import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;

import 'core/android_media_store.dart';
import 'core/apple_music_api.dart';
import 'core/decrypt_session.dart';
import 'core/isobmff.dart';
import 'core/m3u8_resolver.dart';
import 'core/native_media_pipeline.dart';
import 'core/native_output_service.dart';
import 'core/rip_preparation.dart';
import 'grpc/manager_messages.dart';
import 'grpc/wrapper_manager_client.dart';
import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

final class ManagerEndpoint {
  const ManagerEndpoint({
    required this.host,
    required this.port,
    required this.secure,
  });

  factory ManagerEndpoint.parse(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final withScheme = trimmed.contains('://') ? trimmed : 'grpcs://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null ||
        !{'grpc', 'grpcs'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        '请输入 wrapper-manager 地址，例如 grpcs://wm.wol.moe:443',
      );
    }
    final secure = uri.scheme.toLowerCase() == 'grpcs';
    return ManagerEndpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : (secure ? 443 : 80),
      secure: secure,
    );
  }

  final String host;
  final int port;
  final bool secure;

  bool get isLoopback =>
      host == '127.0.0.1' || host == 'localhost' || host == '::1';

  @override
  String toString() {
    final scheme = secure ? 'grpcs' : 'grpc';
    final renderedHost = host.contains(':') ? '[$host]' : host;
    return '$scheme://$renderedHost:$port';
  }
}

abstract interface class ManagerTransport {
  Future<StatusData> status();

  Future<int> login(String username, String password);

  Future<int> submitTwoFactor(String username, String code);

  Future<void> logout(String username);

  Future<void> close();
}

abstract interface class ManagerMediaTransport {
  Stream<DecryptReply> decrypt(Stream<DecryptRequest> requests);

  Future<String> m3u8(String adamId);

  Future<String> lyrics({
    required String adamId,
    required String region,
    required String language,
  });

  Future<String> license({
    required String adamId,
    required String challenge,
    required String uri,
  });

  Future<String> webPlayback(String adamId);
}

final class GrpcManagerTransport
    implements ManagerTransport, ManagerMediaTransport {
  GrpcManagerTransport(ManagerEndpoint endpoint)
      : _channel = grpc.ClientChannel(
          endpoint.host,
          port: endpoint.port,
          options: grpc.ChannelOptions(
            credentials: endpoint.secure
                ? const grpc.ChannelCredentials.secure()
                : const grpc.ChannelCredentials.insecure(),
          ),
        ) {
    _stub = WrapperManagerServiceClient(_channel);
  }

  final grpc.ClientChannel _channel;
  late final WrapperManagerServiceClient _stub;
  StreamController<LoginRequest>? _loginRequests;
  StreamIterator<LoginReply>? _loginReplies;
  String? _loginUsername;
  String? _loginPassword;

  @override
  Future<StatusData> status() async {
    final reply = await _stub.status(
      options: grpc.CallOptions(timeout: const Duration(seconds: 8)),
    );
    _checkHeader(reply.header);
    return reply.data;
  }

  @override
  Future<int> login(String username, String password) async {
    await _closeLogin();
    final requests = StreamController<LoginRequest>();
    _loginRequests = requests;
    _loginReplies = StreamIterator(_stub.login(requests.stream));
    _loginUsername = username;
    _loginPassword = password;
    requests.add(LoginRequest(
      data: LoginData(username: username, password: password),
    ));
    return _readLoginState();
  }

  @override
  Future<int> submitTwoFactor(String username, String code) async {
    final requests = _loginRequests;
    if (requests == null ||
        _loginReplies == null ||
        username != _loginUsername ||
        _loginPassword == null) {
      throw const ApiException('没有等待验证码的登录请求');
    }
    requests.add(LoginRequest(
      data: LoginData(
        username: username,
        password: _loginPassword!,
        twoStepCode: code,
      ),
    ));
    return _readLoginState();
  }

  Future<int> _readLoginState() async {
    final replies = _loginReplies;
    if (replies == null) throw const ApiException('登录流已关闭');
    while (await replies.moveNext()) {
      final header = replies.current.header;
      if (header.code == -1) {
        await _closeLogin();
        throw ApiException(header.msg.isEmpty ? '登录失败' : header.msg);
      }
      if (header.code == 0) {
        await _closeLogin();
        return 0;
      }
      if (header.code == 2) return 2;
    }
    await _closeLogin();
    throw const ApiException('wrapper-manager 提前关闭了登录流');
  }

  @override
  Future<void> logout(String username) async {
    final reply = await _stub.logout(
      LogoutRequest(data: LogoutData(username: username)),
      options: grpc.CallOptions(timeout: const Duration(seconds: 20)),
    );
    _checkHeader(reply.header);
  }

  @override
  Stream<DecryptReply> decrypt(Stream<DecryptRequest> requests) =>
      _stub.decrypt(requests);

  @override
  Future<String> m3u8(String adamId) async {
    final reply = await _stub.m3u8(M3U8Request(adamId: adamId));
    _checkHeader(reply.header);
    return reply.m3u8;
  }

  @override
  Future<String> lyrics({
    required String adamId,
    required String region,
    required String language,
  }) async {
    final reply = await _stub.lyrics(LyricsRequest(
      adamId: adamId,
      region: region,
      language: language,
    ));
    _checkHeader(reply.header);
    return reply.lyrics;
  }

  @override
  Future<String> license({
    required String adamId,
    required String challenge,
    required String uri,
  }) async {
    final reply = await _stub.license(LicenseRequest(
      adamId: adamId,
      challenge: challenge,
      uri: uri,
    ));
    _checkHeader(reply.header);
    return reply.license;
  }

  @override
  Future<String> webPlayback(String adamId) async {
    final reply = await _stub.webPlayback(WebPlaybackRequest(adamId: adamId));
    _checkHeader(reply.header);
    return reply.m3u8;
  }

  void _checkHeader(ReplyHeader header) {
    if (header.code != 0) {
      throw ApiException(
        header.msg.isEmpty ? 'wrapper-manager 请求失败' : header.msg,
      );
    }
  }

  Future<void> _closeLogin() async {
    final requests = _loginRequests;
    final replies = _loginReplies;
    _loginRequests = null;
    _loginReplies = null;
    _loginUsername = null;
    _loginPassword = null;
    await requests?.close();
    await replies?.cancel();
  }

  @override
  Future<void> close() async {
    await _closeLogin();
    await _channel.shutdown();
  }
}

/// Compatibility facade used by the existing GUI while the remaining Python
/// rip pipeline is moved into Dart/Android. Account and status calls already go
/// directly to wrapper-manager gRPC; no FastAPI process is involved.
final class ApiClient {
  ApiClient({required String baseUrl, ManagerTransport? transport})
      : endpoint = ManagerEndpoint.parse(baseUrl),
        _transport = transport ??
            GrpcManagerTransport(ManagerEndpoint.parse(baseUrl));

  final ManagerEndpoint endpoint;
  final ManagerTransport _transport;
  final Set<String> _authenticatedUsers = {};
  AppleMusicApi? _appleMusic;
  DecryptSession? _decryptSession;
  NativeRipCoordinator? _coordinator;
  StreamSubscription<List<NativeRipTask>>? _taskSubscription;
  Future<void>? _nativeInitialization;
  TaskSnapshot _taskSnapshot = const TaskSnapshot(
    tasks: [],
    downloadSpeed: '0.00 kB/s',
    decryptSpeed: '0.00 kB/s',
    running: 0,
  );
  var _closed = false;

  String get baseUrl => endpoint.toString();

  bool get credentialsTransportIsProtected =>
      endpoint.secure || endpoint.isLoopback;

  Future<ServerStatus> health() async {
    try {
      final status = await _transport.status();
      return ServerStatus(
        ready: status.ready,
        regions: status.regions,
        manager: endpoint.toString(),
        authenticatedUsers: List.unmodifiable(_authenticatedUsers),
      );
    } on grpc.GrpcError catch (error) {
      throw ApiException(_grpcMessage(error));
    }
  }

  Future<TaskSnapshot> tasks() async => _taskSnapshot;

  Future<AuthResult> authStatus() async => AuthResult(
        status:
            _authenticatedUsers.isEmpty ? 'signed_out' : 'authenticated',
        authenticatedUsers: List.unmodifiable(_authenticatedUsers),
      );

  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    try {
      final code = await _transport.login(username, password);
      if (code == 2) {
        return AuthResult(
          status: 'requires_2fa',
          username: username,
          authenticatedUsers: List.unmodifiable(_authenticatedUsers),
        );
      }
      _authenticatedUsers.add(username);
      return AuthResult(
        status: 'authenticated',
        username: username,
        authenticatedUsers: List.unmodifiable(_authenticatedUsers),
      );
    } on grpc.GrpcError catch (error) {
      throw ApiException(_grpcMessage(error));
    }
  }

  Future<AuthResult> submitTwoFactor({
    required String username,
    required String code,
  }) async {
    try {
      final result = await _transport.submitTwoFactor(username, code);
      if (result != 0) {
        throw const ApiException('wrapper-manager 未完成登录');
      }
      _authenticatedUsers.add(username);
      return AuthResult(
        status: 'authenticated',
        username: username,
        authenticatedUsers: List.unmodifiable(_authenticatedUsers),
      );
    } on grpc.GrpcError catch (error) {
      throw ApiException(_grpcMessage(error));
    }
  }

  Future<AuthResult> logout(String username) async {
    try {
      await _transport.logout(username);
      _authenticatedUsers.remove(username);
      return AuthResult(
        status:
            _authenticatedUsers.isEmpty ? 'signed_out' : 'authenticated',
        username: username,
        authenticatedUsers: List.unmodifiable(_authenticatedUsers),
      );
    } on grpc.GrpcError catch (error) {
      throw ApiException(_grpcMessage(error));
    }
  }

  Future<void> enqueue({
    required List<String> urls,
    required String codec,
    required String language,
    required bool force,
    required bool includeParticipateSongs,
  }) async {
    if (_closed) throw const ApiException('客户端已关闭');
    await _ensureNativePipeline();
    final parsedCodec = AudioCodec.parse(codec);
    if (parsedCodec == AudioCodec.aacLegacy) {
      throw const ApiException('AAC Legacy/Widevine 路径尚未移植');
    }
    final options = RipPreparationOptions(
      codec: parsedCodec,
      language: language,
      includeParticipateSongs: includeParticipateSongs,
    );
    for (final url in urls) {
      _coordinator!.enqueue(url, options);
    }
  }

  Future<void> cancel(String adamId) async {
    _coordinator?.cancel(adamId);
  }

  Future<void> _ensureNativePipeline() async {
    if (_coordinator != null) return;
    final existing = _nativeInitialization;
    if (existing != null) return existing;
    final mediaManager = _transport;
    if (mediaManager is! ManagerMediaTransport) {
      throw const ApiException('当前 manager transport 不支持媒体 RPC');
    }
    final initialization = _initializeNativePipeline(mediaManager);
    _nativeInitialization = initialization;
    try {
      await initialization;
    } catch (_) {
      if (identical(_nativeInitialization, initialization)) {
        _nativeInitialization = null;
      }
      rethrow;
    }
  }

  Future<void> _initializeNativePipeline(
    ManagerMediaTransport manager,
  ) async {
    final appleMusic = await AppleMusicApi.create();
    if (_closed) {
      appleMusic.close();
      throw const ApiException('客户端已关闭');
    }
    final decryptSession = DecryptSession(manager: manager);
    final pipeline = NativeMediaPipeline(
      appleMusic: appleMusic,
      extractor: const FragmentedMp4Extractor(),
      decryptor: decryptSession,
    );
    const output = NativeOutputService(outputStore: AndroidMediaStore());
    final preparation = RipPreparationService(
      appleMusic: appleMusic,
      manager: manager,
    );
    final coordinator = NativeRipCoordinator(
      appleMusic: appleMusic,
      preparation: preparation,
      mediaHandler: (prepared, onStatus) async {
        final decrypted = await pipeline.process(
          prepared,
          onProgress: (stage) => onStatus(switch (stage) {
            NativeMediaStage.downloading => NativeRipTaskStatus.downloading,
            NativeMediaStage.extracting => NativeRipTaskStatus.extracting,
            NativeMediaStage.decrypting => NativeRipTaskStatus.decrypting,
          }),
        );
        onStatus(NativeRipTaskStatus.packaging);
        await output.save(decrypted);
      },
    );
    _appleMusic = appleMusic;
    _decryptSession = decryptSession;
    _coordinator = coordinator;
    _taskSubscription = coordinator.changes.listen((tasks) {
      _taskSnapshot = _snapshotFrom(tasks);
    });
  }

  static TaskSnapshot _snapshotFrom(List<NativeRipTask> tasks) {
    final mapped = tasks
        .map((task) => DownloadTask(
              adamId: task.id,
              status: _statusName(task.status),
              title: task.title,
              artist: task.artist,
              album: _attribute(task.prepared?.song, 'albumName'),
              error: task.error,
            ))
        .toList(growable: false);
    final running = tasks.where((task) {
      return switch (task.status) {
        NativeRipTaskStatus.waiting ||
        NativeRipTaskStatus.done ||
        NativeRipTaskStatus.expanded ||
        NativeRipTaskStatus.skipped ||
        NativeRipTaskStatus.failed ||
        NativeRipTaskStatus.cancelled =>
          false,
        _ => true,
      };
    }).length;
    return TaskSnapshot(
      tasks: mapped,
      downloadSpeed: '0.00 kB/s',
      decryptSpeed: '0.00 kB/s',
      running: running,
    );
  }

  static String _statusName(NativeRipTaskStatus status) => switch (status) {
        NativeRipTaskStatus.waiting => 'WAITING',
        NativeRipTaskStatus.resolving ||
        NativeRipTaskStatus.preparing ||
        NativeRipTaskStatus.readyForMedia =>
          'PREPARING',
        NativeRipTaskStatus.downloading => 'DOWNLOADING',
        NativeRipTaskStatus.extracting => 'EXTRACTING',
        NativeRipTaskStatus.decrypting => 'DECRYPTING',
        NativeRipTaskStatus.packaging => 'SAVING',
        NativeRipTaskStatus.done => 'DONE',
        NativeRipTaskStatus.expanded => 'EXPANDED',
        NativeRipTaskStatus.skipped => 'SKIPPED',
        NativeRipTaskStatus.failed => 'FAILED',
        NativeRipTaskStatus.cancelled => 'KILLED',
      };

  static String? _attribute(Map<String, dynamic>? resource, String name) {
    final attributes = resource?['attributes'];
    return attributes is Map ? attributes[name]?.toString() : null;
  }

  String _grpcMessage(grpc.GrpcError error) {
    final detail = error.message;
    return detail == null || detail.isEmpty
        ? '无法连接 wrapper-manager gRPC (${error.code})'
        : detail;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_close());
  }

  Future<void> _close() async {
    try {
      await _nativeInitialization;
    } catch (_) {
      // Initialization errors are reported to the enqueue call.
    }
    await _taskSubscription?.cancel();
    await _coordinator?.close();
    await _decryptSession?.close();
    _appleMusic?.close();
    await _transport.close();
  }
}

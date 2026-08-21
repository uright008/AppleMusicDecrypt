import 'dart:async';

import 'package:grpc/grpc.dart' as grpc;

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

final class GrpcManagerTransport implements ManagerTransport {
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

  Stream<DecryptReply> decrypt(Stream<DecryptRequest> requests) =>
      _stub.decrypt(requests);

  Future<String> m3u8(String adamId) async {
    final reply = await _stub.m3u8(M3U8Request(adamId: adamId));
    _checkHeader(reply.header);
    return reply.m3u8;
  }

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

  Future<TaskSnapshot> tasks() async => const TaskSnapshot(
        tasks: [],
        downloadSpeed: '0.00 kB/s',
        decryptSpeed: '0.00 kB/s',
        running: 0,
      );

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
    throw const ApiException('本地下载与媒体封装核心仍在移植中');
  }

  Future<void> cancel(String adamId) async {}

  String _grpcMessage(grpc.GrpcError error) {
    final detail = error.message;
    return detail == null || detail.isEmpty
        ? '无法连接 wrapper-manager gRPC (${error.code})'
        : detail;
  }

  void close() => unawaited(_transport.close());
}

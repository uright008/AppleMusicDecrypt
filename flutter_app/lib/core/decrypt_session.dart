import 'dart:async';

import '../api_client.dart';
import '../grpc/manager_messages.dart';

final class EncryptedSample {
  const EncryptedSample({
    required this.data,
    required this.duration,
    required this.descriptionIndex,
    this.offset,
  });

  final List<int> data;
  final int duration;
  final int descriptionIndex;
  final int? offset;
}

final class DecryptException implements Exception {
  const DecryptException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Long-lived bidirectional decrypt stream equivalent to upstream
/// `WrapperManager.decrypt_init`, including its 15-second keepalive.
abstract interface class SampleDecryptor {
  Future<List<List<int>>> decryptAll({
    required String adamId,
    required List<String> keys,
    required List<EncryptedSample> samples,
  });
}

final class DecryptSession implements SampleDecryptor {
  DecryptSession({
    required ManagerMediaTransport manager,
    this.maxAttempts = 3,
    this.responseTimeout = const Duration(seconds: 30),
    this.retryDelay = const Duration(seconds: 1),
    this.keepaliveInterval = const Duration(seconds: 15),
  }) : _manager = manager {
    _responses = _manager.decrypt(_requests.stream).listen(
          _onReply,
          onError: _onStreamError,
          onDone: _onStreamDone,
          cancelOnError: false,
        );
    _keepalive = Timer.periodic(keepaliveInterval, (_) => _sendKeepalive());
  }

  final ManagerMediaTransport _manager;
  final int maxAttempts;
  final Duration responseTimeout;
  final Duration retryDelay;
  final Duration keepaliveInterval;
  final StreamController<DecryptRequest> _requests = StreamController();
  final Map<({String adamId, int index}), Completer<List<int>>> _pending = {};
  late final StreamSubscription<DecryptReply> _responses;
  late final Timer _keepalive;
  Object? _terminalError;
  var _closed = false;

  int get pendingCount => _pending.length;

  Future<List<int>> decryptSample({
    required String adamId,
    required String key,
    required List<int> sample,
    required int sampleIndex,
  }) async {
    if (_closed) throw const DecryptException('Decrypt stream is closed');
    if (_terminalError != null) throw DecryptException('$_terminalError');
    final correlation = (adamId: adamId, index: sampleIndex);
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_terminalError != null) throw DecryptException('$_terminalError');
      final completer = Completer<List<int>>();
      _pending[correlation] = completer;
      _requests.add(DecryptRequest(
        data: DecryptData(
          adamId: adamId,
          key: key,
          sampleIndex: sampleIndex,
          sample: sample,
        ),
      ));
      try {
        return await completer.future.timeout(responseTimeout);
      } catch (error) {
        if (attempt == maxAttempts) rethrow;
        await Future<void>.delayed(retryDelay);
      } finally {
        if (identical(_pending[correlation], completer)) {
          _pending.remove(correlation);
        }
      }
    }
    throw const DecryptException('Decrypt attempts exhausted');
  }

  @override
  Future<List<List<int>>> decryptAll({
    required String adamId,
    required List<String> keys,
    required List<EncryptedSample> samples,
  }) {
    final futures = <Future<List<int>>>[];
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index];
      if (sample.descriptionIndex < 0 ||
          sample.descriptionIndex >= keys.length) {
        throw RangeError.index(
          sample.descriptionIndex,
          keys,
          'descriptionIndex',
        );
      }
      futures.add(decryptSample(
        adamId: adamId,
        key: keys[sample.descriptionIndex],
        sample: sample.data,
        sampleIndex: index,
      ));
    }
    return Future.wait(futures);
  }

  void _onReply(DecryptReply reply) {
    if (reply.data.adamId == 'KEEPALIVE') return;
    final correlation = (
      adamId: reply.data.adamId,
      index: reply.data.sampleIndex,
    );
    final completer = _pending.remove(correlation);
    if (completer == null || completer.isCompleted) return;
    if (reply.header.code == 0) {
      completer.complete(List<int>.unmodifiable(reply.data.sample));
    } else {
      completer.completeError(DecryptException(
        reply.header.msg.isEmpty ? 'Sample decryption failed' : reply.header.msg,
      ));
    }
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    _terminalError = error;
    _failPending(error, stackTrace);
  }

  void _onStreamDone() {
    if (_closed) return;
    const error = DecryptException('wrapper-manager closed the decrypt stream');
    _terminalError = error;
    _failPending(error, StackTrace.current);
  }

  void _failPending(Object error, StackTrace stackTrace) {
    final completers = _pending.values.toList(growable: false);
    _pending.clear();
    for (final completer in completers) {
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
    }
  }

  void _sendKeepalive() {
    if (_closed || _requests.isClosed) return;
    _requests.add(const DecryptRequest(
      data: DecryptData(adamId: 'KEEPALIVE'),
    ));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _keepalive.cancel();
    const error = DecryptException('Decrypt stream was closed');
    _failPending(error, StackTrace.current);
    await _requests.close();
    await _responses.cancel();
  }
}

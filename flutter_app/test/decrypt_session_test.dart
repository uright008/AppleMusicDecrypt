import 'dart:async';

import 'package:applemusicdecrypt_android/api_client.dart';
import 'package:applemusicdecrypt_android/core/decrypt_session.dart';
import 'package:applemusicdecrypt_android/grpc/manager_messages.dart';
import 'package:flutter_test/flutter_test.dart';

final class _EchoManager implements ManagerMediaTransport {
  final requests = <DecryptData>[];

  @override
  Stream<DecryptReply> decrypt(Stream<DecryptRequest> input) async* {
    await for (final request in input) {
      requests.add(request.data);
      if (request.data.adamId == 'KEEPALIVE') {
        yield const DecryptReply(data: DecryptData(adamId: 'KEEPALIVE'));
        continue;
      }
      yield DecryptReply(
        header: const ReplyHeader(code: 0),
        data: DecryptData(
          adamId: request.data.adamId,
          key: request.data.key,
          sampleIndex: request.data.sampleIndex,
          sample: request.data.sample.reversed.toList(),
        ),
      );
    }
  }

  @override
  Future<String> m3u8(String adamId) async => '';

  @override
  Future<String> lyrics({
    required String adamId,
    required String region,
    required String language,
  }) async =>
      '';

  @override
  Future<String> license({
    required String adamId,
    required String challenge,
    required String uri,
  }) async =>
      '';

  @override
  Future<String> webPlayback(String adamId) async => '';
}

void main() {
  test('decrypts samples on one stream and preserves result order', () async {
    final manager = _EchoManager();
    final session = DecryptSession(
      manager: manager,
      keepaliveInterval: const Duration(days: 1),
    );

    final decrypted = await session.decryptAll(
      adamId: '123',
      keys: const ['key-0', 'key-1'],
      samples: const [
        EncryptedSample(data: [1, 2], duration: 10, descriptionIndex: 1),
        EncryptedSample(data: [3, 4], duration: 20, descriptionIndex: 0),
      ],
    );

    expect(decrypted, [
      [2, 1],
      [4, 3],
    ]);
    expect(manager.requests.map((request) => request.key), ['key-1', 'key-0']);
    expect(session.pendingCount, 0);
    await session.close();
  });

  test('sends keepalive on the existing decrypt stream', () async {
    final manager = _EchoManager();
    final session = DecryptSession(
      manager: manager,
      keepaliveInterval: const Duration(milliseconds: 10),
    );

    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(
      manager.requests.any((request) => request.adamId == 'KEEPALIVE'),
      isTrue,
    );
    await session.close();
  });
}

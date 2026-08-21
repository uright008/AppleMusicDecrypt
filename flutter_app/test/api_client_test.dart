import 'package:applemusicdecrypt_android/api_client.dart';
import 'package:applemusicdecrypt_android/grpc/manager_messages.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeManagerTransport implements ManagerTransport {
  var loginCode = 2;
  var twoFactorCode = 0;
  String? loggedOut;

  @override
  Future<StatusData> status() async => const StatusData(
        status: true,
        regions: ['us'],
        clientCount: 1,
        ready: true,
      );

  @override
  Future<int> login(String username, String password) async => loginCode;

  @override
  Future<int> submitTwoFactor(String username, String code) async =>
      twoFactorCode;

  @override
  Future<void> logout(String username) async => loggedOut = username;

  @override
  Future<void> close() async {}
}

void main() {
  test('normalizes secure and insecure manager endpoints', () {
    expect(
      ManagerEndpoint.parse('wm.wol.moe').toString(),
      'grpcs://wm.wol.moe:443',
    );
    expect(
      ManagerEndpoint.parse('grpc://192.168.1.7:8080/').toString(),
      'grpc://192.168.1.7:8080',
    );
    expect(
      () => ManagerEndpoint.parse('http://192.168.1.7:8080'),
      throwsFormatException,
    );
  });

  test('status is read directly from manager transport', () async {
    final api = ApiClient(
      baseUrl: 'grpcs://wm.wol.moe:443',
      transport: _FakeManagerTransport(),
    );

    final status = await api.health();

    expect(status.ready, isTrue);
    expect(status.regions, ['us']);
    expect(status.manager, 'grpcs://wm.wol.moe:443');
  });

  test('login keeps the bidirectional stream open for 2FA', () async {
    final transport = _FakeManagerTransport();
    final api = ApiClient(
      baseUrl: 'grpcs://wm.wol.moe:443',
      transport: transport,
    );

    final first = await api.login(
      username: 'listener@example.com',
      password: 'secret',
    );
    expect(first.requiresTwoFactor, isTrue);

    final verified = await api.submitTwoFactor(
      username: 'listener@example.com',
      code: '123456',
    );
    expect(verified.isAuthenticated, isTrue);
    expect(verified.authenticatedUsers, ['listener@example.com']);

    final logout = await api.logout('listener@example.com');
    expect(logout.status, 'signed_out');
    expect(transport.loggedOut, 'listener@example.com');
  });

  test('manager proto wire codec preserves decrypt samples', () {
    const original = DecryptReply(
      header: ReplyHeader(code: -1, msg: 'failed'),
      data: DecryptData(
        adamId: '123',
        key: 'skd://key',
        sampleIndex: 7,
        sample: [1, 2, 3, 255],
      ),
    );

    final decoded = DecryptReply.fromBuffer(original.writeToBuffer());

    expect(decoded.header.code, -1);
    expect(decoded.header.msg, 'failed');
    expect(decoded.data.adamId, '123');
    expect(decoded.data.sampleIndex, 7);
    expect(decoded.data.sample, [1, 2, 3, 255]);
  });
}

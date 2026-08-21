import 'dart:convert';

import 'package:applemusicdecrypt_android/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('health parses server response', () async {
    final client = MockClient((request) async => http.Response(
          '{"ready":true,"regions":["us"],"manager":"wm.example",'
          '"authenticatedUsers":["listener@example.com"]}',
          200,
          headers: {'content-type': 'application/json'},
        ));
    final api = ApiClient(baseUrl: 'http://127.0.0.1:10020/', client: client);

    final status = await api.health();

    expect(status.ready, isTrue);
    expect(status.regions, ['us']);
    expect(status.authenticatedUsers, ['listener@example.com']);
    expect(api.baseUrl, 'http://127.0.0.1:10020');
  });

  test('login with 2FA and logout use the auth API', () async {
    final client = MockClient((request) async {
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;
      if (request.url.path.endsWith('/auth/login')) {
        expect(body['username'], 'listener@example.com');
        expect(body['password'], 'secret');
        return http.Response(
          '{"status":"requires_2fa","username":"listener@example.com",'
          '"authenticatedUsers":[]}',
          200,
        );
      }
      if (request.url.path.endsWith('/auth/2fa')) {
        expect(body['username'], 'listener@example.com');
        expect(body['code'], '123456');
        return http.Response(
          '{"status":"authenticated","username":"listener@example.com",'
          '"authenticatedUsers":["listener@example.com"]}',
          200,
        );
      }
      if (request.method == 'DELETE') {
        expect(request.url.pathSegments.last, 'listener@example.com');
        return http.Response(
          '{"status":"signed_out","username":"listener@example.com",'
          '"authenticatedUsers":[]}',
          200,
        );
      }
      return http.Response('{"detail":"unexpected request"}', 500);
    });
    final api = ApiClient(baseUrl: 'https://backend.example', client: client);

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
  });

  test('detects remote plain HTTP for credential warning', () {
    final api = ApiClient(baseUrl: 'http://192.168.1.7:8080');
    expect(api.credentialsTransportIsProtected, isFalse);
    api.close();
  });

  test('throws API detail for error response', () async {
    final client = MockClient((request) async => http.Response(
          '{"detail":"offline"}',
          503,
          headers: {'content-type': 'application/json'},
        ));
    final api = ApiClient(baseUrl: 'http://127.0.0.1:10020', client: client);

    expect(api.health(), throwsA(isA<ApiException>()));
  });
}

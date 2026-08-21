import 'package:applemusicdecrypt_android/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('health parses server response', () async {
    final client = MockClient((request) async => http.Response(
          '{"ready":true,"regions":["us"],"manager":"wm.example"}',
          200,
          headers: {'content-type': 'application/json'},
        ));
    final api = ApiClient(baseUrl: 'http://127.0.0.1:10020/', client: client);

    final status = await api.health();

    expect(status.ready, isTrue);
    expect(status.regions, ['us']);
    expect(api.baseUrl, 'http://127.0.0.1:10020');
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

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({required String baseUrl, http.Client? client})
      : baseUrl = _normalizeBaseUrl(baseUrl),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      throw const FormatException('请输入完整的 HTTP 或 HTTPS API 地址');
    }
    return normalized;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  bool get credentialsTransportIsProtected {
    final uri = Uri.parse(baseUrl);
    return uri.scheme == 'https' ||
        uri.host == '127.0.0.1' ||
        uri.host == 'localhost' ||
        uri.host == '::1';
  }

  Future<ServerStatus> health() async {
    final response = await _client
        .get(_uri('/api/v1/health'))
        .timeout(const Duration(seconds: 8));
    return ServerStatus.fromJson(_decode(response));
  }

  Future<TaskSnapshot> tasks() async {
    final response = await _client
        .get(_uri('/api/v1/tasks'))
        .timeout(const Duration(seconds: 8));
    return TaskSnapshot.fromJson(_decode(response));
  }

  Future<AuthResult> authStatus() async {
    final response = await _client
        .get(_uri('/api/v1/auth'))
        .timeout(const Duration(seconds: 8));
    return AuthResult.fromJson(_decode(response));
  }

  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    final response = await _client
        .post(
          _uri('/api/v1/auth/login'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 55));
    return AuthResult.fromJson(_decode(response));
  }

  Future<AuthResult> submitTwoFactor({
    required String username,
    required String code,
  }) async {
    final response = await _client
        .post(
          _uri('/api/v1/auth/2fa'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'username': username, 'code': code}),
        )
        .timeout(const Duration(seconds: 70));
    return AuthResult.fromJson(_decode(response));
  }

  Future<AuthResult> logout(String username) async {
    final encodedUsername = Uri.encodeComponent(username);
    final response = await _client
        .delete(_uri('/api/v1/auth/$encodedUsername'))
        .timeout(const Duration(seconds: 20));
    return AuthResult.fromJson(_decode(response));
  }

  Future<void> enqueue({
    required List<String> urls,
    required String codec,
    required String language,
    required bool force,
    required bool includeParticipateSongs,
  }) async {
    final response = await _client
        .post(
          _uri('/api/v1/downloads'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'urls': urls,
            'codec': codec,
            'language': language,
            'force': force,
            'include_participate_songs': includeParticipateSongs,
          }),
        )
        .timeout(const Duration(seconds: 12));
    _decode(response);
  }

  Future<void> cancel(String adamId) async {
    final response = await _client
        .delete(_uri('/api/v1/tasks/$adamId'))
        .timeout(const Duration(seconds: 8));
    _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = <String, dynamic>{'detail': response.body};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map<String, dynamic>
          ? decoded['detail']?.toString()
          : null;
      throw ApiException(
        detail ?? 'API 请求失败 (${response.statusCode})',
        response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('API 返回了无效数据');
    }
    return decoded;
  }

  void close() => _client.close();
}

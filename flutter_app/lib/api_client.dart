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
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('请输入完整的 API 地址');
    }
    return normalized;
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

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

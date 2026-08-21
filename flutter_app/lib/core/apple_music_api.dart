import 'dart:convert';

import 'package:http/http.dart' as http;

abstract interface class AppleMusicDataSource {
  Future<Map<String, dynamic>?> getSongInfo({
    required String songId,
    required String storefront,
    required String language,
  });

  Future<Map<String, dynamic>> getAlbumInfo({
    required String albumId,
    required String storefront,
    required String language,
  });

  Future<List<int>> getCover(
    String templateUrl, {
    required String format,
    required String size,
  });

  Future<String> downloadM3u8(String url);

  Future<String> resolveUrl(String url);
}

final class AppleMusicApiException implements Exception {
  const AppleMusicApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Dart port of the HTTP/catalog responsibilities in upstream `src/api.py`.
final class AppleMusicApi implements AppleMusicDataSource {
  AppleMusicApi._({required http.Client client, required String token})
      : _client = client,
        _headers = {
          'authorization': 'Bearer $token',
          'user-agent': _userAgent,
          'origin': 'https://music.apple.com',
        };

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/91.0.4472.124 Safari/537.36';

  static Future<AppleMusicApi> create({http.Client? client}) async {
    final resolvedClient = client ?? http.Client();
    final token = await discoverToken(resolvedClient);
    return AppleMusicApi._(client: resolvedClient, token: token);
  }

  static Future<String> discoverToken(http.Client client) async {
    final home = await client.get(Uri.https('music.apple.com', '/'));
    _ensureSuccess(home);
    final asset = RegExp(r'/assets/index~[^/]+\.js')
        .firstMatch(home.body)
        ?.group(0);
    if (asset == null) {
      throw const AppleMusicApiException('无法在 Apple Music 首页找到 API 脚本');
    }
    final javascript = await client.get(Uri.https('music.apple.com', asset));
    _ensureSuccess(javascript);
    final token = RegExp(
      r'eyJ[A-Za-z0-9_=-]+\.[A-Za-z0-9_=-]+\.[A-Za-z0-9_=-]+',
    ).firstMatch(javascript.body)?.group(0);
    if (token == null) {
      throw const AppleMusicApiException('无法从 Apple Music 脚本提取 API token');
    }
    return token;
  }

  final http.Client _client;
  final Map<String, String> _headers;

  Future<Map<String, dynamic>> getAlbumInfo({
    required String albumId,
    required String storefront,
    required String language,
  }) =>
      _getJson(
        _catalogUri(storefront, '/albums/$albumId', {
          'omit[resource]': 'autos',
          'include': 'tracks,artists,record-labels',
          'include[songs]': 'artists',
          'fields[artists]': 'name',
          'fields[albums:albums]':
              'artistName,artwork,name,releaseDate,url',
          'fields[record-labels]': 'name',
          'l': language,
        }),
      );

  Future<List<Map<String, dynamic>>> getAlbumTracks({
    required String albumId,
    required String storefront,
  }) =>
      _pagedCatalog(
        storefront: storefront,
        path: '/albums/$albumId/tracks',
        pageSize: 300,
      );

  Future<Map<String, dynamic>> getPlaylistInfo({
    required String playlistId,
    required String storefront,
    required String language,
  }) =>
      _getJson(_catalogUri(
        storefront,
        '/playlists/$playlistId',
        {'l': language},
      ));

  Future<List<Map<String, dynamic>>> getPlaylistTracks({
    required String playlistId,
    required String storefront,
    required String language,
  }) =>
      _pagedCatalog(
        storefront: storefront,
        path: '/playlists/$playlistId/tracks',
        pageSize: 100,
        baseQuery: {'l': language},
      );

  Future<Map<String, dynamic>?> getSongInfo({
    required String songId,
    required String storefront,
    required String language,
  }) async {
    final body = await _getJson(_catalogUri(storefront, '/songs/$songId', {
      'extend': 'extendedAssetUrls',
      'include': 'albums,explicit',
      'l': language,
    }));
    for (final item in _data(body)) {
      if (item['id']?.toString() == songId) return item;
    }
    return null;
  }

  Future<Map<String, dynamic>> getArtistInfo({
    required String artistId,
    required String storefront,
    required String language,
  }) =>
      _getJson(_catalogUri(
        storefront,
        '/artists/$artistId',
        {'l': language},
      ));

  Future<List<String>> getAlbumsFromArtist({
    required String artistId,
    required String storefront,
    required String language,
  }) =>
      _artistResourceUrls(
        artistId: artistId,
        storefront: storefront,
        language: language,
        resource: 'albums',
        pageSize: 25,
      );

  Future<List<String>> getSongsFromArtist({
    required String artistId,
    required String storefront,
    required String language,
  }) =>
      _artistResourceUrls(
        artistId: artistId,
        storefront: storefront,
        language: language,
        resource: 'songs',
        pageSize: 20,
      );

  Future<bool> songExists(String songId, String storefront) =>
      _exists(_catalogUri(storefront, '/songs/$songId'));

  Future<bool> albumExists(String albumId, String storefront) =>
      _exists(_catalogUri(storefront, '/albums/$albumId'));

  Future<Map<String, dynamic>?> getAlbumByUpc(
    String upc,
    String storefront,
  ) async {
    final result = await _getJson(_catalogUri(
      storefront,
      '/albums',
      {'filter[upc]': upc},
    ));
    return _data(result).isEmpty ? null : result;
  }

  Future<List<int>> getCover(
    String templateUrl, {
    required String format,
    required String size,
  }) {
    final url = templateUrl
        .replaceFirst('bb.jpg', 'bb.$format')
        .replaceAll('{w}x{h}', size);
    return downloadBytes(url);
  }

  Future<List<int>> downloadBytes(String url) async {
    final response = await _client.get(Uri.parse(url));
    _ensureSuccess(response);
    final declaredLength = int.tryParse(
      response.headers['content-length'] ??
          response.headers['x-apple-ms-content-length'] ??
          '',
    );
    if (declaredLength != null && response.bodyBytes.length != declaredLength) {
      throw AppleMusicApiException(
        '下载长度不完整：${response.bodyBytes.length}/$declaredLength',
      );
    }
    return response.bodyBytes;
  }

  Future<String> downloadM3u8(String url) async {
    final response = await _client.get(Uri.parse(url), headers: _headers);
    _ensureSuccess(response);
    return utf8.decode(response.bodyBytes);
  }

  Future<String> resolveUrl(String url) async {
    final response = await _client.get(Uri.parse(url), headers: _headers);
    _ensureSuccess(response);
    return response.request?.url.toString() ?? url;
  }

  Future<List<Map<String, dynamic>>> _pagedCatalog({
    required String storefront,
    required String path,
    required int pageSize,
    Map<String, String> baseQuery = const {},
  }) async {
    final result = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final body = await _getJson(_catalogUri(storefront, path, {
        ...baseQuery,
        'offset': '$offset',
      }));
      result.addAll(_data(body));
      if (body['next'] == null) return List.unmodifiable(result);
      offset += pageSize;
    }
  }

  Future<List<String>> _artistResourceUrls({
    required String artistId,
    required String storefront,
    required String language,
    required String resource,
    required int pageSize,
  }) async {
    final rows = await _pagedCatalog(
      storefront: storefront,
      path: '/artists/$artistId/$resource',
      pageSize: pageSize,
      baseQuery: {'l': language},
    );
    return rows
        .map((row) => (row['attributes'] as Map?)?['url']?.toString())
        .whereType<String>()
        .toSet()
        .toList(growable: false);
  }

  Future<bool> _exists(Uri uri) async {
    final request = http.Request('HEAD', uri)..headers.addAll(_headers);
    final response = await _client.send(request);
    return response.statusCode == 200;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(uri, headers: _headers);
    _ensureSuccess(response);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const AppleMusicApiException('Apple Music API 返回了无效 JSON');
    }
    return decoded;
  }

  static Uri _catalogUri(
    String storefront,
    String path, [
    Map<String, String>? query,
  ]) =>
      Uri.https(
        'amp-api.music.apple.com',
        '/v1/catalog/$storefront$path',
        query,
      );

  static List<Map<String, dynamic>> _data(Map<String, dynamic> body) =>
      (body['data'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

  static void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppleMusicApiException(
        'HTTP ${response.statusCode}: ${response.request?.url ?? ''}',
      );
    }
  }

  void close() => _client.close();
}

import 'package:applemusicdecrypt_android/core/apple_music_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('discovers bearer token using the same bootstrap as upstream', () async {
    const token = 'eyJheader.payload.signature';
    final client = MockClient((request) async {
      if (request.url.path == '/') {
        return http.Response('<script src="/assets/index~abc.js"></script>', 200);
      }
      return http.Response('window.token="$token";', 200);
    });

    expect(await AppleMusicApi.discoverToken(client), token);
  });

  test('fetches a song with upstream catalog query fields', () async {
    const token = 'eyJheader.payload.signature';
    final client = MockClient((request) async {
      if (request.url.host == 'music.apple.com') {
        return request.url.path == '/'
            ? http.Response('/assets/index~abc.js', 200)
            : http.Response(token, 200);
      }
      expect(request.headers['authorization'], 'Bearer $token');
      expect(request.url.path, '/v1/catalog/us/songs/123');
      expect(request.url.queryParameters['extend'], 'extendedAssetUrls');
      return http.Response(
        '{"data":[{"id":"123","attributes":{"name":"Song"}}]}',
        200,
      );
    });
    final api = await AppleMusicApi.create(client: client);

    final song = await api.getSongInfo(
      songId: '123',
      storefront: 'us',
      language: 'en-US',
    );

    expect(song?['id'], '123');
  });

  test('walks paginated playlist tracks', () async {
    const token = 'eyJheader.payload.signature';
    final client = MockClient((request) async {
      if (request.url.host == 'music.apple.com') {
        return request.url.path == '/'
            ? http.Response('/assets/index~abc.js', 200)
            : http.Response(token, 200);
      }
      final offset = request.url.queryParameters['offset'];
      return offset == '0'
          ? http.Response('{"data":[{"id":"1"}],"next":"page2"}', 200)
          : http.Response('{"data":[{"id":"2"}]}', 200);
    });
    final api = await AppleMusicApi.create(client: client);

    final tracks = await api.getPlaylistTracks(
      playlistId: 'pl.test',
      storefront: 'us',
      language: 'en-US',
    );

    expect(tracks.map((item) => item['id']), ['1', '2']);
  });
}

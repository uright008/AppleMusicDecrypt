import 'package:applemusicdecrypt_android/api_client.dart';
import 'package:applemusicdecrypt_android/core/apple_music_api.dart';
import 'package:applemusicdecrypt_android/core/apple_music_url.dart';
import 'package:applemusicdecrypt_android/core/m3u8_resolver.dart';
import 'package:applemusicdecrypt_android/core/rip_preparation.dart';
import 'package:applemusicdecrypt_android/grpc/manager_messages.dart';
import 'package:flutter_test/flutter_test.dart';

const _master = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-alac-stereo-96000-24",SAMPLE-RATE=96000,BIT-DEPTH=24
#EXT-X-STREAM-INF:BANDWIDTH=1000000,AVERAGE-BANDWIDTH=900000,AUDIO="audio-alac-stereo-96000-24"
media/playlist.m3u8
''';

const _media = '''
#EXTM3U
#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://itunes.apple.com/key/c23"
#EXT-X-MAP:URI="song.mp4"
''';

final class _FakeAppleMusic implements AppleMusicDataSource {
  @override
  Future<Map<String, dynamic>?> getSongInfo({
    required String songId,
    required String storefront,
    required String language,
  }) async =>
      {
        'id': songId,
        'attributes': {
          'name': 'Test Song',
          'artistName': 'Test Artist',
          'hasTimeSyncedLyrics': true,
          'artwork': {'url': 'https://example.test/{w}x{h}/bb.jpg'},
          'extendedAssetUrls': {
            'enhancedHls': 'https://example.test/catalog-master.m3u8',
          },
        },
        'relationships': {
          'albums': {
            'data': [
              {'id': 'album-1'},
            ],
          },
        },
      };

  @override
  Future<Map<String, dynamic>> getAlbumInfo({
    required String albumId,
    required String storefront,
    required String language,
  }) async => {
        'data': [
          {
            'id': albumId,
            'attributes': {
              'name': 'Test Album',
              'artistName': 'Test Artist',
            },
            'relationships': {
              'tracks': {
                'data': [
                  {'id': '123'},
                ],
              },
            },
          },
        ],
      };

  @override
  Future<List<Map<String, dynamic>>> getAlbumTracks({
    required String albumId,
    required String storefront,
  }) async => [
        {'id': '123'},
      ];

  @override
  Future<Map<String, dynamic>> getPlaylistInfo({
    required String playlistId,
    required String storefront,
    required String language,
  }) async =>
      {'data': <Object>[]};

  @override
  Future<List<Map<String, dynamic>>> getPlaylistTracks({
    required String playlistId,
    required String storefront,
    required String language,
  }) async =>
      [];

  @override
  Future<Map<String, dynamic>> getArtistInfo({
    required String artistId,
    required String storefront,
    required String language,
  }) async =>
      {'data': <Object>[]};

  @override
  Future<List<String>> getAlbumsFromArtist({
    required String artistId,
    required String storefront,
    required String language,
  }) async =>
      [];

  @override
  Future<List<String>> getSongsFromArtist({
    required String artistId,
    required String storefront,
    required String language,
  }) async =>
      [];

  @override
  Future<List<int>> getCover(
    String templateUrl, {
    required String format,
    required String size,
  }) async =>
      [1, 2, 3];

  @override
  Future<String> downloadM3u8(String url) async =>
      url.endsWith('playlist.m3u8') ? _media : _master;

  @override
  Future<String> resolveUrl(String url) async => url;
}

final class _FakeManager implements ManagerMediaTransport {
  var m3u8Requests = 0;

  @override
  Future<String> m3u8(String adamId) async {
    m3u8Requests++;
    return 'https://example.test/master.m3u8';
  }

  @override
  Future<String> lyrics({
    required String adamId,
    required String region,
    required String language,
  }) async =>
      '<tt>lyrics</tt>';

  @override
  Stream<DecryptReply> decrypt(Stream<DecryptRequest> requests) =>
      const Stream.empty();

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
  test('prepares metadata, lyrics, cover and ALAC media like upstream', () async {
    final appleMusic = _FakeAppleMusic();
    final manager = _FakeManager();
    final service = RipPreparationService(
      appleMusic: appleMusic,
      manager: manager,
    );
    final url = AppleMusicUrl.tryParse(
      'https://music.apple.com/us/song/test/123',
    )!;

    final prepared = await service.prepareSong(
      url,
      const RipPreparationOptions(
        codec: AudioCodec.alac,
        language: 'en-US',
      ),
    );

    expect(manager.m3u8Requests, 1);
    expect(prepared.title, 'Test Song');
    expect(prepared.artist, 'Test Artist');
    expect(prepared.cover, [1, 2, 3]);
    expect(prepared.lyrics, '<tt>lyrics</tt>');
    expect(prepared.media.uri, 'https://example.test/media/song.mp4');
  });

  test('bounded coordinator advances a song to native media boundary', () async {
    final appleMusic = _FakeAppleMusic();
    final service = RipPreparationService(
      appleMusic: appleMusic,
      manager: _FakeManager(),
    );
    final coordinator = NativeRipCoordinator(
      appleMusic: appleMusic,
      preparation: service,
      maxRunningTasks: 1,
    );
    final ready = coordinator.changes.firstWhere(
      (tasks) => tasks.single.status == NativeRipTaskStatus.readyForMedia,
    );

    coordinator.enqueue(
      'https://music.apple.com/us/song/test/123',
      const RipPreparationOptions(
        codec: AudioCodec.alac,
        language: 'en-US',
      ),
    );
    final tasks = await ready;

    expect(tasks.single.adamId, '123');
    expect(tasks.single.title, 'Test Song');
    expect(tasks.single.prepared?.media.keys, contains(M3u8Resolver.prefetchKey));
    await coordinator.close();
  });

  test('album task expands into deduplicated song tasks', () async {
    final appleMusic = _FakeAppleMusic();
    final coordinator = NativeRipCoordinator(
      appleMusic: appleMusic,
      preparation: RipPreparationService(
        appleMusic: appleMusic,
        manager: _FakeManager(),
      ),
      maxRunningTasks: 1,
    );
    final finished = coordinator.changes.firstWhere(
      (tasks) =>
          tasks.any((task) => task.status == NativeRipTaskStatus.expanded) &&
          tasks.any((task) => task.status == NativeRipTaskStatus.readyForMedia),
    );

    coordinator.enqueue(
      'https://music.apple.com/us/album/test/456',
      const RipPreparationOptions(
        codec: AudioCodec.alac,
        language: 'en-US',
      ),
    );
    final tasks = await finished;

    expect(tasks, hasLength(2));
    expect(
      tasks.firstWhere((task) => task.status == NativeRipTaskStatus.expanded)
          .childCount,
      1,
    );
    expect(tasks.last.adamId, '123');
    await coordinator.close();
  });
}

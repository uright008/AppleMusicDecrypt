import 'package:applemusicdecrypt_android/core/apple_music_metadata.dart';
import 'package:applemusicdecrypt_android/core/apple_music_url.dart';
import 'package:applemusicdecrypt_android/core/m3u8_resolver.dart';
import 'package:applemusicdecrypt_android/core/rip_preparation.dart';
import 'package:flutter_test/flutter_test.dart';

PreparedSong _prepared({RipOutputContext? outputContext}) => PreparedSong(
      url: AppleMusicUrl.tryParse(
        'https://music.apple.com/us/song/test/123456789',
      )!,
      song: {
        'attributes': {
          'name': 'Song: Name?',
          'artistName': 'Artist',
          'albumName': 'Album',
          'composerName': 'Composer',
          'genreNames': ['Pop', 'Music'],
          'releaseDate': '2026-01-02',
          'trackNumber': 3,
          'discNumber': 1,
          'contentRating': 'explicit',
          'isrc': 'US-AAA-26-00001',
        },
        'relationships': {
          'albums': {
            'data': [
              {
                'id': '987654321',
                'attributes': {
                  'artistName': 'Album Artist',
                  'releaseDate': '2026-01-01',
                  'copyright': 'Copyright',
                  'recordLabel': 'Label',
                  'upc': '123456789012',
                },
              },
            ],
          },
          'artists': {
            'data': [
              {'id': '11223344'},
            ],
          },
        },
      },
      album: {
        'data': [
          {
            'id': '987654321',
            'attributes': {
              'name': 'Album',
              'artistName': 'Album Artist',
            },
            'relationships': {
              'tracks': {
                'data': [
                  {
                    'attributes': {'discNumber': 1, 'trackNumber': 4},
                  },
                  {
                    'attributes': {'discNumber': 2, 'trackNumber': 2},
                  },
                ],
              },
            },
          },
        ],
      },
      media: const M3u8Info(
        uri: 'https://example.test/song.mp4',
        keys: [],
        codecId: 'audio-alac-stereo-48000-24',
      ),
      cover: const [0xff, 0xd8, 0xff],
      lyrics: '''
<tt><body><div>
<p begin="00:01.250">First &amp; line</p>
<p begin="01:02.500">Second</p>
</div></body></tt>
''',
      outputContext: outputContext,
    );

void main() {
  test('matches upstream album directory and filename templates', () {
    final metadata = AppleMusicMetadata.fromPrepared(_prepared());

    expect(
      metadata.relativePath,
      'AppleMusicDecrypt/Album Artist/Album',
    );
    expect(metadata.fileBaseName, '1-03 Song Name');
    expect(metadata.trackTotal, 4);
    expect(metadata.discTotal, 2);
    expect(metadata.lyrics, '[00:01.25]First & line\n[01:02.50]Second');
    expect(metadata.rating, 1);
    expect(metadata.recordCompany, 'Label');
  });

  test('matches upstream playlist directory and filename templates', () {
    final metadata = AppleMusicMetadata.fromPrepared(_prepared(
      outputContext: const RipOutputContext(
        playlistName: 'My / Playlist',
        playlistCuratorName: 'Curator',
        playlistIndex: 7,
      ),
    ));

    expect(
      metadata.relativePath,
      'AppleMusicDecrypt/playlists/My  Playlist',
    );
    expect(metadata.fileBaseName, '07. Artist - Song Name');
  });
}

import 'dart:typed_data';

import 'package:applemusicdecrypt_android/core/android_media_store.dart';
import 'package:applemusicdecrypt_android/core/apple_music_url.dart';
import 'package:applemusicdecrypt_android/core/isobmff.dart';
import 'package:applemusicdecrypt_android/core/m3u8_resolver.dart';
import 'package:applemusicdecrypt_android/core/native_media_pipeline.dart';
import 'package:applemusicdecrypt_android/core/native_output_service.dart';
import 'package:applemusicdecrypt_android/core/rip_preparation.dart';
import 'package:flutter_test/flutter_test.dart';

final class _OutputStore implements AudioOutputStore {
  final calls = <({String displayName, String mimeType, String relativePath})>[];
  Uint8List? bytes;
  String? displayName;
  String? mimeType;
  String? relativePath;

  @override
  Future<String> saveAudio({
    required Uint8List bytes,
    required String displayName,
    required String mimeType,
    String relativePath = 'AppleMusicDecrypt',
  }) async {
    this.bytes = bytes;
    this.displayName = displayName;
    this.mimeType = mimeType;
    this.relativePath = relativePath;
    calls.add((
      displayName: displayName,
      mimeType: mimeType,
      relativePath: relativePath,
    ));
    return 'content://media/external/downloads/7';
  }
}

DecryptedSong _song(
  String title, {
  List<int>? cover,
  String? lyrics,
  RipOutputContext? outputContext,
}) =>
    DecryptedSong(
      prepared: PreparedSong(
        url: AppleMusicUrl.tryParse(
          'https://music.apple.com/us/song/test/123',
        )!,
        song: {
          'attributes': {
            'name': title,
            'artistName': 'Test Artist',
            'albumName': 'Test Album',
            'trackNumber': 2,
            'discNumber': 1,
          },
        },
        album: const {
          'data': [
            {
              'attributes': {
                'name': 'Test Album',
                'artistName': 'Test Artist',
              },
            },
          ],
        },
        media: const M3u8Info(
          uri: 'https://example.test/song.mp4',
          keys: [],
          codecId: 'audio-ec3-7680',
        ),
        cover: cover,
        lyrics: lyrics,
        outputContext: outputContext,
      ),
      fragmented: FragmentedSong(
        codec: AudioCodec.ec3,
        raw: Uint8List(0),
        samples: const [],
      ),
      decryptedSamples: const [
        [1, 2, 3],
      ],
      decryptedMedia: Uint8List.fromList([1, 2, 3]),
    );

void main() {
  test('packages and saves raw Atmos output', () async {
    final store = _OutputStore();
    final service = NativeOutputService(outputStore: store);

    final saved = await service.save(
      _song('Test Song'),
    );

    expect(saved.uri, 'content://media/external/downloads/7');
    expect(saved.displayName, '1-02 Test Song.ec3');
    expect(store.bytes, [1, 2, 3]);
    expect(store.mimeType, 'audio/eac3');
    expect(
      store.relativePath,
      'AppleMusicDecrypt/Test Artist/Test Album',
    );
  });

  test('saves upstream-compatible cover and LRC sidecars', () async {
    final store = _OutputStore();
    final service = NativeOutputService(outputStore: store);

    await service.save(_song(
      'Test Song',
      cover: const [0xff, 0xd8, 0xff],
      lyrics: '<tt><body><div><p begin="1.25s">Line</p></div></body></tt>',
    ));

    expect(
      store.calls.map((call) => call.displayName),
      ['1-02 Test Song.ec3', 'cover.jpg', '1-02 Test Song.lrc'],
    );
    expect(
      store.calls.map((call) => call.relativePath).toSet(),
      {'AppleMusicDecrypt/Test Artist/Test Album'},
    );
  });
}

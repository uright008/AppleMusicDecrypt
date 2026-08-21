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
    return 'content://media/external/audio/media/7';
  }
}

DecryptedSong _song(String title) => DecryptedSong(
      prepared: PreparedSong(
        url: AppleMusicUrl.tryParse(
          'https://music.apple.com/us/song/test/123',
        )!,
        song: {
          'attributes': {'name': title},
        },
        album: const {},
        media: const M3u8Info(
          uri: 'https://example.test/song.mp4',
          keys: [],
          codecId: 'audio-ec3-7680',
        ),
        cover: null,
        lyrics: null,
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
      _song('Bad / Song: Name?'),
      relativePath: 'AppleMusicDecrypt/Atmos',
    );

    expect(saved.uri, 'content://media/external/audio/media/7');
    expect(saved.displayName, 'Bad _ Song_ Name_.ec3');
    expect(store.bytes, [1, 2, 3]);
    expect(store.mimeType, 'audio/eac3');
    expect(store.relativePath, 'AppleMusicDecrypt/Atmos');
  });
}

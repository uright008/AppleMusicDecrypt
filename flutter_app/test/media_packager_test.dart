import 'dart:typed_data';

import 'package:applemusicdecrypt_android/core/apple_music_url.dart';
import 'package:applemusicdecrypt_android/core/isobmff.dart';
import 'package:applemusicdecrypt_android/core/m3u8_resolver.dart';
import 'package:applemusicdecrypt_android/core/media_packager.dart';
import 'package:applemusicdecrypt_android/core/native_media_pipeline.dart';
import 'package:applemusicdecrypt_android/core/rip_preparation.dart';
import 'package:flutter_test/flutter_test.dart';

DecryptedSong _song(AudioCodec codec) => DecryptedSong(
      prepared: PreparedSong(
        url: AppleMusicUrl.tryParse(
          'https://music.apple.com/us/song/test/123',
        )!,
        song: const {},
        album: const {},
        media: M3u8Info(
          uri: 'https://example.test/song.mp4',
          keys: const [],
          codecId: codec == AudioCodec.ec3
              ? 'audio-ec3-7680'
              : 'audio-alac-stereo-96000-24',
        ),
        cover: null,
        lyrics: null,
      ),
      fragmented: FragmentedSong(
        codec: codec,
        raw: Uint8List(0),
        samples: const [],
      ),
      decryptedSamples: const [
        [1, 2],
        [3],
      ],
      decryptedMedia: Uint8List.fromList([1, 2, 3]),
    );

void main() {
  test('emits upstream-compatible raw EC3 output', () {
    final packaged = const MediaPackager().package(_song(AudioCodec.ec3));

    expect(packaged.extension, '.ec3');
    expect(packaged.mimeType, 'audio/eac3');
    expect(packaged.bytes, [1, 2, 3]);
  });

  test('does not pretend unfinished ALAC muxing is complete', () {
    expect(
      () => const MediaPackager().package(_song(AudioCodec.alac)),
      throwsA(isA<PackagingNotImplementedException>()),
    );
  });
}

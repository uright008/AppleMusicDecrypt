import 'dart:typed_data';

import 'package:applemusicdecrypt_android/core/apple_music_url.dart';
import 'package:applemusicdecrypt_android/core/decrypt_session.dart';
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

Uint8List _box(String type, List<int> payload) {
  final result = Uint8List(8 + payload.length);
  ByteData.sublistView(result).setUint32(0, result.length);
  result.setRange(4, 8, type.codeUnits);
  result.setRange(8, result.length, payload);
  return result;
}

DecryptedSong _m4aSong() {
  final ftyp = _box('ftyp', [
    ...'iso6'.codeUnits,
    0,
    0,
    0,
    1,
  ]);
  final mdat = _box('mdat', [1, 2, 3]);
  return DecryptedSong(
    prepared: _song(AudioCodec.alac).prepared,
    fragmented: FragmentedSong(
      codec: AudioCodec.alac,
      raw: Uint8List.fromList([...ftyp, ...mdat]),
      samples: [
        EncryptedSample(
          data: const [1, 2, 3],
          duration: 1024,
          descriptionIndex: 0,
          offset: ftyp.length + 8,
        ),
      ],
    ),
    decryptedSamples: const [
      [7, 8, 9],
    ],
    decryptedMedia: Uint8List.fromList([7, 8, 9]),
  );
}

void main() {
  test('emits upstream-compatible raw EC3 output', () {
    final packaged = const MediaPackager().package(_song(AudioCodec.ec3));

    expect(packaged.extension, '.ec3');
    expect(packaged.mimeType, 'audio/eac3');
    expect(packaged.bytes, [1, 2, 3]);
  });

  test('emits clear M4A output for ALAC', () {
    final packaged = const MediaPackager().package(_m4aSong());

    expect(packaged.extension, '.m4a');
    expect(packaged.mimeType, 'audio/mp4');
    expect(String.fromCharCodes(packaged.bytes.sublist(8, 12)), 'M4A ');
    expect(packaged.bytes.sublist(packaged.bytes.length - 3), [7, 8, 9]);
  });
}

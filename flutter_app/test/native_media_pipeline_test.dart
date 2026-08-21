import 'dart:typed_data';

import 'package:applemusicdecrypt_android/core/apple_music_api.dart';
import 'package:applemusicdecrypt_android/core/apple_music_url.dart';
import 'package:applemusicdecrypt_android/core/decrypt_session.dart';
import 'package:applemusicdecrypt_android/core/isobmff.dart';
import 'package:applemusicdecrypt_android/core/m3u8_resolver.dart';
import 'package:applemusicdecrypt_android/core/native_media_pipeline.dart';
import 'package:applemusicdecrypt_android/core/rip_preparation.dart';
import 'package:flutter_test/flutter_test.dart';

final class _DownloadOnlyAppleMusic implements AppleMusicDataSource {
  @override
  Future<List<int>> downloadBytes(String url) async => [9, 8, 7];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeExtractor implements SampleExtractor {
  @override
  FragmentedSong extract(Uint8List raw, AudioCodec codec) => FragmentedSong(
        codec: codec,
        raw: raw,
        samples: const [
          EncryptedSample(data: [1, 2], duration: 10, descriptionIndex: 1),
          EncryptedSample(data: [3], duration: 20, descriptionIndex: 0),
        ],
      );
}

final class _FakeDecryptor implements SampleDecryptor {
  List<String>? receivedKeys;

  @override
  Future<List<List<int>>> decryptAll({
    required String adamId,
    required List<String> keys,
    required List<EncryptedSample> samples,
  }) async {
    receivedKeys = keys;
    return [
      [20, 21],
      [30],
    ];
  }
}

void main() {
  test('downloads, extracts and decrypts samples in order',
      () async {
    final decryptor = _FakeDecryptor();
    final pipeline = NativeMediaPipeline(
      appleMusic: _DownloadOnlyAppleMusic(),
      extractor: _FakeExtractor(),
      decryptor: decryptor,
    );
    final stages = <NativeMediaStage>[];
    final prepared = PreparedSong(
      url: AppleMusicUrl.tryParse(
        'https://music.apple.com/us/song/test/123',
      )!,
      song: const {},
      album: const {},
      media: const M3u8Info(
        uri: 'https://example.test/song.mp4',
        keys: ['key-0', 'key-1'],
        codecId: 'audio-alac-stereo-96000-24',
      ),
      cover: null,
      lyrics: null,
    );

    final song = await pipeline.process(prepared, onProgress: stages.add);

    expect(stages, NativeMediaStage.values);
    expect(song.fragmented.raw, [9, 8, 7]);
    expect(song.decryptedSamples, [
      [20, 21],
      [30],
    ]);
    expect(song.decryptedMedia, isEmpty);
    expect(decryptor.receivedKeys, ['key-0', 'key-1']);
  });
}

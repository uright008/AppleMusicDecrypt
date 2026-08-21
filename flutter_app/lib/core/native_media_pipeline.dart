import 'dart:typed_data';

import 'apple_music_api.dart';
import 'decrypt_session.dart';
import 'isobmff.dart';
import 'm3u8_resolver.dart';
import 'rip_preparation.dart';

enum NativeMediaStage { downloading, extracting, decrypting }

typedef NativeMediaProgress = void Function(NativeMediaStage stage);

final class DecryptedSong {
  const DecryptedSong({
    required this.prepared,
    required this.fragmented,
    required this.decryptedSamples,
    required this.decryptedMedia,
  });

  final PreparedSong prepared;
  final FragmentedSong fragmented;
  final List<List<int>> decryptedSamples;
  final Uint8List decryptedMedia;
}

/// Native pipeline through the last step before ISO-BMFF re-encapsulation.
/// Mirrors upstream `_phase2`: download, extract samples, decrypt, preserve
/// sample order, and concatenate the decrypted media payload.
final class NativeMediaPipeline {
  const NativeMediaPipeline({
    required AppleMusicDataSource appleMusic,
    required SampleExtractor extractor,
    required SampleDecryptor decryptor,
  })  : _appleMusic = appleMusic,
        _extractor = extractor,
        _decryptor = decryptor;

  final AppleMusicDataSource _appleMusic;
  final SampleExtractor _extractor;
  final SampleDecryptor _decryptor;

  Future<DecryptedSong> process(
    PreparedSong prepared, {
    NativeMediaProgress? onProgress,
  }) async {
    onProgress?.call(NativeMediaStage.downloading);
    final raw = Uint8List.fromList(
      await _appleMusic.downloadBytes(prepared.media.uri),
    );
    onProgress?.call(NativeMediaStage.extracting);
    final fragmented = _extractor.extract(raw, prepared.media.codec);
    onProgress?.call(NativeMediaStage.decrypting);
    final decrypted = await _decryptor.decryptAll(
      adamId: prepared.url.id,
      keys: prepared.media.keys,
      samples: fragmented.samples,
    );
    var decryptedMedia = Uint8List(0);
    if (fragmented.codec == AudioCodec.ec3 ||
        fragmented.codec == AudioCodec.ac3) {
      final builder = BytesBuilder(copy: false);
      for (final sample in decrypted) {
        builder.add(sample);
      }
      decryptedMedia = builder.takeBytes();
    }
    return DecryptedSong(
      prepared: prepared,
      fragmented: fragmented,
      decryptedSamples: List.unmodifiable(decrypted),
      decryptedMedia: decryptedMedia,
    );
  }
}

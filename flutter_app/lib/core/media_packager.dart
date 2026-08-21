import 'dart:typed_data';

import 'm3u8_resolver.dart';
import 'native_media_pipeline.dart';

final class PackagedMedia {
  const PackagedMedia({
    required this.bytes,
    required this.extension,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String extension;
  final String mimeType;
}

final class PackagingNotImplementedException implements Exception {
  const PackagingNotImplementedException(this.codec);

  final AudioCodec codec;

  @override
  String toString() => 'M4A packaging for ${codec.value} is not implemented';
}

/// Output behavior matching the raw Atmos branch of upstream `encapsulate`.
/// ALAC/AAC deliberately fail until the ISO-BMFF muxer is complete.
final class MediaPackager {
  const MediaPackager();

  PackagedMedia package(
    DecryptedSong song, {
    bool convertAtmosToM4a = false,
  }) {
    final codec = song.fragmented.codec;
    if (!convertAtmosToM4a && codec == AudioCodec.ec3) {
      return PackagedMedia(
        bytes: song.decryptedMedia,
        extension: '.ec3',
        mimeType: 'audio/eac3',
      );
    }
    if (!convertAtmosToM4a && codec == AudioCodec.ac3) {
      return PackagedMedia(
        bytes: song.decryptedMedia,
        extension: '.ac3',
        mimeType: 'audio/ac3',
      );
    }
    throw PackagingNotImplementedException(codec);
  }
}

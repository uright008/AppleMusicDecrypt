import 'dart:typed_data';

import 'clear_mp4_muxer.dart';
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

/// Output behavior matching upstream `encapsulate`: raw Atmos is preserved
/// when conversion is disabled; other codecs are emitted as clear M4A.
final class MediaPackager {
  const MediaPackager({
    ClearMp4Muxer muxer = const ClearMp4Muxer(),
  }) : _muxer = muxer;

  final ClearMp4Muxer _muxer;

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
    return PackagedMedia(
      bytes: _muxer.mux(
        song.fragmented,
        song.decryptedSamples,
        copySource: false,
      ),
      extension: '.m4a',
      mimeType: 'audio/mp4',
    );
  }
}

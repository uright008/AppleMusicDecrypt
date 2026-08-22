import 'dart:convert';
import 'dart:typed_data';

import 'android_media_store.dart';
import 'apple_music_metadata.dart';
import 'media_packager.dart';
import 'mp4_metadata_writer.dart';
import 'native_media_pipeline.dart';

final class SavedMedia {
  const SavedMedia({
    required this.uri,
    required this.displayName,
    required this.media,
  });

  final String uri;
  final String displayName;
  final PackagedMedia media;
}

/// Packages decrypted samples, embeds M4A metadata, and publishes the result
/// under Android's public Download directory.
final class NativeOutputService {
  const NativeOutputService({
    required AudioOutputStore outputStore,
    MediaPackager packager = const MediaPackager(),
    Mp4MetadataWriter metadataWriter = const Mp4MetadataWriter(),
  })  : _outputStore = outputStore,
        _packager = packager,
        _metadataWriter = metadataWriter;

  final AudioOutputStore _outputStore;
  final MediaPackager _packager;
  final Mp4MetadataWriter _metadataWriter;

  Future<SavedMedia> save(
    DecryptedSong song, {
    String? fileName,
    String? relativePath,
    bool convertAtmosToM4a = false,
  }) async {
    final metadata = AppleMusicMetadata.fromPrepared(song.prepared);
    var media = _packager.package(
      song,
      convertAtmosToM4a: convertAtmosToM4a,
    );
    if (media.extension == '.m4a') {
      media = PackagedMedia(
        bytes: _metadataWriter.write(media.bytes, metadata),
        extension: media.extension,
        mimeType: media.mimeType,
      );
    }
    final baseName = _safeBaseName(fileName ?? metadata.fileBaseName);
    final displayName = '$baseName${media.extension}';
    final uri = await _outputStore.saveAudio(
      bytes: media.bytes,
      displayName: displayName,
      mimeType: media.mimeType,
      relativePath: relativePath ?? metadata.relativePath,
    );
    final outputPath = relativePath ?? metadata.relativePath;
    final cover = metadata.cover;
    if (cover != null &&
        cover.isNotEmpty &&
        metadata.outputContext == null) {
      await _outputStore.saveAudio(
        bytes: Uint8List.fromList(cover),
        displayName: metadata.coverIsPng ? 'cover.png' : 'cover.jpg',
        mimeType: metadata.coverIsPng ? 'image/png' : 'image/jpeg',
        relativePath: outputPath,
      );
    }
    final lyrics = metadata.lyrics;
    if (lyrics != null && lyrics.isNotEmpty) {
      await _outputStore.saveAudio(
        bytes: Uint8List.fromList(utf8.encode(lyrics)),
        displayName: '$baseName.lrc',
        mimeType: 'text/plain',
        relativePath: outputPath,
      );
    }
    return SavedMedia(uri: uri, displayName: displayName, media: media);
  }

  static String _safeBaseName(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    return sanitized.isEmpty ? 'Unknown Song' : sanitized;
  }
}

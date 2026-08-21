import 'android_media_store.dart';
import 'media_packager.dart';
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

/// Packages decrypted samples and publishes the result to Android's music
/// collection. This currently supports the raw EC3/AC3 branch that upstream
/// uses when Atmos-to-M4A conversion is disabled.
final class NativeOutputService {
  const NativeOutputService({
    required AudioOutputStore outputStore,
    MediaPackager packager = const MediaPackager(),
  })  : _outputStore = outputStore,
        _packager = packager;

  final AudioOutputStore _outputStore;
  final MediaPackager _packager;

  Future<SavedMedia> save(
    DecryptedSong song, {
    String? fileName,
    String relativePath = 'AppleMusicDecrypt',
    bool convertAtmosToM4a = false,
  }) async {
    final media = _packager.package(
      song,
      convertAtmosToM4a: convertAtmosToM4a,
    );
    final baseName = _safeBaseName(fileName ?? song.prepared.title);
    final displayName = '$baseName${media.extension}';
    final uri = await _outputStore.saveAudio(
      bytes: media.bytes,
      displayName: displayName,
      mimeType: media.mimeType,
      relativePath: relativePath,
    );
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

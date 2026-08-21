import 'dart:typed_data';

import 'package:flutter/services.dart';

abstract interface class AudioOutputStore {
  Future<String> saveAudio({
    required Uint8List bytes,
    required String displayName,
    required String mimeType,
    String relativePath = 'AppleMusicDecrypt',
  });
}

final class AndroidMediaStore implements AudioOutputStore {
  const AndroidMediaStore({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName =
      'dev.worldobservationlog.applemusicdecrypt/media_store';

  final MethodChannel _channel;

  @override
  Future<String> saveAudio({
    required Uint8List bytes,
    required String displayName,
    required String mimeType,
    String relativePath = 'AppleMusicDecrypt',
  }) async {
    final name = displayName.trim();
    final path = relativePath.trim().replaceAll('\\', '/');
    if (bytes.isEmpty) throw ArgumentError.value(bytes, 'bytes', 'is empty');
    if (name.isEmpty || name.contains('/') || name.contains('\\')) {
      throw ArgumentError.value(displayName, 'displayName');
    }
    if (mimeType.trim().isEmpty) throw ArgumentError.value(mimeType, 'mimeType');
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.split('/').any((segment) => segment == '..')) {
      throw ArgumentError.value(relativePath, 'relativePath');
    }
    final uri = await _channel.invokeMethod<String>('saveAudio', {
      'bytes': bytes,
      'displayName': name,
      'mimeType': mimeType,
      'relativePath': path,
    });
    if (uri == null || uri.isEmpty) {
      throw PlatformException(
        code: 'EMPTY_MEDIA_URI',
        message: 'Android MediaStore returned no URI',
      );
    }
    return uri;
  }
}

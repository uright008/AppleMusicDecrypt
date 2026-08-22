import 'package:applemusicdecrypt_android/core/android_media_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/media-store');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('writes packaged bytes through the MediaStore channel', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return 'content://media/external/downloads/1';
    });
    const store = AndroidMediaStore(channel: channel);

    final uri = await store.saveAudio(
      bytes: Uint8List.fromList([1, 2, 3]),
      displayName: 'Song.ec3',
      mimeType: 'audio/eac3',
    );

    expect(uri, 'content://media/external/downloads/1');
    expect(received?.method, 'saveAudio');
    final arguments = received?.arguments as Map<Object?, Object?>;
    expect(arguments['displayName'], 'Song.ec3');
    expect(arguments['relativePath'], 'AppleMusicDecrypt');
  });

  test('rejects path traversal before invoking Android', () async {
    const store = AndroidMediaStore(channel: channel);

    await expectLater(
      store.saveAudio(
        bytes: Uint8List.fromList([1]),
        displayName: 'Song.ec3',
        mimeType: 'audio/eac3',
        relativePath: '../elsewhere',
      ),
      throwsArgumentError,
    );
  });
}

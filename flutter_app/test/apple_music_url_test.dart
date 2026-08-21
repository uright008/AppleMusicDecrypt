import 'package:applemusicdecrypt_android/core/apple_music_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses song and album URLs', () {
    final song = AppleMusicUrl.tryParse(
      'https://music.apple.com/us/song/example/123456789',
    );
    final album = AppleMusicUrl.tryParse(
      'https://music.apple.com/gb/album/example/987654321',
    );

    expect(song?.type, AppleMusicUrlType.song);
    expect(song?.id, '123456789');
    expect(album?.type, AppleMusicUrlType.album);
    expect(album?.storefront, 'gb');
  });

  test('album track query is treated as a song like upstream', () {
    final url = AppleMusicUrl.tryParse(
      'https://music.apple.com/cn/album/example/987654321?i=123456789',
    );

    expect(url?.type, AppleMusicUrlType.song);
    expect(url?.id, '123456789');
  });

  test('parses playlist and rejects unsupported hosts', () {
    final playlist = AppleMusicUrl.tryParse(
      'https://music.apple.com/us/playlist/example/pl.u-abc123',
    );

    expect(playlist?.type, AppleMusicUrlType.playlist);
    expect(AppleMusicUrl.tryParse('https://example.com/us/song/x/123'), isNull);
  });
}

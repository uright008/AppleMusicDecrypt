import 'package:applemusicdecrypt_android/core/m3u8_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

const _master = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-alac-stereo-96000-24",SAMPLE-RATE=96000,BIT-DEPTH=24
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-alac-stereo-192000-24",SAMPLE-RATE=192000,BIT-DEPTH=24
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-stereo-256",NAME="AAC"
#EXT-X-STREAM-INF:BANDWIDTH=1000000,AVERAGE-BANDWIDTH=900000,AUDIO="audio-alac-stereo-96000-24"
alac-96/playlist.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2000000,AVERAGE-BANDWIDTH=1900000,AUDIO="audio-alac-stereo-192000-24"
alac-192/playlist.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=256000,AVERAGE-BANDWIDTH=250000,AUDIO="audio-stereo-256"
aac/playlist.m3u8
''';

const _media = '''
#EXTM3U
#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://itunes.apple.com/key/c23"
#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://itunes.apple.com/fallback/c6"
#EXT-X-MAP:URI="audio.mp4"
''';

void main() {
  test('selects highest-bandwidth ALAC within configured limits', () async {
    final requested = <String>[];
    final info = await const M3u8Resolver(maxSampleRate: 96000).resolve(
      masterUrl: 'https://example.test/master.m3u8',
      codec: AudioCodec.alac,
      load: (url) async {
        requested.add(url);
        return url.endsWith('master.m3u8') ? _master : _media;
      },
    );

    expect(requested[1], 'https://example.test/alac-96/playlist.m3u8');
    expect(info.uri, 'https://example.test/alac-96/audio.mp4');
    expect(info.codecId, 'audio-alac-stereo-96000-24');
    expect(info.sampleRate, 96000);
    expect(info.bitDepth, 24);
    expect(info.keys, [
      M3u8Resolver.prefetchKey,
      'skd://itunes.apple.com/key/c23',
      'skd://itunes.apple.com/fallback/c6',
    ]);
  });

  test('uses codec priority when alternatives are enabled', () async {
    final info = await const M3u8Resolver().resolve(
      masterUrl: 'https://example.test/master.m3u8',
      codec: AudioCodec.ec3,
      codecAlternative: true,
      codecPriority: const [AudioCodec.aac, AudioCodec.alac],
      load: (url) async => url.endsWith('master.m3u8') ? _master : _media,
    );

    expect(info.codecId, 'audio-stereo-256');
    expect(info.sampleRate, isNull);
  });

  test('fails when requested codec does not exist', () async {
    expect(
      () => const M3u8Resolver().resolve(
        masterUrl: 'https://example.test/master.m3u8',
        codec: AudioCodec.ec3,
        load: (_) async => _master,
      ),
      throwsA(isA<CodecNotFoundException>()),
    );
  });
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:applemusicdecrypt_android/core/apple_music_metadata.dart';
import 'package:applemusicdecrypt_android/core/apple_music_url.dart';
import 'package:applemusicdecrypt_android/core/isobmff.dart';
import 'package:applemusicdecrypt_android/core/m3u8_resolver.dart';
import 'package:applemusicdecrypt_android/core/mp4_metadata_writer.dart';
import 'package:applemusicdecrypt_android/core/rip_preparation.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _box(String type, List<int> payload) {
  final bytes = Uint8List(8 + payload.length);
  ByteData.sublistView(bytes).setUint32(0, bytes.length);
  bytes.setRange(4, 8, type.codeUnits);
  bytes.setRange(8, bytes.length, payload);
  return bytes;
}

List<int> _u32(int value) {
  final bytes = Uint8List(4);
  ByteData.sublistView(bytes).setUint32(0, value);
  return bytes;
}

List<int> _u64(int value) {
  final bytes = Uint8List(8);
  ByteData.sublistView(bytes).setUint64(0, value);
  return bytes;
}

AppleMusicMetadata _metadata() => AppleMusicMetadata.fromPrepared(
      PreparedSong(
        url: AppleMusicUrl.tryParse(
          'https://music.apple.com/us/song/test/123',
        )!,
        song: {
          'attributes': {
            'name': '测试歌曲',
            'artistName': 'Artist',
            'albumName': 'Album',
            'trackNumber': 1,
            'discNumber': 1,
            'genreNames': ['Pop'],
            'isrc': 'US-TEST',
          },
          'relationships': {
            'albums': {
              'data': [
                {'id': '456'},
              ],
            },
          },
        },
        album: {
          'data': [
            {
              'id': '456',
              'attributes': {'name': 'Album', 'artistName': 'Artist'},
            },
          ],
        },
        media: const M3u8Info(
          uri: 'https://example.test/song.mp4',
          keys: [],
          codecId: 'audio-alac-stereo-48000-24',
        ),
        cover: const [0xff, 0xd8, 0xff, 0xd9],
        lyrics: null,
      ),
    );

void main() {
  test('adds standard iTunes metadata under moov/udta/meta/ilst', () {
    final source = Uint8List.fromList([
      ..._box('ftyp', [...'M4A '.codeUnits, 0, 0, 0, 0]),
      ..._box('moov', const []),
      ..._box('mdat', const [1, 2, 3]),
    ]);

    final output = const Mp4MetadataWriter().write(source, _metadata());

    final top = FragmentedMp4Extractor.parseBoxes(output);
    final moov = top.firstWhere((box) => box.type == 'moov');
    final udta = FragmentedMp4Extractor.parseBoxes(
      output,
      start: moov.payloadOffset,
      end: moov.end,
    ).firstWhere((box) => box.type == 'udta');
    final meta = FragmentedMp4Extractor.parseBoxes(
      output,
      start: udta.payloadOffset,
      end: udta.end,
    ).firstWhere((box) => box.type == 'meta');
    final ilst = FragmentedMp4Extractor.parseBoxes(
      output,
      start: meta.payloadOffset + 4,
      end: meta.end,
    ).firstWhere((box) => box.type == 'ilst');
    final tags = FragmentedMp4Extractor.parseBoxes(
      output,
      start: ilst.payloadOffset,
      end: ilst.end,
    ).map((box) => box.type);

    expect(tags, containsAll(['©nam', '©ART', 'aART', '©alb']));
    expect(tags, containsAll(['trkn', 'disk', 'covr', 'cnID', 'plID']));
    expect(utf8.decode(output, allowMalformed: true), contains('测试歌曲'));
    expect(top.last.type, 'mdat');
    expect(output.sublist(top.last.payloadOffset, top.last.end), [1, 2, 3]);
  });

  test('keeps absolute chunk and fragment offsets valid', () {
    final ftyp = _box('ftyp', [...'M4A '.codeUnits, 0, 0, 0, 0]);
    Uint8List moovWithOffset(int offset) => _box('moov', [
          ..._box('trak', [
            ..._box('mdia', [
              ..._box('minf', [
                ..._box('stbl', [
                  ..._box('stco', [0, 0, 0, 0, ..._u32(1), ..._u32(offset)]),
                ]),
              ]),
            ]),
          ]),
        ]);
    Uint8List moofWithOffset(int offset) => _box('moof', [
          ..._box('traf', [
            ..._box('tfhd', [
              0,
              0,
              0,
              1,
              ..._u32(1),
              ..._u64(offset),
            ]),
          ]),
        ]);
    final emptyMoov = moovWithOffset(0);
    final emptyMoof = moofWithOffset(0);
    final oldMdatPayload = ftyp.length + emptyMoov.length + emptyMoof.length + 8;
    final source = Uint8List.fromList([
      ...ftyp,
      ...moovWithOffset(oldMdatPayload),
      ...moofWithOffset(oldMdatPayload),
      ..._box('mdat', const [1, 2, 3]),
    ]);

    final output = const Mp4MetadataWriter().write(source, _metadata());
    final top = FragmentedMp4Extractor.parseBoxes(output);
    final moov = top.firstWhere((box) => box.type == 'moov');
    final mdat = top.firstWhere((box) => box.type == 'mdat');
    IsoBox child(IsoBox parent, String type) =>
        FragmentedMp4Extractor.parseBoxes(
          output,
          start: parent.payloadOffset,
          end: parent.end,
        ).firstWhere((box) => box.type == type);
    final stco = child(
      child(child(child(child(moov, 'trak'), 'mdia'), 'minf'), 'stbl'),
      'stco',
    );
    final moof = top.firstWhere((box) => box.type == 'moof');
    final tfhd = child(child(moof, 'traf'), 'tfhd');
    final data = ByteData.sublistView(output);

    expect(data.getUint32(stco.payloadOffset + 8), mdat.payloadOffset);
    expect(data.getUint64(tfhd.payloadOffset + 8), mdat.payloadOffset);
  });
}

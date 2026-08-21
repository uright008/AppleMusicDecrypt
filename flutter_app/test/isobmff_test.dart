import 'dart:typed_data';

import 'package:applemusicdecrypt_android/core/isobmff.dart';
import 'package:applemusicdecrypt_android/core/m3u8_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _box(String type, List<int> payload) {
  final result = Uint8List(8 + payload.length);
  final data = ByteData.sublistView(result)..setUint32(0, result.length);
  result.setRange(4, 8, type.codeUnits);
  result.setRange(8, result.length, payload);
  return result;
}

List<int> _uint32(int value) {
  final bytes = Uint8List(4);
  ByteData.sublistView(bytes).setUint32(0, value);
  return bytes;
}

Uint8List _fragment() {
  const tfhdFlags = 0x020000 | 0x000002 | 0x000008;
  final tfhd = _box('tfhd', [
    0,
    (tfhdFlags >> 16) & 0xff,
    (tfhdFlags >> 8) & 0xff,
    tfhdFlags & 0xff,
    ..._uint32(1),
    ..._uint32(2),
    ..._uint32(1024),
  ]);

  Uint8List makeMoof(int dataOffset) {
    const trunFlags = 0x000001 | 0x000200;
    final trun = _box('trun', [
      0,
      (trunFlags >> 16) & 0xff,
      (trunFlags >> 8) & 0xff,
      trunFlags & 0xff,
      ..._uint32(2),
      ..._uint32(dataOffset),
      ..._uint32(2),
      ..._uint32(3),
    ]);
    return _box('moof', _box('traf', [...tfhd, ...trun]));
  }

  var moof = makeMoof(0);
  moof = makeMoof(moof.length + 8);
  final mdat = _box('mdat', [1, 2, 3, 4, 5]);
  return Uint8List.fromList([...moof, ...mdat]);
}

void main() {
  test('parses top-level ISO-BMFF boxes', () {
    final boxes = FragmentedMp4Extractor.parseBoxes(_fragment());

    expect(boxes.map((box) => box.type), ['moof', 'mdat']);
    expect(boxes.last.payloadOffset, boxes.first.end + 8);
  });

  test('extracts fragmented samples, duration and description index', () {
    final raw = _fragment();
    final song = const FragmentedMp4Extractor().extract(raw, AudioCodec.alac);

    expect(song.samples, hasLength(2));
    expect(song.samples[0].data, [1, 2]);
    expect(song.samples[1].data, [3, 4, 5]);
    expect(song.samples.map((sample) => sample.duration), [1024, 1024]);
    expect(song.samples.map((sample) => sample.descriptionIndex), [1, 1]);
  });

  test('rejects truncated boxes', () {
    expect(
      () => FragmentedMp4Extractor.parseBoxes(Uint8List.fromList([0, 0, 0])),
      throwsFormatException,
    );
  });
}

import 'dart:typed_data';

import 'package:applemusicdecrypt_android/core/clear_mp4_muxer.dart';
import 'package:applemusicdecrypt_android/core/isobmff.dart';
import 'package:applemusicdecrypt_android/core/m3u8_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _box(String type, List<int> payload) {
  final result = Uint8List(8 + payload.length);
  ByteData.sublistView(result).setUint32(0, result.length);
  result.setRange(4, 8, type.codeUnits);
  result.setRange(8, result.length, payload);
  return result;
}

List<int> _uint32(int value) {
  final bytes = Uint8List(4);
  ByteData.sublistView(bytes).setUint32(0, value);
  return bytes;
}

Uint8List _protectedFragment() {
  final ftyp = _box('ftyp', [
    ...'iso6'.codeUnits,
    0,
    0,
    0,
    1,
    ...'iso6'.codeUnits,
  ]);
  final frma = _box('frma', 'alac'.codeUnits);
  final sinf = _box('sinf', frma);
  final alac = _box('alac', [0, 0, 0, 0]);
  final enca = _box('enca', [
    ...List<int>.filled(28, 0),
    ...sinf,
    ...alac,
  ]);
  final stsd = _box('stsd', [
    0,
    0,
    0,
    0,
    ..._uint32(1),
    ...enca,
  ]);
  final moov = _box(
    'moov',
    _box('trak', _box('mdia', _box('minf', _box('stbl', stsd)))),
  );

  const tfhdFlags = 0x020000 | 0x000002 | 0x000008;
  final tfhd = _box('tfhd', [
    0,
    (tfhdFlags >> 16) & 0xff,
    (tfhdFlags >> 8) & 0xff,
    tfhdFlags & 0xff,
    ..._uint32(1),
    ..._uint32(1),
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
    final traf = _box('traf', [
      ...tfhd,
      ...trun,
      ..._box('senc', [0, 0, 0, 0]),
      ..._box('saiz', [0, 0, 0, 0]),
      ..._box('saio', [0, 0, 0, 0]),
    ]);
    return _box('moof', traf);
  }

  var moof = makeMoof(0);
  moof = makeMoof(moof.length + 8);
  final mdat = _box('mdat', [1, 2, 3, 4, 5]);
  return Uint8List.fromList([...ftyp, ...moov, ...moof, ...mdat]);
}

void main() {
  test('restores clear sample entry and replaces samples in place', () {
    final protected = _protectedFragment();
    final source = const FragmentedMp4Extractor().extract(
      protected,
      AudioCodec.alac,
    );

    final clear = const ClearMp4Muxer().mux(source, const [
      [9, 8],
      [7, 6, 5],
    ]);

    final reparsed = const FragmentedMp4Extractor().extract(
      clear,
      AudioCodec.alac,
    );
    expect(reparsed.samples[0].data, [9, 8]);
    expect(reparsed.samples[1].data, [7, 6, 5]);
    expect(source.samples[0].data, [1, 2]);
    expect(
      String.fromCharCodes(clear.sublist(8, 12)),
      'M4A ',
    );
    final boxText = String.fromCharCodes(clear);
    expect(boxText, contains('alac'));
    expect(boxText, isNot(contains('enca')));
    expect(boxText, isNot(contains('sinf')));
    expect(boxText, isNot(contains('senc')));
    expect(boxText, isNot(contains('saiz')));
    expect(boxText, isNot(contains('saio')));
  });

  test('rejects decrypted samples whose length changed', () {
    final source = const FragmentedMp4Extractor().extract(
      _protectedFragment(),
      AudioCodec.alac,
    );

    expect(
      () => const ClearMp4Muxer().mux(source, const [
        [1],
        [2, 3, 4],
      ]),
      throwsA(isA<Mp4MuxException>()),
    );
  });
}

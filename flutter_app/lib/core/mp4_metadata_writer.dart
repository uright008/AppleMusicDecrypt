import 'dart:convert';
import 'dart:typed_data';

import 'apple_music_metadata.dart';
import 'isobmff.dart';

final class Mp4MetadataException implements Exception {
  const Mp4MetadataException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Writes the iTunes-style metadata atoms used by upstream Mutagen.
final class Mp4MetadataWriter {
  const Mp4MetadataWriter();

  Uint8List write(Uint8List source, AppleMusicMetadata metadata) {
    final topLevel = FragmentedMp4Extractor.parseBoxes(source);
    final moov = _firstWhereOrNull(topLevel, (box) => box.type == 'moov');
    if (moov == null) {
      throw const Mp4MetadataException('M4A has no moov box');
    }
    final items = <Uint8List>[];
    _addText(items, '©nam', metadata.title);
    _addText(items, '©ART', metadata.artist);
    _addText(items, 'aART', metadata.albumArtist);
    _addText(items, '©alb', metadata.album);
    _addText(items, '©day', metadata.albumCreated);
    _addText(items, '©wrt', metadata.composer);
    _addText(items, 'purd', metadata.created);
    _addText(items, '©lyr', metadata.lyrics);
    _addText(items, 'cprt', metadata.copyright);
    _addText(items, '©pub', metadata.recordCompany);
    if (metadata.genres.isNotEmpty) {
      items.add(_item(
        '©gen',
        metadata.genres.map((genre) => _data(1, utf8.encode(genre))).toList(),
      ));
    }
    items.add(_item('trkn', [
      _data(0, _pair(metadata.trackNumber, metadata.trackTotal, trailing: true)),
    ]));
    items.add(_item('disk', [
      _data(0, _pair(metadata.discNumber, metadata.discTotal)),
    ]));
    items.add(_item('rtng', [
      _data(21, [metadata.rating & 0xff]),
    ]));
    _addInteger(items, 'cnID', metadata.songId);
    _addInteger(items, 'plID', metadata.albumId);
    _addInteger(items, 'atID', metadata.artistId);
    _addFreeform(items, 'BARCODE', metadata.upc);
    _addFreeform(items, 'ISRC', metadata.isrc);
    final cover = metadata.cover;
    if (cover != null && cover.isNotEmpty) {
      items.add(_item('covr', [
        _data(metadata.coverIsPng ? 14 : 13, cover),
      ]));
    }

    final ilst = _box('ilst', _concat(items));
    final hdlr = _box('hdlr', [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      ...'mdir'.codeUnits,
      ...'appl'.codeUnits,
      ...List<int>.filled(8, 0),
      0,
    ]);
    final meta = _box('meta', [
      0,
      0,
      0,
      0,
      ...hdlr,
      ...ilst,
    ]);
    final rebuiltMoov = _rebuildMoov(source, moov, meta);
    final delta = rebuiltMoov.length - moov.size;
    _patchChunkOffsets(rebuiltMoov, delta, moov.end);
    final output = BytesBuilder(copy: false)
      ..add(Uint8List.sublistView(source, 0, moov.offset))
      ..add(rebuiltMoov)
      ..add(Uint8List.sublistView(source, moov.end));
    final bytes = output.takeBytes();
    _patchFragmentOffsets(bytes, delta, moov);
    _patchSegmentIndexes(bytes, delta, moov);
    return bytes;
  }

  static Uint8List _rebuildMoov(
    Uint8List source,
    IsoBox moov,
    Uint8List metadata,
  ) {
    final parts = <List<int>>[];
    var wroteMetadata = false;
    for (final child in FragmentedMp4Extractor.parseBoxes(
      source,
      start: moov.payloadOffset,
      end: moov.end,
    )) {
      if (child.type != 'udta') {
        parts.add(Uint8List.sublistView(source, child.offset, child.end));
        continue;
      }
      final userData = <List<int>>[];
      for (final item in FragmentedMp4Extractor.parseBoxes(
        source,
        start: child.payloadOffset,
        end: child.end,
      )) {
        if (item.type != 'meta') {
          userData.add(Uint8List.sublistView(source, item.offset, item.end));
        }
      }
      if (!wroteMetadata) {
        userData.add(metadata);
        wroteMetadata = true;
      }
      parts.add(_box('udta', _concat(userData)));
    }
    if (!wroteMetadata) parts.add(_box('udta', metadata));
    return _box('moov', _concat(parts));
  }

  static void _patchChunkOffsets(
    Uint8List moov,
    int delta,
    int oldMoovEnd,
  ) {
    if (delta == 0) return;
    final root = FragmentedMp4Extractor.parseBoxes(moov).single;
    _walkContainers(moov, root, (box) {
      if (box.type != 'stco' && box.type != 'co64') return;
      final data = ByteData.sublistView(moov);
      if (box.payloadOffset + 8 > box.end) {
        throw const Mp4MetadataException('Truncated chunk offset box');
      }
      final count = data.getUint32(box.payloadOffset + 4);
      final width = box.type == 'co64' ? 8 : 4;
      var cursor = box.payloadOffset + 8;
      for (var index = 0; index < count; index++) {
        if (cursor + width > box.end) {
          throw const Mp4MetadataException('Truncated chunk offset table');
        }
        final value = width == 8
            ? data.getUint64(cursor)
            : data.getUint32(cursor);
        if (value >= oldMoovEnd) {
          final shifted = value + delta;
          if (shifted < 0 || (width == 4 && shifted > 0xffffffff)) {
            throw const Mp4MetadataException('Chunk offset exceeds its field');
          }
          if (width == 8) {
            data.setUint64(cursor, shifted);
          } else {
            data.setUint32(cursor, shifted);
          }
        }
        cursor += width;
      }
    });
  }

  static void _patchFragmentOffsets(
    Uint8List output,
    int delta,
    IsoBox oldMoov,
  ) {
    if (delta == 0) return;
    final data = ByteData.sublistView(output);
    for (final moof in FragmentedMp4Extractor.parseBoxes(output)
        .where((box) => box.type == 'moof')) {
      for (final traf in FragmentedMp4Extractor.parseBoxes(
        output,
        start: moof.payloadOffset,
        end: moof.end,
      ).where((box) => box.type == 'traf')) {
        for (final tfhd in FragmentedMp4Extractor.parseBoxes(
          output,
          start: traf.payloadOffset,
          end: traf.end,
        ).where((box) => box.type == 'tfhd')) {
          if (tfhd.payloadOffset + 16 > tfhd.end) continue;
          final flags = (data.getUint8(tfhd.payloadOffset + 1) << 16) |
              (data.getUint8(tfhd.payloadOffset + 2) << 8) |
              data.getUint8(tfhd.payloadOffset + 3);
          if ((flags & 0x000001) == 0) continue;
          final offset = tfhd.payloadOffset + 8;
          final value = data.getUint64(offset);
          if (value >= oldMoov.end) data.setUint64(offset, value + delta);
        }
      }
    }
  }

  static void _patchSegmentIndexes(
    Uint8List output,
    int delta,
    IsoBox oldMoov,
  ) {
    if (delta == 0) return;
    final data = ByteData.sublistView(output);
    for (final sidx in FragmentedMp4Extractor.parseBoxes(output)
        .where((box) => box.type == 'sidx')) {
      final originalOffset =
          sidx.offset >= oldMoov.end + delta ? sidx.offset - delta : sidx.offset;
      if (originalOffset >= oldMoov.end || sidx.payloadOffset + 20 > sidx.end) {
        continue;
      }
      final version = data.getUint8(sidx.payloadOffset);
      final firstOffsetPosition = sidx.payloadOffset + (version == 0 ? 16 : 20);
      final width = version == 0 ? 4 : 8;
      if (firstOffsetPosition + width > sidx.end) continue;
      final firstOffset = width == 4
          ? data.getUint32(firstOffsetPosition)
          : data.getUint64(firstOffsetPosition);
      final originalEnd = originalOffset + sidx.size;
      if (originalEnd + firstOffset < oldMoov.end) continue;
      final shifted = firstOffset + delta;
      if (width == 4) {
        if (shifted > 0xffffffff) {
          throw const Mp4MetadataException('Segment index offset overflow');
        }
        data.setUint32(firstOffsetPosition, shifted);
      } else {
        data.setUint64(firstOffsetPosition, shifted);
      }
    }
  }

  static const _offsetContainers = {
    'moov',
    'trak',
    'mdia',
    'minf',
    'stbl',
  };

  static void _walkContainers(
    Uint8List bytes,
    IsoBox parent,
    void Function(IsoBox box) visit,
  ) {
    for (final child in FragmentedMp4Extractor.parseBoxes(
      bytes,
      start: parent.payloadOffset,
      end: parent.end,
    )) {
      visit(child);
      if (_offsetContainers.contains(child.type)) {
        _walkContainers(bytes, child, visit);
      }
    }
  }

  static void _addText(
    List<Uint8List> items,
    String type,
    String? value,
  ) {
    if (value == null || value.isEmpty) return;
    items.add(_item(type, [_data(1, utf8.encode(value))]));
  }

  static void _addInteger(
    List<Uint8List> items,
    String type,
    String? value,
  ) {
    final number = int.tryParse(value ?? '');
    if (number == null || number < 0) return;
    final bytes = Uint8List(8);
    ByteData.sublistView(bytes).setUint64(0, number);
    items.add(_item(type, [_data(21, bytes)]));
  }

  static void _addFreeform(
    List<Uint8List> items,
    String name,
    String? value,
  ) {
    if (value == null || value.isEmpty) return;
    items.add(_box('----', [
      ..._box('mean', [0, 0, 0, 0, ...utf8.encode('com.apple.iTunes')]),
      ..._box('name', [0, 0, 0, 0, ...utf8.encode(name)]),
      ..._data(1, utf8.encode(value)),
    ]));
  }

  static Uint8List _pair(int current, int total, {bool trailing = false}) {
    final bytes = Uint8List(trailing ? 8 : 6);
    final data = ByteData.sublistView(bytes);
    data.setUint16(2, current);
    data.setUint16(4, total);
    return bytes;
  }

  static Uint8List _item(String type, List<Uint8List> values) =>
      _box(type, _concat(values));

  static Uint8List _data(int type, List<int> value) => _box('data', [
        0,
        0,
        0,
        type,
        0,
        0,
        0,
        0,
        ...value,
      ]);

  static Uint8List _box(String type, List<int> payload) {
    if (type.codeUnits.length != 4) {
      throw Mp4MetadataException('Invalid MP4 box type: $type');
    }
    final size = 8 + payload.length;
    if (size > 0xffffffff) {
      throw const Mp4MetadataException('Metadata box exceeds 32-bit size');
    }
    final bytes = Uint8List(size);
    ByteData.sublistView(bytes).setUint32(0, size);
    bytes.setRange(4, 8, type.codeUnits);
    bytes.setRange(8, size, payload);
    return bytes;
  }

  static Uint8List _concat(Iterable<List<int>> values) {
    final builder = BytesBuilder(copy: false);
    for (final value in values) {
      builder.add(value);
    }
    return builder.takeBytes();
  }
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}

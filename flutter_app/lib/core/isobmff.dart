import 'dart:typed_data';

import 'decrypt_session.dart';
import 'm3u8_resolver.dart';

final class IsoBox {
  const IsoBox({
    required this.type,
    required this.offset,
    required this.size,
    required this.headerSize,
  });

  final String type;
  final int offset;
  final int size;
  final int headerSize;

  int get payloadOffset => offset + headerSize;
  int get end => offset + size;
}

final class FragmentedSong {
  const FragmentedSong({
    required this.codec,
    required this.raw,
    required this.samples,
  });

  final AudioCodec codec;
  final Uint8List raw;
  final List<EncryptedSample> samples;
}

/// ISO-BMFF fragment parser replacing the sample-extraction portion of the
/// GPAC/MP4Box subprocess path in upstream `src.mp4.extract_song`.
final class FragmentedMp4Extractor {
  const FragmentedMp4Extractor();

  FragmentedSong extract(Uint8List raw, AudioCodec codec) {
    final topLevel = parseBoxes(raw);
    final samples = <EncryptedSample>[];
    for (final moof in topLevel.where((box) => box.type == 'moof')) {
      final followingMdat = _firstWhereOrNull(
        topLevel,
        (box) => box.type == 'mdat' && box.offset >= moof.end,
      );
      for (final traf in parseBoxes(raw, start: moof.payloadOffset, end: moof.end)
          .where((box) => box.type == 'traf')) {
        final children = parseBoxes(
          raw,
          start: traf.payloadOffset,
          end: traf.end,
        );
        final tfhdBox = _firstWhereOrNull(
          children,
          (box) => box.type == 'tfhd',
        );
        if (tfhdBox == null) {
          throw const FormatException('Track fragment has no tfhd box');
        }
        final tfhd = _parseTfhd(raw, tfhdBox);
        var implicitOffset = followingMdat?.payloadOffset;
        for (final trunBox in children.where((box) => box.type == 'trun')) {
          final trun = _parseTrun(raw, trunBox, tfhd);
          var sampleOffset = trun.dataOffset == null
              ? implicitOffset
              : (tfhd.baseDataOffset ?? moof.offset) + trun.dataOffset!;
          if (sampleOffset == null) {
            throw const FormatException('Cannot resolve fragment sample offset');
          }
          for (final entry in trun.entries) {
            final sampleEnd = sampleOffset + entry.size;
            if (sampleOffset < 0 || sampleEnd > raw.length) {
              throw FormatException(
                'Fragment sample range $sampleOffset..$sampleEnd is invalid',
              );
            }
            samples.add(EncryptedSample(
              data: Uint8List.fromList(raw.sublist(sampleOffset, sampleEnd)),
              duration: entry.duration,
              descriptionIndex: tfhd.sampleDescriptionIndex,
            ));
            sampleOffset = sampleEnd;
          }
          implicitOffset = sampleOffset;
        }
      }
    }
    if (samples.isEmpty) {
      throw const FormatException('No fragmented MP4 audio samples were found');
    }
    return FragmentedSong(
      codec: codec,
      raw: raw,
      samples: List.unmodifiable(samples),
    );
  }

  static List<IsoBox> parseBoxes(
    Uint8List bytes, {
    int start = 0,
    int? end,
  }) {
    final limit = end ?? bytes.length;
    final data = ByteData.sublistView(bytes);
    final result = <IsoBox>[];
    var cursor = start;
    while (cursor < limit) {
      if (cursor + 8 > limit) {
        throw const FormatException('Truncated ISO-BMFF box header');
      }
      var size = data.getUint32(cursor);
      final type = String.fromCharCodes(bytes.sublist(cursor + 4, cursor + 8));
      var headerSize = 8;
      if (size == 1) {
        if (cursor + 16 > limit) {
          throw const FormatException('Truncated large ISO-BMFF box header');
        }
        size = data.getUint64(cursor + 8);
        headerSize = 16;
      } else if (size == 0) {
        size = limit - cursor;
      }
      if (size < headerSize || cursor + size > limit) {
        throw FormatException('Invalid $type box size $size at $cursor');
      }
      result.add(IsoBox(
        type: type,
        offset: cursor,
        size: size,
        headerSize: headerSize,
      ));
      cursor += size;
    }
    return List.unmodifiable(result);
  }

  static _TrackFragmentHeader _parseTfhd(Uint8List raw, IsoBox box) {
    final reader = _BoxReader(raw, box.payloadOffset, box.end);
    final flags = reader.readFullBoxFlags();
    reader.readUint32(); // track_ID
    int? baseDataOffset;
    var sampleDescriptionIndex = 0;
    int? defaultSampleDuration;
    int? defaultSampleSize;
    if ((flags & 0x000001) != 0) baseDataOffset = reader.readUint64();
    if ((flags & 0x000002) != 0) {
      sampleDescriptionIndex = reader.readUint32() - 1;
    }
    if ((flags & 0x000008) != 0) {
      defaultSampleDuration = reader.readUint32();
    }
    if ((flags & 0x000010) != 0) defaultSampleSize = reader.readUint32();
    if ((flags & 0x000020) != 0) reader.readUint32();
    return _TrackFragmentHeader(
      baseDataOffset: baseDataOffset,
      sampleDescriptionIndex: sampleDescriptionIndex,
      defaultSampleDuration: defaultSampleDuration,
      defaultSampleSize: defaultSampleSize,
    );
  }

  static _TrackRun _parseTrun(
    Uint8List raw,
    IsoBox box,
    _TrackFragmentHeader tfhd,
  ) {
    final reader = _BoxReader(raw, box.payloadOffset, box.end);
    final fullBox = reader.readFullBox();
    final flags = fullBox.flags;
    final sampleCount = reader.readUint32();
    final dataOffset =
        (flags & 0x000001) != 0 ? reader.readInt32() : null;
    if ((flags & 0x000004) != 0) reader.readUint32();
    final entries = <_TrackRunEntry>[];
    for (var index = 0; index < sampleCount; index++) {
      final duration = (flags & 0x000100) != 0
          ? reader.readUint32()
          : tfhd.defaultSampleDuration ?? 0;
      final size = (flags & 0x000200) != 0
          ? reader.readUint32()
          : tfhd.defaultSampleSize;
      if (size == null) {
        throw const FormatException('Fragment sample has no declared size');
      }
      if ((flags & 0x000400) != 0) reader.readUint32();
      if ((flags & 0x000800) != 0) {
        if (fullBox.version == 1) {
          reader.readInt32();
        } else {
          reader.readUint32();
        }
      }
      entries.add(_TrackRunEntry(duration: duration, size: size));
    }
    return _TrackRun(dataOffset: dataOffset, entries: entries);
  }
}

final class _BoxReader {
  _BoxReader(Uint8List bytes, this._offset, this._end)
      : _data = ByteData.sublistView(bytes);

  final ByteData _data;
  int _offset;
  final int _end;

  ({int version, int flags}) readFullBox() {
    _ensure(4);
    final version = _data.getUint8(_offset);
    final flags = (_data.getUint8(_offset + 1) << 16) |
        (_data.getUint8(_offset + 2) << 8) |
        _data.getUint8(_offset + 3);
    _offset += 4;
    return (version: version, flags: flags);
  }

  int readFullBoxFlags() => readFullBox().flags;

  int readUint32() {
    _ensure(4);
    final value = _data.getUint32(_offset);
    _offset += 4;
    return value;
  }

  int readInt32() {
    _ensure(4);
    final value = _data.getInt32(_offset);
    _offset += 4;
    return value;
  }

  int readUint64() {
    _ensure(8);
    final value = _data.getUint64(_offset);
    _offset += 8;
    return value;
  }

  void _ensure(int length) {
    if (_offset + length > _end) {
      throw const FormatException('Truncated ISO-BMFF box payload');
    }
  }
}

final class _TrackFragmentHeader {
  const _TrackFragmentHeader({
    required this.baseDataOffset,
    required this.sampleDescriptionIndex,
    required this.defaultSampleDuration,
    required this.defaultSampleSize,
  });

  final int? baseDataOffset;
  final int sampleDescriptionIndex;
  final int? defaultSampleDuration;
  final int? defaultSampleSize;
}

final class _TrackRun {
  const _TrackRun({required this.dataOffset, required this.entries});

  final int? dataOffset;
  final List<_TrackRunEntry> entries;
}

final class _TrackRunEntry {
  const _TrackRunEntry({required this.duration, required this.size});

  final int duration;
  final int size;
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}

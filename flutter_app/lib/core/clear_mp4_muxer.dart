import 'dart:typed_data';

import 'isobmff.dart';

final class Mp4MuxException implements Exception {
  const Mp4MuxException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Converts Apple's protected fragmented MP4 into a clear fragmented M4A.
///
/// CENC decryption preserves sample lengths, so the original timing, fragment,
/// and offset tables remain valid. The muxer replaces samples in place, restores
/// the protected audio sample entry's original format from `frma`, and turns
/// encryption-only boxes into same-sized `free` boxes.
final class ClearMp4Muxer {
  const ClearMp4Muxer();

  Uint8List mux(
    FragmentedSong source,
    List<List<int>> decryptedSamples,
  ) {
    if (source.samples.length != decryptedSamples.length) {
      throw Mp4MuxException(
        'Expected ${source.samples.length} decrypted samples, '
        'received ${decryptedSamples.length}',
      );
    }
    final output = Uint8List.fromList(source.raw);
    for (var index = 0; index < source.samples.length; index++) {
      final encrypted = source.samples[index];
      final decrypted = decryptedSamples[index];
      final offset = encrypted.offset;
      if (offset == null) {
        throw Mp4MuxException('Sample ${index + 1} has no source offset');
      }
      if (encrypted.data.length != decrypted.length) {
        throw Mp4MuxException(
          'Sample ${index + 1} changed length from '
          '${encrypted.data.length} to ${decrypted.length}',
        );
      }
      final end = offset + decrypted.length;
      if (offset < 0 || end > output.length) {
        throw Mp4MuxException('Sample ${index + 1} is outside the source MP4');
      }
      output.setRange(offset, end, decrypted);
    }

    for (final box in FragmentedMp4Extractor.parseBoxes(output)) {
      switch (box.type) {
        case 'ftyp':
          _setMajorBrand(output, box);
        case 'pssh':
          _setType(output, box, 'free');
        case 'moov':
        case 'moof':
          _patchContainer(output, box);
      }
    }
    return output;
  }

  static const _containers = {
    'moov',
    'trak',
    'mdia',
    'minf',
    'stbl',
    'mvex',
    'moof',
    'traf',
  };

  static const _fragmentProtectionBoxes = {'senc', 'saiz', 'saio'};

  static void _patchContainer(Uint8List bytes, IsoBox parent) {
    final children = FragmentedMp4Extractor.parseBoxes(
      bytes,
      start: parent.payloadOffset,
      end: parent.end,
    );
    for (final child in children) {
      if (child.type == 'pssh' ||
          (parent.type == 'traf' &&
              _fragmentProtectionBoxes.contains(child.type))) {
        _setType(bytes, child, 'free');
        continue;
      }
      if (child.type == 'stsd') {
        _patchSampleDescriptions(bytes, child);
        continue;
      }
      if (_containers.contains(child.type)) {
        _patchContainer(bytes, child);
      }
    }
  }

  static void _patchSampleDescriptions(Uint8List bytes, IsoBox stsd) {
    if (stsd.payloadOffset + 8 > stsd.end) {
      throw const Mp4MuxException('Truncated stsd box');
    }
    final entries = FragmentedMp4Extractor.parseBoxes(
      bytes,
      start: stsd.payloadOffset + 8,
      end: stsd.end,
    );
    for (final entry in entries.where((box) => box.type == 'enca')) {
      final childOffset = _audioSampleEntryChildOffset(bytes, entry);
      final children = FragmentedMp4Extractor.parseBoxes(
        bytes,
        start: childOffset,
        end: entry.end,
      );
      final sinf = _firstWhereOrNull(children, (box) => box.type == 'sinf');
      if (sinf == null) {
        throw const Mp4MuxException('Protected audio entry has no sinf box');
      }
      final protection = FragmentedMp4Extractor.parseBoxes(
        bytes,
        start: sinf.payloadOffset,
        end: sinf.end,
      );
      final frma = _firstWhereOrNull(protection, (box) => box.type == 'frma');
      if (frma == null || frma.payloadOffset + 4 > frma.end) {
        throw const Mp4MuxException('Protected audio entry has no frma format');
      }
      final originalFormat = String.fromCharCodes(
        bytes.sublist(frma.payloadOffset, frma.payloadOffset + 4),
      );
      _setType(bytes, entry, originalFormat);
      _setType(bytes, sinf, 'free');
    }
  }

  static int _audioSampleEntryChildOffset(Uint8List bytes, IsoBox entry) {
    if (entry.payloadOffset + 10 > entry.end) {
      throw const Mp4MuxException('Truncated protected audio sample entry');
    }
    final version = ByteData.sublistView(bytes).getUint16(
      entry.payloadOffset + 8,
    );
    final headerSize = switch (version) {
      0 => 28,
      1 => 44,
      2 => 64,
      _ => throw Mp4MuxException(
          'Unsupported audio sample entry version $version',
        ),
    };
    final offset = entry.payloadOffset + headerSize;
    if (offset > entry.end) {
      throw const Mp4MuxException('Truncated protected audio sample entry');
    }
    return offset;
  }

  static void _setMajorBrand(Uint8List bytes, IsoBox ftyp) {
    if (ftyp.payloadOffset + 4 <= ftyp.end) {
      bytes.setRange(ftyp.payloadOffset, ftyp.payloadOffset + 4, 'M4A '.codeUnits);
    }
  }

  static void _setType(Uint8List bytes, IsoBox box, String type) {
    if (type.codeUnits.length != 4) {
      throw Mp4MuxException('Invalid MP4 box type: $type');
    }
    bytes.setRange(box.offset + 4, box.offset + 8, type.codeUnits);
  }
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}

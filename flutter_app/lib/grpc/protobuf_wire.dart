import 'dart:convert';
import 'dart:typed_data';

/// Small proto3 wire codec used by the checked-in wrapper-manager messages.
///
/// Keeping the codec local avoids running protoc during every Android build.
/// The source-of-truth schema is `protos/manager.proto` copied unchanged from
/// WorldObservationLog/AppleMusicDecrypt v2.
final class ProtoWriter {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void stringField(int field, String value) {
    if (value.isEmpty) return;
    bytesField(field, utf8.encode(value));
  }

  void bytesField(int field, List<int> value) {
    if (value.isEmpty) return;
    _varint((field << 3) | 2);
    _varint(value.length);
    _bytes.add(value);
  }

  void messageField(int field, List<int> value) {
    _varint((field << 3) | 2);
    _varint(value.length);
    _bytes.add(value);
  }

  void int32Field(int field, int value) {
    if (value == 0) return;
    _varint(field << 3);
    _varint(value);
  }

  void boolField(int field, bool value) {
    if (!value) return;
    _varint(field << 3);
    _varint(1);
  }

  void _varint(int value) {
    var current = value;
    if (current < 0) {
      current = current.toUnsigned(64);
    }
    while (current > 0x7f) {
      _bytes.addByte((current & 0x7f) | 0x80);
      current >>= 7;
    }
    _bytes.addByte(current);
  }

  Uint8List takeBytes() => _bytes.takeBytes();
}

final class ProtoReader {
  ProtoReader(List<int> bytes) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool get isDone => _offset >= _bytes.length;

  ({int field, int wire}) readTag() {
    final tag = readVarint();
    return (field: tag >> 3, wire: tag & 7);
  }

  int readVarint() {
    var value = 0;
    var shift = 0;
    while (_offset < _bytes.length && shift < 70) {
      final byte = _bytes[_offset++];
      value |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return value;
      shift += 7;
    }
    throw const FormatException('Invalid protobuf varint');
  }

  Uint8List readBytes() {
    final length = readVarint();
    final end = _offset + length;
    if (length < 0 || end > _bytes.length) {
      throw const FormatException('Invalid protobuf length');
    }
    final value = Uint8List.sublistView(_bytes, _offset, end);
    _offset = end;
    return value;
  }

  String readString() => utf8.decode(readBytes());

  void skip(int wire) {
    switch (wire) {
      case 0:
        readVarint();
        return;
      case 1:
        _offset += 8;
        break;
      case 2:
        final length = readVarint();
        _offset += length;
        break;
      case 5:
        _offset += 4;
        break;
      default:
        throw FormatException('Unsupported protobuf wire type $wire');
    }
    if (_offset > _bytes.length) {
      throw const FormatException('Truncated protobuf field');
    }
  }
}

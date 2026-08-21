import 'dart:typed_data';

import 'protobuf_wire.dart';

abstract interface class ProtoMessage {
  Uint8List writeToBuffer();
}

final class EmptyMessage implements ProtoMessage {
  const EmptyMessage();

  @override
  Uint8List writeToBuffer() => Uint8List(0);
}

final class ReplyHeader implements ProtoMessage {
  const ReplyHeader({this.code = 0, this.msg = ''});

  factory ReplyHeader.fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var code = 0;
    var msg = '';
    while (!reader.isDone) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          code = reader.readVarint().toSigned(32);
          break;
        case 2:
          msg = reader.readString();
          break;
        default:
          reader.skip(tag.wire);
      }
    }
    return ReplyHeader(code: code, msg: msg);
  }

  final int code;
  final String msg;

  @override
  Uint8List writeToBuffer() {
    final writer = ProtoWriter()
      ..int32Field(1, code)
      ..stringField(2, msg);
    return writer.takeBytes();
  }
}

final class StatusData implements ProtoMessage {
  const StatusData({
    this.status = false,
    this.regions = const [],
    this.clientCount = 0,
    this.ready = false,
  });

  factory StatusData.fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var status = false;
    final regions = <String>[];
    var clientCount = 0;
    var ready = false;
    while (!reader.isDone) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          status = reader.readVarint() != 0;
          break;
        case 2:
          regions.add(reader.readString());
          break;
        case 3:
          clientCount = reader.readVarint().toSigned(32);
          break;
        case 4:
          ready = reader.readVarint() != 0;
          break;
        default:
          reader.skip(tag.wire);
      }
    }
    return StatusData(
      status: status,
      regions: List.unmodifiable(regions),
      clientCount: clientCount,
      ready: ready,
    );
  }

  final bool status;
  final List<String> regions;
  final int clientCount;
  final bool ready;

  @override
  Uint8List writeToBuffer() {
    final writer = ProtoWriter()..boolField(1, status);
    for (final region in regions) {
      writer.stringField(2, region);
    }
    writer
      ..int32Field(3, clientCount)
      ..boolField(4, ready);
    return writer.takeBytes();
  }
}

final class StatusReply implements ProtoMessage {
  const StatusReply({
    this.header = const ReplyHeader(),
    this.data = const StatusData(),
  });

  factory StatusReply.fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var header = const ReplyHeader();
    var data = const StatusData();
    while (!reader.isDone) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          header = ReplyHeader.fromBuffer(reader.readBytes());
          break;
        case 2:
          data = StatusData.fromBuffer(reader.readBytes());
          break;
        default:
          reader.skip(tag.wire);
      }
    }
    return StatusReply(header: header, data: data);
  }

  final ReplyHeader header;
  final StatusData data;

  @override
  Uint8List writeToBuffer() {
    final writer = ProtoWriter()
      ..messageField(1, header.writeToBuffer())
      ..messageField(2, data.writeToBuffer());
    return writer.takeBytes();
  }
}

final class LoginData implements ProtoMessage {
  const LoginData({
    this.username = '',
    this.password = '',
    this.twoStepCode = '',
  });

  factory LoginData.fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var username = '';
    var password = '';
    var twoStepCode = '';
    while (!reader.isDone) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          username = reader.readString();
          break;
        case 2:
          password = reader.readString();
          break;
        case 3:
          twoStepCode = reader.readString();
          break;
        default:
          reader.skip(tag.wire);
      }
    }
    return LoginData(
      username: username,
      password: password,
      twoStepCode: twoStepCode,
    );
  }

  final String username;
  final String password;
  final String twoStepCode;

  @override
  Uint8List writeToBuffer() {
    final writer = ProtoWriter()
      ..stringField(1, username)
      ..stringField(2, password)
      ..stringField(3, twoStepCode);
    return writer.takeBytes();
  }
}

final class LoginRequest implements ProtoMessage {
  const LoginRequest({required this.data});

  final LoginData data;

  @override
  Uint8List writeToBuffer() {
    final writer = ProtoWriter()..messageField(1, data.writeToBuffer());
    return writer.takeBytes();
  }
}

final class LoginReply implements ProtoMessage {
  const LoginReply({
    this.header = const ReplyHeader(),
    this.data = const LoginData(),
  });

  factory LoginReply.fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var header = const ReplyHeader();
    var data = const LoginData();
    while (!reader.isDone) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          header = ReplyHeader.fromBuffer(reader.readBytes());
          break;
        case 2:
          data = LoginData.fromBuffer(reader.readBytes());
          break;
        default:
          reader.skip(tag.wire);
      }
    }
    return LoginReply(header: header, data: data);
  }

  final ReplyHeader header;
  final LoginData data;

  @override
  Uint8List writeToBuffer() {
    final writer = ProtoWriter()
      ..messageField(1, header.writeToBuffer())
      ..messageField(2, data.writeToBuffer());
    return writer.takeBytes();
  }
}

final class LogoutData implements ProtoMessage {
  const LogoutData({this.username = ''});

  factory LogoutData.fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var username = '';
    while (!reader.isDone) {
      final tag = reader.readTag();
      if (tag.field == 1) {
        username = reader.readString();
      } else {
        reader.skip(tag.wire);
      }
    }
    return LogoutData(username: username);
  }

  final String username;

  @override
  Uint8List writeToBuffer() {
    final writer = ProtoWriter()..stringField(1, username);
    return writer.takeBytes();
  }
}

final class LogoutRequest implements ProtoMessage {
  const LogoutRequest({required this.data});

  final LogoutData data;

  @override
  Uint8List writeToBuffer() {
    final writer = ProtoWriter()..messageField(1, data.writeToBuffer());
    return writer.takeBytes();
  }
}

final class LogoutReply implements ProtoMessage {
  const LogoutReply({
    this.header = const ReplyHeader(),
    this.data = const LogoutData(),
  });

  factory LogoutReply.fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var header = const ReplyHeader();
    var data = const LogoutData();
    while (!reader.isDone) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          header = ReplyHeader.fromBuffer(reader.readBytes());
          break;
        case 2:
          data = LogoutData.fromBuffer(reader.readBytes());
          break;
        default:
          reader.skip(tag.wire);
      }
    }
    return LogoutReply(header: header, data: data);
  }

  final ReplyHeader header;
  final LogoutData data;

  @override
  Uint8List writeToBuffer() {
    final writer = ProtoWriter()
      ..messageField(1, header.writeToBuffer())
      ..messageField(2, data.writeToBuffer());
    return writer.takeBytes();
  }
}

final class DecryptData implements ProtoMessage {
  const DecryptData({
    this.adamId = '',
    this.key = '',
    this.sampleIndex = 0,
    this.sample = const [],
  });

  factory DecryptData.fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var adamId = '';
    var key = '';
    var sampleIndex = 0;
    Uint8List sample = Uint8List(0);
    while (!reader.isDone) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          adamId = reader.readString();
          break;
        case 2:
          key = reader.readString();
          break;
        case 3:
          sampleIndex = reader.readVarint().toSigned(32);
          break;
        case 4:
          sample = reader.readBytes();
          break;
        default:
          reader.skip(tag.wire);
      }
    }
    return DecryptData(
      adamId: adamId,
      key: key,
      sampleIndex: sampleIndex,
      sample: sample,
    );
  }

  final String adamId;
  final String key;
  final int sampleIndex;
  final List<int> sample;

  @override
  Uint8List writeToBuffer() {
    final writer = ProtoWriter()
      ..stringField(1, adamId)
      ..stringField(2, key)
      ..int32Field(3, sampleIndex)
      ..bytesField(4, sample);
    return writer.takeBytes();
  }
}

final class DecryptRequest implements ProtoMessage {
  const DecryptRequest({required this.data});

  final DecryptData data;

  @override
  Uint8List writeToBuffer() {
    final writer = ProtoWriter()..messageField(1, data.writeToBuffer());
    return writer.takeBytes();
  }
}

final class DecryptReply implements ProtoMessage {
  const DecryptReply({
    this.header = const ReplyHeader(),
    this.data = const DecryptData(),
  });

  factory DecryptReply.fromBuffer(List<int> bytes) {
    final reader = ProtoReader(bytes);
    var header = const ReplyHeader();
    var data = const DecryptData();
    while (!reader.isDone) {
      final tag = reader.readTag();
      switch (tag.field) {
        case 1:
          header = ReplyHeader.fromBuffer(reader.readBytes());
          break;
        case 2:
          data = DecryptData.fromBuffer(reader.readBytes());
          break;
        default:
          reader.skip(tag.wire);
      }
    }
    return DecryptReply(header: header, data: data);
  }

  final ReplyHeader header;
  final DecryptData data;

  @override
  Uint8List writeToBuffer() {
    final writer = ProtoWriter()
      ..messageField(1, header.writeToBuffer())
      ..messageField(2, data.writeToBuffer());
    return writer.takeBytes();
  }
}

import 'dart:typed_data';

/// 通用的二進制緩衝區讀取器
class BufferReader {
  final ByteData byteData;
  int _position;

  BufferReader(Uint8List bytes, [this._position = 0])
    : byteData = ByteData.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );

  void position(int index) {
    _position = index;
  }

  int get currentPosition => _position;

  int readUInt32() {
    final val = byteData.getUint32(_position, Endian.big);
    _position += 4;
    return val;
  }

  int readInt32() {
    final val = byteData.getInt32(_position, Endian.big);
    _position += 4;
    return val;
  }

  int readUInt16() {
    final val = byteData.getUint16(_position, Endian.big);
    _position += 2;
    return val;
  }

  int readInt16() {
    final val = byteData.getInt16(_position, Endian.big);
    _position += 2;
    return val;
  }

  int readUInt8() {
    final val = byteData.getUint8(_position);
    _position += 1;
    return val;
  }

  int readInt8() {
    final val = byteData.getInt8(_position);
    _position += 1;
    return val;
  }

  Uint8List readByteArray(int len) {
    final list = Uint8List(len);
    for (var i = 0; i < len; i++) {
      list[i] = byteData.getUint8(_position + i);
    }
    _position += len;
    return list;
  }

  List<int> readUInt8Array(int len) {
    final list = List<int>.filled(len, 0);
    for (var i = 0; i < len; i++) {
      list[i] = byteData.getUint8(_position);
      _position += 1;
    }
    return list;
  }

  List<int> readInt16Array(int len) {
    final list = List<int>.filled(len, 0);
    for (var i = 0; i < len; i++) {
      list[i] = byteData.getInt16(_position, Endian.big);
      _position += 2;
    }
    return list;
  }

  List<int> readUInt16Array(int len) {
    final list = List<int>.filled(len, 0);
    for (var i = 0; i < len; i++) {
      list[i] = byteData.getUint16(_position, Endian.big);
      _position += 2;
    }
    return list;
  }

  List<int> readInt32Array(int len) {
    final list = List<int>.filled(len, 0);
    for (var i = 0; i < len; i++) {
      list[i] = byteData.getInt32(_position, Endian.big);
      _position += 4;
    }
    return list;
  }
}

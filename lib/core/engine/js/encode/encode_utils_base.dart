import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/block/des_base.dart';
import 'package:pointycastle/export.dart' as pc;

/// JsEncodeUtils 的基礎常數與底層轉換
class EncodeUtilsBase {
  // --- Android Base64 Flags ---
  static const int base64Default = 0;
  static const int base64NoPadding = 1;
  static const int base64NoWrap = 2;
  static const int base64Crlf = 4;
  static const int base64UrlSafe = 8;

  static List<int> toBytes(dynamic data) {
    if (data is Uint8List) return data.toList();
    if (data is List<int>) {
      return data.map((value) => value & 0xFF).toList();
    }
    if (data is List) {
      if (data.every((item) => item is num)) {
        return data.map((item) => (item as num).toInt() & 0xFF).toList();
      }
    }
    if (data is String) return utf8.encode(data);
    throw ArgumentError('Unsupported data type: ${data.runtimeType}');
  }
}

/// 補償 PointyCastle 移除的單層 DESEngine 實作
class DESEngine extends DesBase implements pc.BlockCipher {
  static const int _blockSize = 8;
  List<int>? workingKey;
  bool forEncryption = false;

  @override
  String get algorithmName => 'DES';

  @override
  int get blockSize => _blockSize;

  @override
  void init(bool forEncryption, covariant pc.CipherParameters? params) {
    if (params is pc.KeyParameter) {
      this.forEncryption = forEncryption;
      final key = params.key;
      if (key.length != 8) throw ArgumentError('DES key size must be 8 bytes.');
      workingKey = generateWorkingKey(forEncryption, key);
    } else if (params is pc.ParametersWithIV) {
      this.forEncryption = forEncryption;
      final key = (params.parameters as pc.KeyParameter).key;
      if (key.length != 8) throw ArgumentError('DES key size must be 8 bytes.');
      workingKey = generateWorkingKey(forEncryption, key);
    }
  }

  @override
  Uint8List process(Uint8List data) {
    final out = Uint8List(_blockSize);
    final len = processBlock(data, 0, out, 0);
    return out.sublist(0, len);
  }

  @override
  int processBlock(Uint8List inp, int inpOff, Uint8List out, int outOff) {
    if (workingKey == null) throw StateError('DES engine not initialised');
    desFunc(workingKey!, inp, inpOff, out, outOff);
    return _blockSize;
  }

  @override
  void reset() {}
}

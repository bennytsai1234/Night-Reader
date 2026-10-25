import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/export.dart' as pc;

import 'encode_utils_base.dart';

/// 規則 JS 的對稱加解密（`java.createSymmetricCrypto` 與舊的 `aes*`、
/// `des*`、`tripleDES*`、Java `Cipher`）。照 Legado 用的 Hutool／Java 規則：
///
/// - 轉換字串 `演算法/模式/填充`，只寫演算法時是 `ECB/PKCS5Padding`；
///   GCM、CTR 沒寫填充時不填充。
/// - 演算法 AES、DES、DESede（3DES）；模式 ECB、CBC、CFB、OFB（不寫位數時
///   回饋一整個區塊，`CFB8` 這類照寫的位數）、CTR、GCM（128 位元標籤接在
///   密文後面）。
/// - 填充 PKCS5／PKCS7、NoPadding、ZeroPadding、ISO10126、ISO7816-4。
/// - 解密的字串看起來是十六進位就照十六進位解，否則照 Base64（網址安全
///   字元與少了 `=` 都收）。
/// - 需要 IV 卻沒給時用全 0（Hutool 會用隨機 IV，解密一定錯，全 0 至少和
///   其他實作一致）。
extension EncodeUtilsCrypto on EncodeUtilsBase {
  /// [action] 是 `encrypt` 或 `decrypt`。[outputFormat]：加密時 `base64`、
  /// `hex`、`bytes`；解密時 `string`（照 [charset]）、`bytes`、`hex`、
  /// `base64`。
  static dynamic symmetricCrypto(
    String action,
    String transformation,
    dynamic key,
    dynamic iv,
    dynamic data, {
    String outputFormat = 'base64',
    String charset = 'UTF-8',
  }) {
    final cipher = _Transformation.parse(transformation);
    final encrypt = action == 'encrypt';
    final input = encrypt
        ? Uint8List.fromList(EncodeUtilsBase.toBytes(data))
        : data is String
        ? decodeCipherText(data)
        : Uint8List.fromList(EncodeUtilsBase.toBytes(data));
    final output = cipher.process(
      encrypt: encrypt,
      key: _bytesOrNull(key) ?? Uint8List(0),
      iv: _bytesOrNull(iv),
      input: input,
    );
    if (encrypt) {
      return switch (outputFormat) {
        'hex' => hex.encode(output),
        'bytes' => output,
        _ => base64.encode(output),
      };
    }
    return switch (outputFormat) {
      'string' => decodeText(output, charset),
      'bytes' => output,
      'hex' => hex.encode(output),
      _ => base64.encode(output),
    };
  }

  /// Hutool `SecureUtil.decode`：十六進位字元組成、長度是偶數就照十六進位，
  /// 否則照 Base64。
  static Uint8List decodeCipherText(String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), '');
    if (clean.isNotEmpty &&
        clean.length.isEven &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)) {
      return Uint8List.fromList(hex.decode(clean));
    }
    return decodeBase64Lenient(clean);
  }

  /// 標準與網址安全的 Base64 都收，少了 `=` 自己補。
  static Uint8List decodeBase64Lenient(String text) {
    var clean = text
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '+')
        .replaceAll('_', '/')
        .replaceAll('=', '');
    final remainder = clean.length % 4;
    if (remainder == 1) {
      // 多出一個字元湊不成位元組，和 Java 的寬鬆解碼一樣丟掉。
      clean = clean.substring(0, clean.length - 1);
    } else if (remainder > 1) {
      clean = clean.padRight(clean.length + 4 - remainder, '=');
    }
    return base64.decode(clean);
  }

  static String decodeText(List<int> bytes, String charset) {
    final name = charset.toUpperCase();
    if (name.contains('GBK') || name.contains('GB2312')) {
      return gbk.decode(bytes);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Uint8List? _bytesOrNull(dynamic value) {
    if (value == null) return null;
    if (value is String && value.isEmpty) return null;
    return Uint8List.fromList(EncodeUtilsBase.toBytes(value));
  }
}

final class _Transformation {
  const _Transformation(
    this.algorithm,
    this.mode,
    this.feedbackBytes,
    this.padding,
  );

  final String algorithm;
  final String mode;

  /// CFB、OFB 每次回饋的位元組數；null 是一整個區塊。
  final int? feedbackBytes;
  final String padding;

  static _Transformation parse(String transformation) {
    final parts = transformation.trim().split('/');
    final algorithm = parts[0].trim().toUpperCase();
    final modeText = parts.length > 1 && parts[1].trim().isNotEmpty
        ? parts[1].trim().toUpperCase()
        : 'ECB';
    final match = RegExp(r'^([A-Z]+?)(\d*)$').firstMatch(modeText);
    final mode = match?.group(1) ?? modeText;
    final bits = int.tryParse(match?.group(2) ?? '');
    final padding = parts.length > 2 && parts[2].trim().isNotEmpty
        ? parts[2].trim().toUpperCase()
        : (mode == 'GCM' || mode == 'CTR' ? 'NOPADDING' : 'PKCS5PADDING');
    return _Transformation(
      algorithm,
      mode,
      bits == null ? null : bits ~/ 8,
      padding,
    );
  }

  pc.BlockCipher _engine() => switch (algorithm) {
    'AES' => pc.AESEngine(),
    'DES' => DESEngine(),
    'DESEDE' || 'TRIPLEDES' || '3DES' => DESedeEngine(),
    _ => throw UnsupportedError('不支援的加密演算法：$algorithm'),
  };

  Uint8List process({
    required bool encrypt,
    required Uint8List key,
    required Uint8List? iv,
    required Uint8List input,
  }) {
    final engine = _engine();
    final blockSize = engine.blockSize;
    final keyParameter = pc.KeyParameter(key);
    if (mode == 'GCM') {
      final gcm = pc.GCMBlockCipher(engine)
        ..init(
          encrypt,
          pc.AEADParameters(
            keyParameter,
            128,
            iv ?? Uint8List(12),
            Uint8List(0),
          ),
        );
      return gcm.process(input);
    }

    final ivBytes = iv ?? Uint8List(blockSize);
    final pc.BlockCipher cipher = switch (mode) {
      'ECB' => engine,
      'CBC' => pc.CBCBlockCipher(engine),
      'CFB' => pc.CFBBlockCipher(engine, feedbackBytes ?? blockSize),
      'OFB' => pc.OFBBlockCipher(engine, feedbackBytes ?? blockSize),
      'CTR' => pc.CTRBlockCipher(blockSize, pc.CTRStreamCipher(engine)),
      _ => throw UnsupportedError('不支援的加密模式：$mode'),
    };
    cipher.init(
      encrypt,
      mode == 'ECB' ? keyParameter : pc.ParametersWithIV(keyParameter, ivBytes),
    );

    final data = encrypt ? _pad(input, blockSize) : input;
    final isStream = mode == 'CFB' || mode == 'OFB' || mode == 'CTR';
    final chunk = cipher.blockSize;
    if (!isStream && data.length % chunk != 0) {
      throw ArgumentError(
        encrypt
            ? '資料長度不是 $chunk 的倍數，不填充（NoPadding）時要自己補齊'
            : '密文長度不是 $chunk 的倍數，可能不是這種加密的結果',
      );
    }
    final output = Uint8List(data.length);
    for (var offset = 0; offset < data.length; offset += chunk) {
      final remaining = data.length - offset;
      if (remaining >= chunk) {
        cipher.processBlock(data, offset, output, offset);
      } else {
        // 串流式的模式最後不滿一塊：補 0 算一塊，只取前面這幾個位元組。
        final last = Uint8List(chunk)..setRange(0, remaining, data, offset);
        final out = Uint8List(chunk);
        cipher.processBlock(last, 0, out, 0);
        output.setRange(offset, data.length, out);
      }
    }
    return encrypt ? output : _unpad(output, blockSize);
  }

  Uint8List _pad(Uint8List data, int blockSize) {
    switch (padding) {
      case 'NOPADDING':
        return data;
      case 'PKCS5PADDING' || 'PKCS7PADDING':
        final count = blockSize - data.length % blockSize;
        return Uint8List.fromList([...data, ...List.filled(count, count)]);
      case 'ZEROPADDING' || 'ZEROBYTEPADDING':
        final remainder = data.length % blockSize;
        if (remainder == 0) return data;
        return Uint8List.fromList([
          ...data,
          ...List.filled(blockSize - remainder, 0),
        ]);
      case 'ISO10126PADDING':
        final count = blockSize - data.length % blockSize;
        final random = Random.secure();
        return Uint8List.fromList([
          ...data,
          for (var i = 0; i < count - 1; i++) random.nextInt(256),
          count,
        ]);
      case 'ISO7816-4PADDING':
        final count = blockSize - data.length % blockSize;
        return Uint8List.fromList([
          ...data,
          0x80,
          ...List.filled(count - 1, 0),
        ]);
    }
    throw UnsupportedError('不支援的填充方式：$padding');
  }

  Uint8List _unpad(Uint8List data, int blockSize) {
    switch (padding) {
      case 'NOPADDING':
        return data;
      case 'PKCS5PADDING' || 'PKCS7PADDING':
        final count = data.isEmpty ? 0 : data.last;
        final valid =
            count >= 1 &&
            count <= blockSize &&
            count <= data.length &&
            data.sublist(data.length - count).every((b) => b == count);
        if (!valid) {
          throw ArgumentError('解密失敗：填充不對，金鑰、IV 或加密方式可能不對');
        }
        return data.sublist(0, data.length - count);
      case 'ZEROPADDING' || 'ZEROBYTEPADDING':
        var end = data.length;
        while (end > 0 && data[end - 1] == 0) {
          end--;
        }
        return data.sublist(0, end);
      case 'ISO10126PADDING':
        final count = data.isEmpty ? 0 : data.last;
        if (count < 1 || count > data.length) {
          throw ArgumentError('解密失敗：填充不對，金鑰、IV 或加密方式可能不對');
        }
        return data.sublist(0, data.length - count);
      case 'ISO7816-4PADDING':
        final marker = data.lastIndexOf(0x80);
        if (marker < 0) {
          throw ArgumentError('解密失敗：填充不對，金鑰、IV 或加密方式可能不對');
        }
        return data.sublist(0, marker);
    }
    throw UnsupportedError('不支援的填充方式：$padding');
  }
}

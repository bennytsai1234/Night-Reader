import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/export.dart' as pc;

import 'charsets.dart';
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
/// - 需要 IV 的模式沒給 IV 時丟錯；加密時 JS 端照 Java 先產生隨機 IV。
/// - 文字照 [charset] 轉位元組（[Charsets]）。
extension EncodeUtilsCrypto on EncodeUtilsBase {
  /// [action] 是 `encrypt` 或 `decrypt`。[outputFormat]：加密時 `base64`、
  /// `hex`、`bytes`；解密時 `string`（照 [charset]）、`bytes`、`hex`、
  /// `base64`。[tagBits] 是 GCM 驗證標籤的位元數。
  static dynamic symmetricCrypto(
    String action,
    String transformation,
    dynamic key,
    dynamic iv,
    dynamic data, {
    String outputFormat = 'base64',
    String charset = 'UTF-8',
    int tagBits = 128,
  }) {
    final cipher = _Transformation.parse(transformation);
    final encrypt = action == 'encrypt';
    final input = data is String
        ? (encrypt ? Charsets.encode(data, charset) : decodeCipherText(data))
        : Uint8List.fromList(EncodeUtilsBase.toBytes(data));
    final output = cipher.process(
      encrypt: encrypt,
      key: _bytesOrNull(key) ?? Uint8List(0),
      iv: _bytesOrNull(iv),
      input: input,
      tagBits: tagBits,
    );
    if (encrypt) {
      return switch (outputFormat) {
        'hex' => hex.encode(output),
        'bytes' => output,
        _ => base64.encode(output),
      };
    }
    return switch (outputFormat) {
      'string' => Charsets.decode(output, charset),
      'bytes' => output,
      'hex' => hex.encode(output),
      _ => base64.encode(output),
    };
  }

  /// Hutool `SecureUtil.decode`：整段（不先去空白）都是十六進位字元、長度
  /// 是偶數就照十六進位，否則照 Base64。
  static Uint8List decodeCipherText(String text) {
    if (text.isNotEmpty &&
        text.length.isEven &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(text)) {
      return Uint8List.fromList(hex.decode(text));
    }
    return decodeBase64Lenient(text);
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

  /// 空字串與空陣列都當成沒給（Legado `JsEncodeUtils.createSymmetricCrypto`
  /// 不設空的 IV）。
  static Uint8List? _bytesOrNull(dynamic value) {
    if (value == null) return null;
    if (value is String && value.isEmpty) return null;
    if (value is List && value.isEmpty) return null;
    return Uint8List.fromList(EncodeUtilsBase.toBytes(value));
  }
}

final class _Transformation {
  const _Transformation(
    this.algorithm,
    this.modeText,
    this.mode,
    this.feedbackBits,
    this.padding,
  );

  final String algorithm;
  final String modeText;
  final String mode;

  /// CFB、OFB 寫在模式後面的回饋位元數（`CFB8`）；null 是一整個區塊。
  final int? feedbackBits;
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
    return _Transformation(algorithm, modeText, mode, bits, padding);
  }

  /// CFB、OFB 每次處理的位元組數。和 Java 一樣只收 8 的倍數、不超過一個
  /// 區塊；其他模式不能帶位數。
  int _feedbackBytes(int blockSize) {
    final bits = feedbackBits;
    if (bits == null) return blockSize;
    final valid =
        (mode == 'CFB' || mode == 'OFB') &&
        bits % 8 == 0 &&
        bits >= 8 &&
        bits <= blockSize * 8;
    if (!valid) throw UnsupportedError('不支援的加密模式：$modeText');
    return bits ~/ 8;
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
    required int tagBits,
  }) {
    final engine = _engine();
    final blockSize = engine.blockSize;
    final keyParameter = pc.KeyParameter(key);
    if (mode != 'ECB' && iv == null) {
      throw ArgumentError('$modeText 模式需要 IV');
    }
    if (mode == 'GCM') {
      if (tagBits % 8 != 0 || tagBits < 32 || tagBits > 128) {
        throw ArgumentError('GCM 驗證標籤長度不對：$tagBits 位元');
      }
      if (!encrypt && input.length < tagBits ~/ 8) {
        throw ArgumentError('密文比驗證標籤還短，可能不是這種加密的結果');
      }
      Uint8List gcm(bool forEncryption, Uint8List data) =>
          (pc.GCMBlockCipher(_engine())..init(
                forEncryption,
                pc.AEADParameters(keyParameter, 128, iv!, Uint8List(0)),
              ))
              .process(data);
      if (tagBits == 128) return gcm(encrypt, input);
      // pointycastle 只做 128 位元標籤。較短的標籤就是完整標籤的前幾個位元
      // 組：加密時截短；解密時先用全 0 取得金鑰流解出明文，再重算完整標籤
      // 比對前幾個位元組。
      final tagBytes = tagBits ~/ 8;
      if (encrypt) return gcm(true, input).sublist(0, input.length + tagBytes);
      final textLength = input.length - tagBytes;
      final keyStream = gcm(true, Uint8List(textLength));
      final plain = Uint8List(textLength);
      for (var i = 0; i < textLength; i++) {
        plain[i] = input[i] ^ keyStream[i];
      }
      final tag = gcm(true, plain).sublist(textLength, input.length);
      var difference = 0;
      for (var i = 0; i < tagBytes; i++) {
        difference |= tag[i] ^ input[textLength + i];
      }
      if (difference != 0) {
        throw ArgumentError('解密失敗：驗證標籤不符，金鑰、IV 或密文可能不對');
      }
      return plain;
    }

    final pc.BlockCipher cipher = switch (mode) {
      'ECB' => engine,
      'CBC' => pc.CBCBlockCipher(engine),
      'CFB' => pc.CFBBlockCipher(engine, _feedbackBytes(blockSize)),
      'OFB' => pc.OFBBlockCipher(engine, _feedbackBytes(blockSize)),
      'CTR' => pc.CTRBlockCipher(blockSize, pc.CTRStreamCipher(engine)),
      _ => throw UnsupportedError('不支援的加密模式：$modeText'),
    };
    if (mode != 'CFB' && mode != 'OFB') _feedbackBytes(blockSize);
    if (mode != 'ECB' && iv!.length != blockSize) {
      throw ArgumentError('IV 長度要是 $blockSize 個位元組，拿到 ${iv.length} 個');
    }
    cipher.init(
      encrypt,
      mode == 'ECB' ? keyParameter : pc.ParametersWithIV(keyParameter, iv!),
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
        if (count < 1 || count > blockSize || count > data.length) {
          throw ArgumentError('解密失敗：填充不對，金鑰、IV 或加密方式可能不對');
        }
        return data.sublist(0, data.length - count);
      case 'ISO7816-4PADDING':
        // 從最後往前只能是 0，直到 0x80，而且都在最後一個區塊裡。
        var marker = data.length - 1;
        while (marker >= 0 && data[marker] == 0) {
          marker--;
        }
        if (marker < 0 ||
            data[marker] != 0x80 ||
            data.length - marker > blockSize) {
          throw ArgumentError('解密失敗：填充不對，金鑰、IV 或加密方式可能不對');
        }
        return data.sublist(0, marker);
    }
    throw UnsupportedError('不支援的填充方式：$padding');
  }
}

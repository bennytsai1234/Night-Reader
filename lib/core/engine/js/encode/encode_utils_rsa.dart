import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart' as pc;

import 'encode_utils_base.dart';
import 'encode_utils_crypto.dart';

/// 規則 JS 的 RSA（`java.createAsymmetricCrypto`）與簽章（`java.createSign`），
/// 照 Legado `help/crypto/AsymmetricCrypto.kt`、`Sign.kt`（Hutool）：
///
/// - 金鑰是 DER 位元組：私鑰 PKCS#8（也收 PKCS#1），公鑰 X.509（也收
///   PKCS#1）。字串金鑰照 Base64 解（Legado 直接取字串的位元組，那樣解不
///   出金鑰，書源都傳位元組）。
/// - `usePublicKey` 預設 true 用公鑰，false 用私鑰。
/// - 比金鑰長的資料照 Hutool 分塊：加密每塊最多（金鑰長度 − 11），解密每
///   塊一個金鑰長度。
/// - 填充 PKCS1Padding、OAEPPadding（SHA-1）、NoPadding。
abstract final class EncodeUtilsRsa {
  static Uint8List process({
    required String transformation,
    required bool encrypt,
    required bool usePublicKey,
    required dynamic publicKey,
    required dynamic privateKey,
    required dynamic data,
  }) {
    final key = usePublicKey
        ? (publicKey == null ? null : parsePublicKey(_keyBytes(publicKey)))
        : (privateKey == null ? null : parsePrivateKey(_keyBytes(privateKey)));
    if (key == null) {
      throw ArgumentError(usePublicKey ? '還沒設定 RSA 公鑰' : '還沒設定 RSA 私鑰');
    }
    final input = encrypt || data is! String
        ? Uint8List.fromList(EncodeUtilsBase.toBytes(data))
        : EncodeUtilsCrypto.decodeCipherText(data);

    final padding = _padding(transformation);
    final modulus = key is pc.RSAPublicKey
        ? key.modulus!
        : (key as pc.RSAPrivateKey).modulus!;
    final keyBytes = (modulus.bitLength + 7) ~/ 8;
    final pc.AsymmetricBlockCipher cipher;
    final int encryptBlock;
    switch (padding) {
      case 'NOPADDING':
        cipher = pc.RSAEngine();
        encryptBlock = keyBytes;
      case 'PKCS1PADDING':
        cipher = pc.PKCS1Encoding(pc.RSAEngine());
        encryptBlock = keyBytes - 11;
      default:
        // OAEP：訊息摘要與 MGF1 用同一個（Android 的提供者也是）。
        final digest = padding;
        cipher = pc.OAEPEncoding.withCustomDigest(
          () => pc.Digest(digest),
          pc.RSAEngine(),
        );
        encryptBlock = keyBytes - 2 * pc.Digest(digest).digestSize - 2;
    }
    final pc.CipherParameters parameters = key is pc.RSAPublicKey
        ? pc.PublicKeyParameter<pc.RSAPublicKey>(key)
        : pc.PrivateKeyParameter<pc.RSAPrivateKey>(key as pc.RSAPrivateKey);
    // PKCS1 與 OAEP 加密時要亂數填充；不填充的 RSAEngine 只收金鑰。
    cipher.init(
      encrypt,
      encrypt && padding != 'NOPADDING'
          ? pc.ParametersWithRandom(parameters, _secureRandom())
          : parameters,
    );

    // 照 Hutool 分塊：加密每塊最多 [encryptBlock]，解密每塊一個金鑰長度。
    // 密文與不填充的輸出照 Java 補滿一個金鑰長度（前面補 0）。空資料也
    // 照樣處理一塊。
    final block = encrypt ? encryptBlock : keyBytes;
    final fixedLength = encrypt || padding == 'NOPADDING';
    final output = BytesBuilder();
    var offset = 0;
    do {
      final end = min(offset + block, input.length);
      final out = cipher.process(Uint8List.sublistView(input, offset, end));
      output.add(fixedLength ? _leftPad(out, keyBytes) : out);
      offset = end;
    } while (offset < input.length);
    return output.toBytes();
  }

  /// 轉換字串的填充：`PKCS1PADDING`、`NOPADDING`，或 OAEP 用的摘要名稱。
  static String _padding(String transformation) {
    final parts = transformation.trim().toUpperCase().split('/');
    if (parts[0] != 'RSA') {
      throw UnsupportedError('不支援的非對稱加密：$transformation');
    }
    final padding = parts.length > 2 ? parts[2] : 'PKCS1PADDING';
    if (padding == 'PKCS1PADDING' || padding == 'NOPADDING') return padding;
    if (padding == 'OAEPPADDING') return 'SHA-1';
    final match = RegExp(r'^OAEPWITH(.+)ANDMGF1PADDING$').firstMatch(padding);
    if (match == null) {
      throw UnsupportedError('不支援的 RSA 填充：$padding');
    }
    return switch (match.group(1)!.replaceAll('-', '')) {
      'SHA1' => 'SHA-1',
      'SHA224' => 'SHA-224',
      'SHA256' => 'SHA-256',
      'SHA384' => 'SHA-384',
      'SHA512' => 'SHA-512',
      'MD5' => 'MD5',
      final other => throw UnsupportedError('不支援的 OAEP 摘要：$other'),
    };
  }

  static Uint8List _leftPad(Uint8List bytes, int length) {
    if (bytes.length >= length) return bytes;
    return Uint8List(length)..setRange(length - bytes.length, length, bytes);
  }

  /// Hutool 沒設定金鑰時自動產生一組（預設 1024 位元）。傳回 DER：公鑰
  /// X.509、私鑰 PKCS#8。
  static ({Uint8List publicKey, Uint8List privateKey}) generateKeyPair([
    int bits = 1024,
  ]) {
    final generator = pc.RSAKeyGenerator()
      ..init(
        pc.ParametersWithRandom(
          pc.RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
          _secureRandom(),
        ),
      );
    final pair = generator.generateKeyPair();
    final public = pair.publicKey;
    final private = pair.privateKey;
    final algorithm = ASN1Sequence(
      elements: [
        ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.1'),
        ASN1Null(),
      ],
    );
    final publicDer = ASN1Sequence(
      elements: [
        algorithm,
        ASN1BitString(
          stringValues: ASN1Sequence(
            elements: [
              ASN1Integer(public.modulus),
              ASN1Integer(public.exponent),
            ],
          ).encode(),
        ),
      ],
    ).encode();
    final p = private.p!;
    final q = private.q!;
    final d = private.privateExponent!;
    final privateDer = ASN1Sequence(
      elements: [
        ASN1Integer(BigInt.zero),
        algorithm,
        ASN1OctetString(
          octets: ASN1Sequence(
            elements: [
              ASN1Integer(BigInt.zero),
              ASN1Integer(private.modulus),
              ASN1Integer(public.exponent),
              ASN1Integer(d),
              ASN1Integer(p),
              ASN1Integer(q),
              ASN1Integer(d % (p - BigInt.one)),
              ASN1Integer(d % (q - BigInt.one)),
              ASN1Integer(q.modInverse(p)),
            ],
          ).encode(),
        ),
      ],
    ).encode();
    return (publicKey: publicDer, privateKey: privateDer);
  }

  /// `SHA256withRSA` 這類名稱。
  static Uint8List sign(String algorithm, dynamic privateKey, dynamic data) {
    final signer = pc.Signer(_signerName(algorithm))
      ..init(
        true,
        pc.PrivateKeyParameter<pc.RSAPrivateKey>(
          parsePrivateKey(_keyBytes(privateKey)),
        ),
      );
    final signature = signer.generateSignature(
      Uint8List.fromList(EncodeUtilsBase.toBytes(data)),
    ) as pc.RSASignature;
    return signature.bytes;
  }

  static bool verify(
    String algorithm,
    dynamic publicKey,
    dynamic data,
    dynamic signature,
  ) {
    final signer = pc.Signer(_signerName(algorithm))
      ..init(
        false,
        pc.PublicKeyParameter<pc.RSAPublicKey>(
          parsePublicKey(_keyBytes(publicKey)),
        ),
      );
    final bytes = signature is String
        ? EncodeUtilsCrypto.decodeCipherText(signature)
        : Uint8List.fromList(EncodeUtilsBase.toBytes(signature));
    return signer.verifySignature(
      Uint8List.fromList(EncodeUtilsBase.toBytes(data)),
      pc.RSASignature(bytes),
    );
  }

  static String _signerName(String algorithm) {
    final match = RegExp(
      r'^(\w+?)with(RSA)$',
      caseSensitive: false,
    ).firstMatch(algorithm.trim());
    if (match == null) {
      throw UnsupportedError('不支援的簽章演算法：$algorithm');
    }
    final digest = match.group(1)!.toUpperCase().replaceAll('-', '');
    final name = switch (digest) {
      'SHA1' => 'SHA-1',
      'SHA224' => 'SHA-224',
      'SHA256' => 'SHA-256',
      'SHA384' => 'SHA-384',
      'SHA512' => 'SHA-512',
      _ => digest,
    };
    return '$name/RSA';
  }

  static Uint8List _keyBytes(dynamic key) => key is String
      ? EncodeUtilsCrypto.decodeBase64Lenient(key)
      : Uint8List.fromList(EncodeUtilsBase.toBytes(key));

  static pc.RSAPrivateKey parsePrivateKey(Uint8List der) {
    var sequence = ASN1Parser(der).nextObject() as ASN1Sequence;
    final elements = sequence.elements!;
    // PKCS#8：[版本, 演算法, OCTET STRING(PKCS#1 私鑰)]
    if (elements.length == 3 && elements[1] is ASN1Sequence) {
      final octets = (elements[2] as ASN1OctetString).octets!;
      sequence = ASN1Parser(octets).nextObject() as ASN1Sequence;
    }
    final values = sequence.elements!;
    BigInt at(int index) => (values[index] as ASN1Integer).integer!;
    return pc.RSAPrivateKey(at(1), at(3), at(4), at(5));
  }

  static pc.RSAPublicKey parsePublicKey(Uint8List der) {
    var sequence = ASN1Parser(der).nextObject() as ASN1Sequence;
    final elements = sequence.elements!;
    // X.509：[演算法, BIT STRING(PKCS#1 公鑰)]
    if (elements.length == 2 && elements[0] is ASN1Sequence) {
      final bits = (elements[1] as ASN1BitString).stringValues!;
      sequence =
          ASN1Parser(Uint8List.fromList(bits)).nextObject() as ASN1Sequence;
    }
    final values = sequence.elements!;
    return pc.RSAPublicKey(
      (values[0] as ASN1Integer).integer!,
      (values[1] as ASN1Integer).integer!,
    );
  }

  static String toHex(List<int> bytes) => hex.encode(bytes);

  static pc.SecureRandom _secureRandom() {
    final random = Random.secure();
    return pc.FortunaRandom()..seed(
      pc.KeyParameter(
        Uint8List.fromList(List.generate(32, (_) => random.nextInt(256))),
      ),
    );
  }
}

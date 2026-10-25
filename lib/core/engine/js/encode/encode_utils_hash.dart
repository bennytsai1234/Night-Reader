import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:convert/convert.dart';
import 'package:pointycastle/export.dart' as pc;

import 'encode_utils_base.dart';

/// JsEncodeUtils 的雜湊與摘要算法擴展。演算法名稱照 Java 的寫法
/// （`SHA-256`、`SHA256`、`HmacSHA256`、`HMAC-SHA1` 都收）。
extension EncodeUtilsHash on EncodeUtilsBase {
  static String md5Encode(String str) =>
      hex.encode(digestBytes(utf8.encode(str), 'MD5'));
  static String md5Encode16(String str) => md5Encode(str).substring(8, 24);

  static String crc32(dynamic data) {
    final bytes = EncodeUtilsBase.toBytes(data);
    return getCrc32(bytes).toRadixString(16);
  }

  static Uint8List digestBytes(List<int> data, String algorithm) =>
      pc.Digest(_digestName(algorithm)).process(Uint8List.fromList(data));

  static String digest(String data, String algorithm, {bool hexFormat = true}) {
    final result = digestBytes(utf8.encode(data), algorithm);
    return hexFormat ? hex.encode(result) : base64.encode(result);
  }

  static Uint8List hmacBytes(List<int> data, String algorithm, List<int> key) {
    final name = algorithm.trim().toUpperCase().replaceFirst(
      RegExp(r'^HMAC[-_/]?'),
      '',
    );
    final mac = pc.Mac('${_digestName(name)}/HMAC')
      ..init(pc.KeyParameter(Uint8List.fromList(key)));
    return mac.process(Uint8List.fromList(data));
  }

  static String hmacHex(String data, String algorithm, String key) =>
      hex.encode(hmacBytes(utf8.encode(data), algorithm, utf8.encode(key)));

  static String hmacBase64(String data, String algorithm, String key) =>
      base64.encode(hmacBytes(utf8.encode(data), algorithm, utf8.encode(key)));

  /// Java 與 Hutool 的寫法換成 pointycastle 的名稱。
  static String _digestName(String algorithm) {
    final name = algorithm.trim().toUpperCase().replaceAll('_', '-');
    final compact = name.replaceAll('-', '');
    return switch (compact) {
      'SHA' || 'SHA1' => 'SHA-1',
      'SHA224' => 'SHA-224',
      'SHA256' => 'SHA-256',
      'SHA384' => 'SHA-384',
      'SHA512' => 'SHA-512',
      'SHA512/224' => 'SHA-512/224',
      'SHA512/256' => 'SHA-512/256',
      'SHA3224' => 'SHA3-224',
      'SHA3256' => 'SHA3-256',
      'SHA3384' => 'SHA3-384',
      'SHA3512' => 'SHA3-512',
      'RIPEMD160' => 'RIPEMD-160',
      'RIPEMD128' => 'RIPEMD-128',
      'RIPEMD256' => 'RIPEMD-256',
      'RIPEMD320' => 'RIPEMD-320',
      _ => name,
    };
  }
}

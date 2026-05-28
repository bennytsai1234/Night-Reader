import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'encode_utils_base.dart';

/// JsEncodeUtils 的雜湊與摘要算法擴展
extension EncodeUtilsHash on EncodeUtilsBase {
  static String md5Encode(String str) =>
      md5.convert(utf8.encode(str)).toString();
  static String md5Encode16(String str) => md5Encode(str).substring(8, 24);

  static String crc32(dynamic data) {
    final bytes = EncodeUtilsBase.toBytes(data);
    return getCrc32(bytes).toRadixString(16);
  }

  static String hmacHex(String data, String algorithm, String key) {
    final keyBytes = utf8.encode(key);
    final dataBytes = utf8.encode(data);
    Hmac hmac;
    switch (algorithm.toUpperCase()) {
      case 'HMACMD5':
        hmac = Hmac(md5, keyBytes);
        break;
      case 'HMACSHA1':
        hmac = Hmac(sha1, keyBytes);
        break;
      case 'HMACSHA256':
        hmac = Hmac(sha256, keyBytes);
        break;
      default:
        throw UnsupportedError('Unsupported HMAC algorithm: $algorithm');
    }
    return hmac.convert(dataBytes).toString();
  }

  static String digest(String data, String algorithm, {bool hexFormat = true}) {
    Hash hasher;
    switch (algorithm.toUpperCase()) {
      case 'SHA-1':
      case 'SHA1':
        hasher = sha1;
        break;
      case 'SHA-256':
      case 'SHA256':
        hasher = sha256;
        break;
      case 'MD5':
        hasher = md5;
        break;
      default:
        throw UnsupportedError('Unsupported digest algorithm: $algorithm');
    }
    final result = hasher.convert(utf8.encode(data));
    return hexFormat ? result.toString() : base64.encode(result.bytes);
  }
}

import 'dart:typed_data';
import 'encode/encode_utils_base.dart';
import 'encode/encode_utils_hash.dart';
import 'encode/encode_utils_base64.dart';
import 'encode/encode_utils_crypto.dart';

export 'encode/encode_utils_base.dart';
export 'encode/encode_utils_hash.dart';
export 'encode/encode_utils_base64.dart';
export 'encode/encode_utils_crypto.dart';

/// JsEncodeUtils - JS 加解密工具類 (重構後)
/// (原 Android help/JsEncodeUtils.kt)
class JsEncodeUtils extends EncodeUtilsBase {
  /// MD5 加密 (32位)
  static String md5Encode(String str) => EncodeUtilsHash.md5Encode(str);

  /// MD5 加密 (16位)
  static String md5Encode16(String str) => EncodeUtilsHash.md5Encode16(str);

  /// Base64 編碼 (支援 Flags)
  static String base64Encode(dynamic data, {int flags = 0}) =>
      EncodeUtilsBase64.base64Encode(data, flags: flags);

  /// Base64 解碼
  static String base64Decode(
    String str, {
    String charset = 'UTF-8',
    int flags = 0,
  }) => EncodeUtilsBase64.base64Decode(str, charset: charset, flags: flags);

  static Uint8List base64DecodeToBytes(String str, {int flags = 0}) =>
      EncodeUtilsBase64.base64DecodeToBytes(str, flags: flags);

  /// CRC32 校驗
  static String crc32(dynamic data) => EncodeUtilsHash.crc32(data);

  /// 十六進位解碼為位元組陣列
  static Uint8List hexDecodeToByteArray(String hexStr) =>
      EncodeUtilsBase64.hexDecodeToByteArray(hexStr);

  /// 字串轉十六進位
  static String hexEncodeToString(String str) =>
      EncodeUtilsBase64.hexEncodeToString(str);

  /// 對稱加密/解密
  static dynamic symmetricCrypto(
    String action,
    String transformation,
    dynamic key,
    dynamic iv,
    dynamic data, {
    String outputFormat = 'base64',
  }) => EncodeUtilsCrypto.symmetricCrypto(
    action,
    transformation,
    key,
    iv,
    data,
    outputFormat: outputFormat,
  );

  // === AES Variants ===
  static dynamic aesEncode(
    String data,
    String key,
    String transformation,
    String iv, {
    String format = 'base64',
  }) => symmetricCrypto(
    'encrypt',
    transformation,
    key,
    iv,
    data,
    outputFormat: format,
  );

  static dynamic aesDecode(
    String data,
    String key,
    String transformation,
    String iv, {
    String format = 'string',
  }) => symmetricCrypto(
    'decrypt',
    transformation,
    key,
    iv,
    data,
    outputFormat: format,
  );

  // === HMAC ===
  static String hmacHex(String data, String algorithm, String key) =>
      EncodeUtilsHash.hmacHex(data, algorithm, key);

  /// 摘要算法
  static String digest(
    String data,
    String algorithm, {
    bool hexFormat = true,
  }) => EncodeUtilsHash.digest(data, algorithm, hexFormat: hexFormat);
}

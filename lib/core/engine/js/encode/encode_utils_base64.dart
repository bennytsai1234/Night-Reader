import 'dart:convert';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'encode_utils_base.dart';

/// JsEncodeUtils 的 Base64 與 Hex 轉碼擴展
extension EncodeUtilsBase64 on EncodeUtilsBase {
  static String base64Encode(dynamic data, {int flags = 0}) {
    final bytes = EncodeUtilsBase.toBytes(data);
    var result =
        (flags & EncodeUtilsBase.base64UrlSafe) != 0
            ? base64Url.encode(bytes)
            : base64.encode(bytes);
    if ((flags & EncodeUtilsBase.base64NoPadding) != 0)
      result = result.replaceAll('=', '');
    return result;
  }

  static String base64Decode(
    String str, {
    String charset = 'UTF-8',
    int flags = 0,
  }) {
    final cleanStr = str.replaceAll(RegExp(r'\s+'), '');
    var paddedStr = cleanStr;
    if (cleanStr.length % 4 != 0)
      paddedStr = cleanStr.padRight(
        cleanStr.length + (4 - cleanStr.length % 4),
        '=',
      );
    final bytes =
        (flags & EncodeUtilsBase.base64UrlSafe) != 0
            ? base64Url.decode(paddedStr)
            : base64.decode(paddedStr);
    if (charset.toUpperCase().contains('GBK') ||
        charset.toUpperCase().contains('GB2312'))
      return gbk.decode(bytes);
    return utf8.decode(bytes);
  }

  static Uint8List base64DecodeToBytes(String str, {int flags = 0}) {
    final cleanStr = str.replaceAll(RegExp(r'\s+'), '');
    var paddedStr = cleanStr;
    if (cleanStr.length % 4 != 0)
      paddedStr = cleanStr.padRight(
        cleanStr.length + (4 - cleanStr.length % 4),
        '=',
      );
    return (flags & EncodeUtilsBase.base64UrlSafe) != 0
        ? base64Url.decode(paddedStr)
        : base64.decode(paddedStr);
  }

  static Uint8List hexDecodeToByteArray(String hexStr) =>
      Uint8List.fromList(hex.decode(hexStr));
  static String hexEncodeToString(String str) => hex.encode(utf8.encode(str));
}

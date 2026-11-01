import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';

import 'charsets.dart';
import 'encode_utils_base.dart';

/// JsEncodeUtils 的 Base64 與 Hex 轉碼擴展
extension EncodeUtilsBase64 on EncodeUtilsBase {
  /// 照 Android `Base64.encodeToString(bytes, flags)`；預設 NO_WRAP，同
  /// Legado 的 `java.base64Encode`。沒有 NO_WRAP 時每 76 個字元換一行、最後
  /// 也換行（CRLF 時用 `\r\n`）。
  static String base64Encode(
    dynamic data, {
    int flags = EncodeUtilsBase.base64NoWrap,
  }) {
    final bytes = EncodeUtilsBase.toBytes(data);
    var result = (flags & EncodeUtilsBase.base64UrlSafe) != 0
        ? base64Url.encode(bytes)
        : base64.encode(bytes);
    if ((flags & EncodeUtilsBase.base64NoPadding) != 0) {
      result = result.replaceAll('=', '');
    }
    if ((flags & EncodeUtilsBase.base64NoWrap) == 0 && result.isNotEmpty) {
      final newline = (flags & EncodeUtilsBase.base64Crlf) != 0 ? '\r\n' : '\n';
      final lines = [
        for (var i = 0; i < result.length; i += 76)
          result.substring(i, i + 76 > result.length ? result.length : i + 76),
      ];
      result = '${lines.join(newline)}$newline';
    }
    return result;
  }

  static String base64Decode(
    String str, {
    String charset = 'UTF-8',
    int flags = 0,
  }) {
    // 照 Java 的 String(bytes, charset)；不認得的字元集丟錯誤。
    return Charsets.decode(base64DecodeToBytes(str, flags: flags), charset);
  }

  /// 空白與換行略過、缺的 `=` 補上；兩種字母表（`+/` 與 `-_`）都收，同
  /// Legado 一個參數的 `base64Decode`（Hutool）。
  static Uint8List base64DecodeToBytes(String str, {int flags = 0}) {
    final cleanStr = str
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    var paddedStr = cleanStr;
    if (cleanStr.length % 4 != 0) {
      paddedStr = cleanStr.padRight(
        cleanStr.length + (4 - cleanStr.length % 4),
        '=',
      );
    }
    return base64.decode(paddedStr);
  }

  static Uint8List hexDecodeToByteArray(String hexStr) =>
      Uint8List.fromList(hex.decode(hexStr));
  static String hexEncodeToString(String str) => hex.encode(utf8.encode(str));
}

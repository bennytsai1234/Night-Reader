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

  /// [flags] 是 null 時照 Legado 一個或兩個參數（字元集）的 `base64Decode`
  /// （Hutool），有給時照 `android.util.Base64.decode(str, flags)`。
  static String base64Decode(
    String str, {
    String charset = 'UTF-8',
    int? flags,
  }) {
    // 照 Java 的 String(bytes, charset)；不認得的字元集丟錯誤。
    return Charsets.decode(base64DecodeToBytes(str, flags: flags), charset);
  }

  /// [flags] 是 null 時照 Hutool 的 `Base64.decode`：兩種字母表（`+/` 與
  /// `-_`）都收，字母表以外的字元（含 `=`）全部略過，缺的補位不用寫。有給
  /// 時照 Android：URL_SAFE（8）收 `-_`，否則收 `+/`，其他字元略過，`=`
  /// 只能出現在結尾。
  static Uint8List base64DecodeToBytes(String str, {int? flags}) =>
      flags == null
      ? decodeHutool(str)
      : decodeAndroid(
          str,
          urlSafe: (flags & EncodeUtilsBase.base64UrlSafe) != 0,
        );

  static const _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  static const _skip = -1;
  static const _equals = -2;

  static Int8List _table(String last2) {
    final table = Int8List(256)..fillRange(0, 256, _skip);
    final chars = '$_alphabet$last2';
    for (var i = 0; i < 64; i++) {
      table[chars.codeUnitAt(i)] = i;
    }
    return table;
  }

  static final Int8List _standardTable = _table('+/')..[0x3D] = _equals;
  static final Int8List _urlSafeTable = _table('-_')..[0x3D] = _equals;
  static final Int8List _hutoolTable = _table('+/')
    ..[0x2D] = 62
    ..[0x5F] = 63;

  /// Hutool `Base64Decoder.decode`：不是字母表的字元略過，四個一組，最後
  /// 剩 2 個出 1 位元組、剩 3 個出 2 位元組、剩 1 個丟掉。
  static Uint8List decodeHutool(String str) {
    final out = BytesBuilder(copy: false);
    var count = 0;
    var value = 0;
    for (final unit in utf8.encode(str)) {
      final d = _hutoolTable[unit];
      if (d < 0) continue;
      value = (value << 6) | d;
      if (++count == 4) {
        out
          ..addByte((value >> 16) & 0xFF)
          ..addByte((value >> 8) & 0xFF)
          ..addByte(value & 0xFF);
        count = 0;
        value = 0;
      }
    }
    if (count == 2) out.addByte((value >> 4) & 0xFF);
    if (count == 3) {
      out
        ..addByte((value >> 10) & 0xFF)
        ..addByte((value >> 2) & 0xFF);
    }
    return out.takeBytes();
  }

  /// `android.util.Base64.Decoder.process`：字母表以外的字元略過（`\/`、空白、
  /// 換行），`=` 只能補在結尾，剩 1 個字元、`=` 後面還有字、`=` 不夠補等
  /// Android 丟 `IllegalArgumentException("bad base-64")` 的情形丟
  /// [FormatException]。
  static Uint8List decodeAndroid(String str, {bool urlSafe = false}) {
    final table = urlSafe ? _urlSafeTable : _standardTable;
    final out = BytesBuilder(copy: false);
    var state = 0;
    var value = 0;
    Never bad() => throw const FormatException('bad base-64');
    for (final unit in utf8.encode(str)) {
      final d = table[unit];
      if (d == _skip) continue;
      switch (state) {
        case 0:
          if (d < 0) bad();
          value = d;
          state = 1;
        case 1:
          if (d < 0) bad();
          value = (value << 6) | d;
          state = 2;
        case 2:
          if (d >= 0) {
            value = (value << 6) | d;
            state = 3;
          } else {
            out.addByte((value >> 4) & 0xFF);
            state = 4;
          }
        case 3:
          if (d >= 0) {
            value = (value << 6) | d;
            out
              ..addByte((value >> 16) & 0xFF)
              ..addByte((value >> 8) & 0xFF)
              ..addByte(value & 0xFF);
            state = 0;
          } else {
            out
              ..addByte((value >> 10) & 0xFF)
              ..addByte((value >> 2) & 0xFF);
            state = 5;
          }
        case 4:
          if (d != _equals) bad();
          state = 5;
        default:
          bad();
      }
    }
    switch (state) {
      case 1 || 4:
        bad();
      case 2:
        out.addByte((value >> 4) & 0xFF);
      case 3:
        out
          ..addByte((value >> 10) & 0xFF)
          ..addByte((value >> 2) & 0xFF);
    }
    return out.takeBytes();
  }

  static Uint8List hexDecodeToByteArray(String hexStr) =>
      Uint8List.fromList(hex.decode(hexStr));
  static String hexEncodeToString(String str) => hex.encode(utf8.encode(str));
}

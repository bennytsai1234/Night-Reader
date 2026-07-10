import 'dart:convert';
import 'dart:typed_data';
import 'app_log_service.dart';

import 'package:fast_gbk/fast_gbk.dart';

/// EncodingDetect - 簡易編碼偵測工具
/// 針對中文書源優化，支援 UTF-8、UTF-16LE／BE 與 GBK 識別。
class EncodingDetect {
  /// 執行安全解碼，避免崩潰 (原 Android EncodingDetect.getEncode)
  static String decode(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    return decodeWithCharset(bytes, getEncode(bytes));
  }

  /// 使用已知編碼解碼完整檔案或不含 BOM 的章節切片。
  static String decodeWithCharset(List<int> bytes, String charset) {
    if (bytes.isEmpty) return '';
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final normalized = charset.toUpperCase().replaceAll('_', '-');

    try {
      if (normalized == 'UTF-16LE' || normalized == 'UTF16LE') {
        return _decodeUtf16(data, Endian.little);
      }
      if (normalized == 'UTF-16BE' || normalized == 'UTF16BE') {
        return _decodeUtf16(data, Endian.big);
      }
      if (normalized == 'GBK' ||
          normalized == 'GB2312' ||
          normalized == 'GB18030') {
        try {
          return gbk.decode(data);
        } catch (_) {
          return utf8.decode(data, allowMalformed: true);
        }
      }
      final offset = _hasUtf8Bom(data) ? 3 : 0;
      return utf8.decode(data.sublist(offset), allowMalformed: true);
    } catch (_) {
      return utf8.decode(data, allowMalformed: true);
    }
  }

  /// 將字串編成指定格式，不附加 BOM；用於把字元索引映射回檔案位元組位置。
  static Uint8List encodeWithCharset(String text, String charset) {
    final normalized = charset.toUpperCase().replaceAll('_', '-');
    if (normalized == 'UTF-16LE' || normalized == 'UTF16LE') {
      return _encodeUtf16(text, Endian.little);
    }
    if (normalized == 'UTF-16BE' || normalized == 'UTF16BE') {
      return _encodeUtf16(text, Endian.big);
    }
    if (normalized == 'GBK' ||
        normalized == 'GB2312' ||
        normalized == 'GB18030') {
      return Uint8List.fromList(gbk.encode(text));
    }
    return Uint8List.fromList(utf8.encode(text));
  }

  static int bomLength(Uint8List bytes) {
    if (_hasUtf8Bom(bytes)) return 3;
    if (_hasUtf16LeBom(bytes) || _hasUtf16BeBom(bytes)) return 2;
    return 0;
  }

  /// 針對 HTML 內容偵測編碼
  static String getHtmlEncode(Uint8List bytes) {
    try {
      final content = utf8.decode(
        bytes.sublist(0, bytes.length > 8000 ? 8000 : bytes.length),
        allowMalformed: true,
      );

      // 1. 尋找 <meta charset="...">
      final charsetMatch = RegExp(
        r'<meta\s+charset=["'
        "'"
        r']?([a-zA-Z0-9_-]+)["'
        "'"
        r']?',
        caseSensitive: false,
      ).firstMatch(content);
      if (charsetMatch != null) {
        return charsetMatch.group(1) ?? 'UTF-8';
      }

      // 2. 尋找 <meta http-equiv="Content-Type" content="...charset=...">
      final contentTypeMatch = RegExp(
        r'content=["'
        "'"
        r']?text/html;\s*charset=([a-zA-Z0-9_-]+)["'
        "'"
        r']?',
        caseSensitive: false,
      ).firstMatch(content);
      if (contentTypeMatch != null) {
        return contentTypeMatch.group(1) ?? 'UTF-8';
      }
    } catch (e, s) {
      AppLog.put('Unexpected Error', error: e, stackTrace: s);
    }

    return getEncode(bytes);
  }

  /// 偵測位元組陣列的編碼
  static String getEncode(Uint8List bytes) {
    if (bytes.isEmpty) return 'UTF-8';

    // 1. 檢查 UTF-8 BOM (EF BB BF)
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return 'UTF-8';
    }

    // 2. 檢查 UTF-16 BE BOM (FE FF)
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return 'UTF-16BE';
    }

    // 3. 檢查 UTF-16 LE BOM (FF FE)
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return 'UTF-16LE';
    }

    // 4. 嘗試 UTF-8 解碼 (最快路徑)
    try {
      utf8.decode(bytes);
      return 'UTF-8';
    } catch (_) {
      // 5. 若 UTF-8 失敗，嘗試 GBK 偵測
      // GBK 第一字節範圍 0x81-0xFE, 第二字節 0x40-0x7E 或 0x80-0xFE
      bool isGbk = false;
      for (int i = 0; i < bytes.length - 1; i++) {
        if (bytes[i] >= 0x81 && bytes[i] <= 0xFE) {
          if ((bytes[i + 1] >= 0x40 && bytes[i + 1] <= 0x7E) ||
              (bytes[i + 1] >= 0x80 && bytes[i + 1] <= 0xFE)) {
            isGbk = true;
            break;
          }
        }
      }
      return isGbk ? 'GBK' : 'UTF-8'; // 預設回退至 UTF-8 (含 malformed 處理)
    }
  }

  static String _decodeUtf16(Uint8List bytes, Endian endian) {
    var offset = 0;
    if ((endian == Endian.little && _hasUtf16LeBom(bytes)) ||
        (endian == Endian.big && _hasUtf16BeBom(bytes))) {
      offset = 2;
    }
    final codeUnits = <int>[];
    while (offset + 1 < bytes.length) {
      final first = bytes[offset];
      final second = bytes[offset + 1];
      codeUnits.add(
        endian == Endian.little ? first | (second << 8) : (first << 8) | second,
      );
      offset += 2;
    }
    if (offset < bytes.length) codeUnits.add(0xFFFD);
    return String.fromCharCodes(codeUnits);
  }

  static Uint8List _encodeUtf16(String text, Endian endian) {
    final result = Uint8List(text.codeUnits.length * 2);
    var offset = 0;
    for (final codeUnit in text.codeUnits) {
      if (endian == Endian.little) {
        result[offset] = codeUnit & 0xFF;
        result[offset + 1] = codeUnit >> 8;
      } else {
        result[offset] = codeUnit >> 8;
        result[offset + 1] = codeUnit & 0xFF;
      }
      offset += 2;
    }
    return result;
  }

  static bool _hasUtf8Bom(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;

  static bool _hasUtf16LeBom(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE;

  static bool _hasUtf16BeBom(Uint8List bytes) =>
      bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF;
}

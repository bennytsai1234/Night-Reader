import 'dart:convert';
import 'dart:typed_data';
import 'app_log_service.dart';

import 'package:fast_gbk/fast_gbk.dart';

/// EncodingDetect - 簡易編碼偵測工具
/// 針對中文書源優化，支援 UTF-8 (含 BOM) 與 GBK 識別
class EncodingDetect {
  static Encoding detect(Uint8List bytes) {
    final name = getEncode(bytes).toUpperCase();
    if (name == 'GBK' || name == 'GB2312' || name == 'GB18030') {
      return gbk;
    }
    return utf8;
  }

  /// 執行安全解碼，避免崩潰 (原 Android EncodingDetect.getEncode)
  static String decode(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    final charset = getEncode(bytes).toUpperCase();

    try {
      if (charset == 'UTF-8') {
        return utf8.decode(bytes, allowMalformed: true);
      } else if (charset == 'GBK' ||
          charset == 'GB2312' ||
          charset == 'GB18030') {
        try {
          return gbk.decode(bytes);
        } catch (_) {
          return utf8.decode(bytes, allowMalformed: true);
        }
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      return utf8.decode(bytes, allowMalformed: true);
    }
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
}

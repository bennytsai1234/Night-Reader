import 'dart:convert';
import 'package:crypto/crypto.dart';

/// EncoderUtils - 編碼工具 (原 Android utils/EncoderUtils.kt & MD5Utils.kt)
class EncoderUtils {
  EncoderUtils._();

  /// escape 處理
  static String escape(String src) {
    final tmp = StringBuffer();
    for (var i = 0; i < src.length; i++) {
      final charCode = src.codeUnitAt(i);
      if ((charCode >= 48 && charCode <= 57) ||
          (charCode >= 65 && charCode <= 90) ||
          (charCode >= 97 && charCode <= 122)) {
        tmp.write(src[i]);
        continue;
      }

      String prefix;
      if (charCode < 16) {
        prefix = '%0';
      } else if (charCode < 256) {
        prefix = '%';
      } else {
        prefix = '%u';
      }
      tmp.write(prefix);
      tmp.write(charCode.toRadixString(16));
    }
    return tmp.toString();
  }

  /// Base64 編碼
  static String base64Encode(dynamic data) {
    if (data is String) {
      return base64.encode(utf8.encode(data));
    } else if (data is List<int>) {
      return base64.encode(data);
    }
    return '';
  }

  /// Base64 解碼
  static String base64Decode(String str) {
    return utf8.decode(base64.decode(str));
  }

  /// Base64 解碼為位元組
  static List<int> base64DecodeToBytes(String str) {
    return base64.decode(str);
  }

  /// MD5 編碼 (32位元)
  static String md5Encode(String str) {
    return md5.convert(utf8.encode(str)).toString();
  }

  /// MD5 編碼 (16位元)
  static String md5Encode16(String str) {
    final full = md5Encode(str);
    return full.substring(8, 24);
  }
}

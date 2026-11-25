import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

import 'encoding_detect.dart';
import 'gb18030_ranges.dart';

/// GB18030：雙位元組和 GBK 一樣，GBK 沒有的字（emoji、少見漢字、一些符號）
/// 寫成四位元組，照 WHATWG Encoding Standard 的 gb18030 對照（序號與碼位的
/// 對照表在 [gb18030RangePointers]）；WHATWG 把 `81 35 F4 37` 另外對到私用區
/// 的特例不照做，同 Java 與 Python（「ḿ」解得回來）。網站明寫 GB18030 時照它解，搜尋送出的字
/// 也照它編（同 Legado 用 Java 的 GB18030）。
abstract final class Gb18030 {
  /// 解：四位元組的照對照表，其他照 GBK（[EncodingDetect.decodeGbk]，壞掉的
  /// 位元組換成替代字元）。
  static String decode(List<int> bytes) {
    final out = StringBuffer();
    var start = 0;
    var i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b < 0x81 || b > 0xFE || i + 1 >= bytes.length) {
        i++;
        continue;
      }
      if (!_isDigit(bytes[i + 1])) {
        i += 2;
        continue;
      }
      if (!isFourByteAt(bytes, i)) {
        i++;
        continue;
      }
      if (start < i) {
        out.write(EncodingDetect.decodeGbk(bytes.sublist(start, i)));
      }
      final pointer =
          (b - 0x81) * 12600 +
          (bytes[i + 1] - 0x30) * 1260 +
          (bytes[i + 2] - 0x81) * 10 +
          (bytes[i + 3] - 0x30);
      out.writeCharCode(_codePointOf(pointer));
      i += 4;
      start = i;
    }
    if (start == 0) return EncodingDetect.decodeGbk(bytes);
    if (start < bytes.length) {
      out.write(EncodingDetect.decodeGbk(bytes.sublist(start)));
    }
    return out.toString();
  }

  /// 編：ASCII 一個位元組，GBK 有的字兩個位元組，其他四個位元組。
  static Uint8List encode(String text) {
    final out = BytesBuilder(copy: false);
    for (final rune in text.runes) {
      if (rune < 0x80) {
        out.addByte(rune);
        continue;
      }
      // 落單的代理碼位（半個 emoji），同 Java 編成 `?`。
      if (rune >= 0xD800 && rune <= 0xDFFF) {
        out.addByte(0x3F);
        continue;
      }
      final two = _gbkBytes(rune);
      if (two != null) {
        out.add(two);
        continue;
      }
      var pointer = _pointerOf(rune);
      final b1 = pointer ~/ 12600 + 0x81;
      pointer %= 12600;
      final b2 = pointer ~/ 1260 + 0x30;
      pointer %= 1260;
      out.add([b1, b2, pointer ~/ 10 + 0x81, pointer % 10 + 0x30]);
    }
    return out.takeBytes();
  }

  /// [index] 開始是一個四位元組的字：0x81–0xFE、0x30–0x39、0x81–0xFE、
  /// 0x30–0x39。
  static bool isFourByteAt(List<int> bytes, int index) =>
      index + 3 < bytes.length &&
      bytes[index] >= 0x81 &&
      bytes[index] <= 0xFE &&
      _isDigit(bytes[index + 1]) &&
      bytes[index + 2] >= 0x81 &&
      bytes[index + 2] <= 0xFE &&
      _isDigit(bytes[index + 3]);

  static bool _isDigit(int b) => b >= 0x30 && b <= 0x39;

  /// GBK 編得出、解得回同一個字時的兩個位元組（fast_gbk 遇到沒有的字會編出
  /// 別的位元組，不丟錯）。
  static List<int>? _gbkBytes(int rune) {
    final char = String.fromCharCode(rune);
    try {
      final bytes = gbk.encode(char);
      return bytes.length == 2 && gbk.decode(bytes) == char ? bytes : null;
    } on Object {
      return null;
    }
  }

  static int _codePointOf(int pointer) {
    if ((pointer > 39419 && pointer < 189000) || pointer > 1237575) {
      return 0xFFFD;
    }
    if (pointer >= 189000) return 0x10000 + pointer - 189000;
    final index = _lastAtMost(gb18030RangePointers, pointer);
    return gb18030RangeCodePoints[index] +
        pointer -
        gb18030RangePointers[index];
  }

  static int _pointerOf(int rune) {
    if (rune >= 0x10000) return 189000 + rune - 0x10000;
    final index = _lastAtMost(gb18030RangeCodePoints, rune);
    return gb18030RangePointers[index] + rune - gb18030RangeCodePoints[index];
  }

  /// [sorted] 裡最後一個不大於 [value] 的位置。
  static int _lastAtMost(List<int> sorted, int value) {
    var low = 0;
    var high = sorted.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (sorted[mid] <= value) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}

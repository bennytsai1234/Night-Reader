import 'dart:typed_data';

import 'big5_table.dart';

/// Big5（cp950）的編碼與解碼，同 Java 的 `String(bytes, "Big5")`、
/// `getBytes("Big5")`：解不出的位元組換成一個替代字元，後面照常解；編不出的
/// 字寫成 `?`。台灣、香港的舊網站常用它（Legado 用 Java 的字元集，照收）。
abstract final class Big5 {
  /// Java 認得的 Big5 名稱（大寫、底線換成連字號）：Big5、cp950 與
  /// Big5-HKSCS 都照 cp950 的表。
  static const Set<String> names = {
    'BIG5',
    'BIG-5',
    'CSBIG5',
    'CP950',
    'MS950',
    'WINDOWS-950',
    'X-WINDOWS-950',
    'BIG5-HKSCS',
    'BIG5HKSCS',
    'BIG5HK',
  };

  /// 第二個位元組在一列裡的位置；不是合法的第二個位元組時是 -1。
  static int _trailIndex(int b) {
    if (b >= 0x40 && b <= 0x7E) return b - 0x40;
    if (b >= 0xA1 && b <= 0xFE) return b - 0xA1 + 63;
    return -1;
  }

  /// [decode] 在第 [i] 個位元組解出的那一個字佔幾個位元組（1 或 2）；表裡
  /// 沒有的格解成替代字元，也佔 2 個。本地 TXT 照它算章節的位元組位置。
  static int byteLengthAt(List<int> bytes, int i) {
    final b = bytes[i];
    if (b < 0x81 || b > 0xFE) return 1;
    final trail = i + 1 < bytes.length ? _trailIndex(bytes[i + 1]) : -1;
    return trail < 0 ? 1 : 2;
  }

  static String decode(List<int> bytes) {
    final out = StringBuffer();
    var i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b < 0x80) {
        out.writeCharCode(b);
        i++;
        continue;
      }
      final trail = i + 1 < bytes.length ? _trailIndex(bytes[i + 1]) : -1;
      if (b < 0x81 || b > 0xFE || trail < 0) {
        // 孤立的開頭位元組只換掉它自己，後面的字（常是 `<`）照常解。
        out.writeCharCode(0xFFFD);
        i++;
        continue;
      }
      out.writeCharCode(big5Rows[b - 0x81].codeUnitAt(trail));
      i += 2;
    }
    return out.toString();
  }

  static Map<int, int>? _reverse;

  static Map<int, int> get _encodeTable => _reverse ??= () {
    final map = <int, int>{};
    for (var row = 0; row < big5Rows.length; row++) {
      final chars = big5Rows[row];
      for (var t = 0; t < chars.length; t++) {
        final unit = chars.codeUnitAt(t);
        if (unit == 0xFFFD) continue;
        final trail = t < 63 ? 0x40 + t : 0xA1 + t - 63;
        map.putIfAbsent(unit, () => ((row + 0x81) << 8) | trail);
      }
    }
    // 同一個字有兩個位置時，Java 不一定取前面的（「十」是 A451，不是數字
    // 符號區的 A2CC）。
    return map..addAll(big5EncodeOverrides);
  }();

  static Uint8List encode(String text) {
    final out = BytesBuilder(copy: false);
    for (final rune in text.runes) {
      if (rune < 0x80) {
        out.addByte(rune);
        continue;
      }
      final code = _encodeTable[rune];
      if (code == null) {
        out.addByte(0x3F);
      } else {
        out
          ..addByte(code >> 8)
          ..addByte(code & 0xFF);
      }
    }
    return out.toBytes();
  }
}

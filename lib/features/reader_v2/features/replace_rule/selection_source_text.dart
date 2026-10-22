/// 在章節原文 [source] 裡找出畫面上那段字 [shown] 對應的原文。
///
/// 替換規則套在原文上，畫面上的字卻經過排版整理（標點換成全形、刪掉中文
/// 之間的空白、`...` 變 `……`）與繁簡轉換，直接拿來當規則常常對不到。這裡
/// 把兩邊都化成同一種比對用的字：略過空白，英數字不分全半形與大小寫，
/// 中文字一律轉成簡體（[toSimplified]，沒給就不轉），標點只認位置不認是哪
/// 個符號，連續的刪節號或破折號算一個；找到後回傳原文裡那一段。找不到，
/// 或 [shown] 只有空白時回傳 null。
String? findSourceText({
  required String source,
  required String shown,
  String Function(String char)? toSimplified,
}) {
  final shownKey = _ComparisonText.of(shown, toSimplified);
  if (shownKey.key.isEmpty) return null;
  final sourceKey = _ComparisonText.of(source, toSimplified);
  final index = sourceKey.key.indexOf(shownKey.key);
  if (index < 0) return null;
  final last = index + shownKey.key.length - 1;
  return source.substring(sourceKey.starts[index], sourceKey.ends[last]);
}

/// 比對用的字，每個字記得它在原字串裡的範圍。
final class _ComparisonText {
  _ComparisonText._(this.key, this.starts, this.ends);

  factory _ComparisonText.of(
    String text,
    String Function(String char)? toSimplified,
  ) {
    final key = StringBuffer();
    final starts = <int>[];
    final ends = <int>[];
    var offset = 0;
    String? previous;
    for (final rune in text.runes) {
      final start = offset;
      offset += rune > 0xFFFF ? 2 : 1;
      final char = _fold(rune, toSimplified);
      if (char == null) continue;
      // 刪節號、破折號排版時會改長度，緊接著的同一種算一個。
      final isRun = char == _ellipsis || char == _dash;
      if (isRun && char == previous && ends.last == start) {
        ends[ends.length - 1] = offset;
        continue;
      }
      previous = char;
      key.write(char);
      // 罕用字是兩個 UTF-16 單位，每個單位都記同一個原文範圍。
      for (var unit = 0; unit < char.length; unit += 1) {
        starts.add(start);
        ends.add(offset);
      }
    }
    return _ComparisonText._(key.toString(), starts, ends);
  }

  final String key;
  final List<int> starts;
  final List<int> ends;

  static const String _ellipsis = '…';
  static const String _dash = '—';
  static const String _punctuation = '·';

  /// 一個字比對時的樣子；空白與控制字元回傳 null（略過）。
  static String? _fold(int rune, String Function(String char)? toSimplified) {
    if (_isIgnorable(rune)) return null;
    // 全形英數字與標點（U+FF01–FF5E）換成半形。
    final halfWidth = rune >= 0xFF01 && rune <= 0xFF5E ? rune - 0xFEE0 : rune;
    final char = String.fromCharCode(halfWidth);
    if (_ellipsisRunes.contains(halfWidth)) return _ellipsis;
    if (_dashRunes.contains(halfWidth)) return _dash;
    if (_letterOrDigit.hasMatch(char)) {
      if (toSimplified != null && _han.hasMatch(char)) {
        return toSimplified(char);
      }
      return char.toLowerCase();
    }
    return _punctuation;
  }

  static bool _isIgnorable(int rune) =>
      rune <= 0x20 ||
      (rune >= 0x7F && rune <= 0xA0) ||
      rune == 0x3000 ||
      rune == 0x200B ||
      rune == 0xFEFF;

  /// 句點也算：排版把 `...` 變成 `……`、把中文旁的 `.` 變成 `。`。
  static const Set<int> _ellipsisRunes = <int>{
    0x2E, // .
    0x3002, // 。
    0x2026, // …
    0x22EF, // ⋯
  };

  static const Set<int> _dashRunes = <int>{
    0x2D, // -
    0x2013, // –
    0x2014, // —
    0x2015, // ―
    0x2500, // ─
  };

  static final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final RegExp _han = RegExp(r'\p{Script=Han}', unicode: true);
}

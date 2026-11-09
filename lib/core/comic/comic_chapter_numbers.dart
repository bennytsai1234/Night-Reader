/// 從章名認出第幾話，換章分隔用它提醒中間缺了幾話（照 Mihon 的
/// `calculateChapterGap`；Mihon 的章號由書源或章名辨識給）。
abstract final class ComicChapterNumbers {
  static final RegExp _marked = RegExp(
    r'第\s*([0-9０-９]+(?:\.[0-9]+)?|[零〇一二兩两三四五六七八九十百千]+)\s*[話话章回集]',
  );
  static final RegExp _chapterWord = RegExp(
    r'\b(?:ch(?:apter)?|ep(?:isode)?)\.?\s*([0-9]+(?:\.[0-9]+)?)',
    caseSensitive: false,
  );
  static final RegExp _leading = RegExp(r'^\s*([0-9]+(?:\.[0-9]+)?)(?![0-9])');

  /// [title] 是第幾話；認不出來是 null。「第12話」「第十二话」「Ch.12」
  /// 「12 標題」都認得；「第3卷」這種只有卷號的不算。
  static double? of(String title) {
    final marked = _marked.firstMatch(title)?.group(1);
    if (marked != null) return _parse(marked);
    final word = _chapterWord.firstMatch(title)?.group(1);
    if (word != null) return double.tryParse(word);
    final leading = _leading.firstMatch(title)?.group(1);
    if (leading != null) return double.tryParse(leading);
    return null;
  }

  /// 從 [from] 接到 [to] 中間缺了幾話；認不出章號或沒有缺是 0。
  /// 同 Mihon：只看整數部分，`12.5` 接 `13` 不算缺。
  static int gapBetween(String from, String to) {
    final a = of(from);
    final b = of(to);
    if (a == null || b == null) return 0;
    final gap = b.floor() - a.floor() - 1;
    return gap > 0 ? gap : 0;
  }

  static double? _parse(String text) {
    final ascii = String.fromCharCodes(
      text.runes.map((r) => r >= 0xFF10 && r <= 0xFF19 ? r - 0xFF10 + 0x30 : r),
    );
    return double.tryParse(ascii) ?? _chinese(ascii)?.toDouble();
  }

  static const Map<String, int> _digits = {
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '兩': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  static const Map<String, int> _units = {'十': 10, '百': 100, '千': 1000};

  /// 一千以內的中文數字（「十二」「一百零五」「二十」）。
  static int? _chinese(String text) {
    var total = 0;
    var digit = 0;
    var seenAny = false;
    for (final char in text.split('')) {
      if (_digits[char] case final value?) {
        digit = value;
        seenAny = true;
      } else if (_units[char] case final unit?) {
        // 「十二」的十前面沒有數字，算一十。
        total += (digit == 0 ? 1 : digit) * unit;
        digit = 0;
        seenAny = true;
      } else {
        return null;
      }
    }
    return seenAny ? total + digit : null;
  }
}

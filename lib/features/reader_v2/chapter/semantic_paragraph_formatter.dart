/// 把書源存錯的換行接回去（ADR 0070）。
///
/// 網路書、TXT 與 EPUB 的正文裡，一個換行通常就是一段。這裡只接有明確
/// 排版證據的換行：收尾標點被折到下一行開頭、開頭標點留在上一行結尾、
/// 成對的「……」「——」被折開，以及高度一致的固定欄寬硬折行。空白行與
/// 只有插圖的行一律是段落邊界。
///
/// 在排版整理（`normalizeTypography`）之前跑，落單的彎引號接回句子後才
/// 轉得對方向。只刪接縫的換行與兩側空白，不補標點、不改字。
abstract final class SemanticParagraphFormatter {
  /// 不會出現在段首的標點（不含引號，引號另外判斷）。
  static const String _noParagraphStart = '，。、；：！？）】》〉〕｝';
  static const String _noParagraphEnd = '（【《〈〔｛';
  static const String _closingQuotes = '」』”’';
  static const String _openingQuotes = '「『“‘';
  static const String _curlyQuotes = '“”‘’';
  static const String _sentenceFinal = '。！？!?…';
  static const String _paragraphFinal = '。！？!?」』”’';

  /// 整行只有這些時是獨立的一段（例如「？？？」「！！」），不接到上一行。
  static const String _standalonePunctuation = '，。、；：！？!?…～~';

  static String repair(String content) {
    if (content.isEmpty) return content;
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    if (lines.length < 2) return lines.single;

    final wrapColumns = _fixedWidthColumns(lines);
    final output = <String>[];
    String? pending;
    var previous = '';

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_visible(line).isEmpty) {
        if (pending != null) output.add(pending);
        pending = null;
        // 空白行與只有插圖的行是確定的邊界，下一行以收尾標點開頭也不跨過。
        output.add(line.trim().isEmpty ? '' : line);
        continue;
      }
      if (pending != null &&
          _shouldJoin(pending, previous, line, wrapColumns[i])) {
        pending = pending.trimRight() + line.trimLeft();
      } else {
        if (pending != null) output.add(pending);
        pending = line;
      }
      previous = line;
    }
    if (pending != null) output.add(pending);
    return output.join('\n');
  }

  /// [paragraph] 是到上一行為止接好的段落，[before] 是上一行本身。
  static bool _shouldJoin(
    String paragraph,
    String before,
    String after,
    int? wrapColumn,
  ) {
    final left = _visible(before);
    final right = _visible(after);
    final first = right[0];
    final last = left[left.length - 1];

    // 書源常把 “ ” 的方向打反（“看！”寫成“看！“），只看方向會把下一段
    // 併進來。引號一律要這一段還有沒收的引號才接；彎引號緊跟在句末標點
    // 之後是收引號（一句話跨好幾行說完時，開引號在更前面的行），不是留在
    // 行尾的開引號。
    if (_openingQuotes.contains(last) &&
        _curlyQuotes.contains(last) &&
        left.length > 1 &&
        _sentenceFinal.contains(left[left.length - 2])) {
      return false;
    }
    if (_closingQuotes.contains(first) || _openingQuotes.contains(last)) {
      return _hasUnclosedQuote(paragraph);
    }
    if (_noParagraphStart.contains(first)) {
      return !_isStandalonePunctuation(right);
    }
    if (_noParagraphEnd.contains(last)) return true;
    if (_splitsPair(left, right, '…') || _splitsPair(left, right, '—')) {
      return true;
    }

    // 欄寬一致是硬折行的證據；句子已結束或下一行是新的對白時仍分段。
    return wrapColumn != null &&
        (left.runes.length - wrapColumn).abs() <= 1 &&
        !_paragraphFinal.contains(last) &&
        !_openingQuotes.contains(first);
  }

  /// [text] 裡有沒收的引號：「『 多於 」』，或彎雙引號、彎單引號是奇數個
  /// （方向不可靠，只數個數）。
  static bool _hasUnclosedQuote(String text) {
    var corner = 0;
    var whiteCorner = 0;
    var double = 0;
    var single = 0;
    for (final unit in text.codeUnits) {
      switch (unit) {
        case 0x300C: // 「
          corner++;
        case 0x300D: // 」
          corner--;
        case 0x300E: // 『
          whiteCorner++;
        case 0x300F: // 』
          whiteCorner--;
        case 0x201C || 0x201D: // “ ”
          double++;
        case 0x2018 || 0x2019: // ‘ ’
          single++;
      }
    }
    return corner > 0 || whiteCorner > 0 || double.isOdd || single.isOdd;
  }

  static bool _isStandalonePunctuation(String text) =>
      text.split('').every(_standalonePunctuation.contains);

  /// 「……」「——」這種兩個字一組的符號被折成兩半：上一行結尾與下一行開頭
  /// 各有奇數個 [mark]。各自完整的一組（上一段以「……」收、下一段以「……」
  /// 起）不算。
  static bool _splitsPair(String left, String right, String mark) {
    var trailing = 0;
    while (trailing < left.length && left[left.length - 1 - trailing] == mark) {
      trailing++;
    }
    var leading = 0;
    while (leading < right.length && right[leading] == mark) {
      leading++;
    }
    return trailing.isOdd && leading.isOdd;
  }

  /// 去掉頭尾空白與插圖記號（私用區 U+E000–U+F8FF）後的字：記號是插圖的
  /// 位置，不是標點，判斷首尾標點與行長時跳過它，但接起來時照樣留著。
  static String _visible(String line) {
    final trimmed = line.trim();
    if (!trimmed.codeUnits.any(_isPlaceholder)) return trimmed;
    return String.fromCharCodes(
      trimmed.codeUnits.where((unit) => !_isPlaceholder(unit)),
    ).trim();
  }

  static bool _isPlaceholder(int unit) => unit >= 0xE000 && unit <= 0xF8FF;

  /// 只在沒有空白行的連續區間裡找固定欄寬：至少五行，其中至少四行、
  /// 也至少四分之三的行，字數落在同一個 14–120 字的欄寬正負一字內。
  /// 單獨一段長段落或長短不一的小說段落不算。
  static List<int?> _fixedWidthColumns(List<String> lines) {
    final result = List<int?>.filled(lines.length, null);
    final lengths = [for (final line in lines) _visible(line).runes.length];
    var start = 0;
    while (start < lines.length) {
      if (lengths[start] == 0) {
        start++;
        continue;
      }
      var end = start;
      final frequencies = <int, int>{};
      while (end < lines.length && lengths[end] != 0) {
        final length = lengths[end];
        if (length >= 14 && length <= 120) {
          frequencies[length] = (frequencies[length] ?? 0) + 1;
        }
        end++;
      }
      if (end - start >= 5) {
        int? column;
        var bestCount = 0;
        for (final candidate in frequencies.keys) {
          final matches =
              (frequencies[candidate - 1] ?? 0) +
              (frequencies[candidate] ?? 0) +
              (frequencies[candidate + 1] ?? 0);
          if (matches > bestCount) {
            bestCount = matches;
            column = candidate;
          }
        }
        if (column != null &&
            bestCount >= 4 &&
            bestCount * 4 >= (end - start) * 3) {
          for (var i = start; i < end; i++) {
            result[i] = column;
          }
        }
      }
      start = end;
    }
    return result;
  }
}

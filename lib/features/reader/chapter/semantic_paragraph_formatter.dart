/// 把書源存錯的換行接回去（ADR 0073）。
///
/// 網路書、TXT 與 EPUB 的正文裡，一個換行通常就是一段。這裡只接有明確
/// 排版證據的換行：收尾標點被折到下一行開頭、開頭標點或逗號、頓號、分號
/// 留在上一行結尾、成對的「……」「——」被折開，以及高度一致的固定欄寬
/// 硬折行。空白行與只有插圖的行一律是段落邊界。
///
/// 在排版整理（`normalizeTypography`）之前跑，落單的彎引號接回句子後才
/// 轉得對方向。只刪接縫的換行與兩側空白，不補標點、不改字。
abstract final class SemanticParagraphFormatter {
  /// 不會出現在段首的標點（不含引號，引號另外判斷）。
  static const String _noParagraphStart = '，。、；：！？）】》〉〕｝';
  static const String _noParagraphEnd = '（【《〈〔｛';

  /// 句中停頓的標點：上一行停在這裡時句子還沒完。
  static const String _midSentencePause = '，、；,;';

  /// 單層引號；其餘的「」“” 是雙層，兩層各自配對。
  static const String _singleQuotes = '『』‘’';
  static const String _closingQuotes = '」』”’';
  static const String _openingQuotes = '「『“‘';
  static const String _curlyQuotes = '“”‘’';
  static const String _sentenceFinal = '。！？!?…';
  static const String _paragraphFinal = '。！？!?.」』”’';

  /// 整行只有這些時是獨立的一段（例如「？？？」「！！」），不接到上一行。
  static const String _standalonePunctuation = '，。、；：！？!?…～~';

  static String repair(String content) =>
      _repair(content).map((group) => group.repaired).join('\n');

  /// 修復後的每一行（[lines]，和 [repair] 的結果一行一行對應）與組成它的
  /// 原文（[sources]：被接起來的幾行照原樣以換行相連）。替換規則在修復之前
  /// 套用，要建規則比對被接起來的字時用 [sources]。
  static ({List<String> lines, List<String> sources}) repairWithSources(
    String content,
  ) {
    final groups = _repair(content);
    return (
      lines: [for (final group in groups) group.repaired],
      sources: [for (final group in groups) group.source],
    );
  }

  static List<({String repaired, String source})> _repair(String content) {
    if (content.isEmpty) return const [(repaired: '', source: '')];
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final wrapColumns = _fixedWidthColumns(lines);
    final output = <({String repaired, String source})>[];
    String? pending;
    String? pendingSource;
    var previous = '';

    void flush() {
      if (pending != null) {
        output.add((repaired: pending!, source: pendingSource!));
      }
      pending = null;
      pendingSource = null;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_visible(line).isEmpty) {
        flush();
        // 空白行與只有插圖的行是確定的邊界，下一行以收尾標點開頭也不跨過。
        final kept = line.trim().isEmpty ? '' : line;
        output.add((repaired: kept, source: line));
        continue;
      }
      if (pending != null &&
          _shouldJoin(pending!, previous, line, wrapColumns[i])) {
        pending = pending!.trimRight() + line.trimLeft();
        pendingSource = '$pendingSource\n$line';
      } else {
        flush();
        pending = line;
        pendingSource = line;
      }
      previous = line;
    }
    flush();
    return output;
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
    // 併進來。引號一律要這一段還有同一層沒收的引號才接；彎引號緊跟在句末
    // 標點之後是收引號（一句話跨好幾行說完時，開引號在更前面的行），不是
    // 留在行尾的開引號。
    if (_openingQuotes.contains(last) &&
        _curlyQuotes.contains(last) &&
        left.length > 1 &&
        _sentenceFinal.contains(left[left.length - 2])) {
      return false;
    }
    if (_closingQuotes.contains(first)) {
      return _hasUnclosedQuote(
        paragraph,
        single: _singleQuotes.contains(first),
      );
    }
    if (_openingQuotes.contains(last)) {
      return _hasUnclosedQuote(paragraph, single: _singleQuotes.contains(last));
    }
    if (_noParagraphStart.contains(first)) {
      return !_isStandalonePunctuation(right);
    }
    if (_noParagraphEnd.contains(last)) return true;
    // 一段話不會停在逗號、頓號、分號上。半形的後面接英數字時不接，接起來
    // 會黏掉字詞間的空格。
    if (_midSentencePause.contains(last)) {
      final halfWidth = last == ',' || last == ';';
      return !(halfWidth && _isLatinLetterOrDigit(first.codeUnitAt(0)));
    }
    if (_splitsPair(left, right, '…') || _splitsPair(left, right, '—')) {
      return true;
    }

    // 欄寬一致是硬折行的證據；句子已結束、下一行是新的對白，或接縫兩邊
    // 都是英數字（接起來會黏掉字詞間的空格）時仍分段。
    return wrapColumn != null &&
        (left.runes.length - wrapColumn).abs() <= 1 &&
        !_paragraphFinal.contains(last) &&
        !_openingQuotes.contains(first) &&
        !(_isLatinLetterOrDigit(last.codeUnitAt(0)) &&
            _isLatinLetterOrDigit(first.codeUnitAt(0)));
  }

  /// [text] 裡有沒有沒收的雙層（[single] 時單層）引號：直角引號開的多於
  /// 收的，或彎引號是奇數個（方向不可靠，只數個數）。英文字中間的 `’` 是
  /// 撇號（don’t），不算。
  static bool _hasUnclosedQuote(String text, {required bool single}) {
    final (open, close, curlyOpen, curlyClose) = single
        ? (0x300E, 0x300F, 0x2018, 0x2019) // 『』‘’
        : (0x300C, 0x300D, 0x201C, 0x201D); // 「」“”
    var corner = 0;
    var curly = 0;
    final units = text.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final unit = units[i];
      if (unit == open) {
        corner++;
      } else if (unit == close) {
        corner--;
      } else if (unit == curlyOpen) {
        curly++;
      } else if (unit == curlyClose) {
        final apostrophe =
            single &&
            i > 0 &&
            i + 1 < units.length &&
            _isLatinLetterOrDigit(units[i - 1]) &&
            _isLatinLetterOrDigit(units[i + 1]);
        if (!apostrophe) curly++;
      }
    }
    return corner > 0 || curly.isOdd;
  }

  static bool _isLatinLetterOrDigit(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A);

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

  /// 只在沒有空白行的連續區間裡找固定欄寬：至少八行，其中至少六行、也
  /// 至少四分之三的行，字數落在同一個 14–120 字的欄寬正負一字內。單獨
  /// 一段長段落、長短不一的小說段落與幾項等長的列表不算。
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
        frequencies.update(lengths[end], (n) => n + 1, ifAbsent: () => 1);
        end++;
      }
      if (end - start >= 8) {
        int? column;
        var bestCount = 0;
        final candidates = {
          for (final length in frequencies.keys) ...[
            length - 1,
            length,
            length + 1,
          ],
        }.where((candidate) => candidate >= 14 && candidate <= 120);
        for (final candidate in candidates) {
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
            bestCount >= 6 &&
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

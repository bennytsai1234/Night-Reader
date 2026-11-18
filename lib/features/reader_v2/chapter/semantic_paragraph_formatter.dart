/// Repairs paragraph boundaries that were lost when a source wrapped its text.
///
/// A newline is normally a paragraph boundary in online novels, TXT, and
/// imported EPUB. Only unambiguous typography errors and high-confidence
/// fixed-width hard wrapping are joined. Blank lines always remain boundaries.
///
/// This runs before typography normalization so an orphan curly quote can
/// still be converted using its newly adjacent Chinese context. It only
/// deletes line breaks/indentation at joined boundaries; it never invents
/// punctuation or changes a word.
abstract final class SemanticParagraphFormatter {
  static const String _noParagraphStart = '，。、；：！？」』）】》〉〕｝”’';
  static const String _noParagraphEnd = '「『（【《〈〔｛“‘';
  static const String _paragraphFinal = '。！？!?」』”’';
  static const String _dialogueStart = '「『“‘';

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
    var previousIndex = -2;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        if (pending != null) output.add(pending);
        pending = null;
        // Keep this boundary even if the next line starts with a closing mark.
        output.add('');
        previousIndex = -2;
        continue;
      }
      if (pending != null &&
          previousIndex == i - 1 &&
          _shouldJoin(previous, line, wrapColumns[i])) {
        pending = pending.trimRight() + line.trimLeft();
      } else {
        if (pending != null) output.add(pending);
        pending = line;
      }
      previous = line;
      previousIndex = i;
    }
    if (pending != null) output.add(pending);
    return output.join('\n');
  }

  static bool _shouldJoin(String before, String after, int? wrapColumn) {
    final left = before.trimRight();
    final right = after.trimLeft();
    if (left.isEmpty || right.isEmpty) return false;

    // A closing mark must not start a new semantic paragraph. The inverse
    // applies to an opening mark stranded at the end of the previous line.
    final first = _visibleEdge(right, fromStart: true);
    final last = _visibleEdge(left, fromStart: false);
    if ((first.isNotEmpty && _noParagraphStart.contains(first)) ||
        (last.isNotEmpty && _noParagraphEnd.contains(last))) {
      return true;
    }
    if ((left.endsWith('…') && right.startsWith('…')) ||
        (left.endsWith('—') && right.startsWith('—'))) {
      return true;
    }

    // A uniform source column is evidence for visual hard wraps. Do not merge
    // dialogue boundaries, short lines, or natural sentence-final lines.
    if (wrapColumn == null ||
        (left.runes.length - wrapColumn).abs() > 1 ||
        _paragraphFinal.contains(last) ||
        _dialogueStart.contains(first)) {
      return false;
    }
    return true;
  }

  /// Inserted illustration markers are private-use code units. They are
  /// content anchors, not punctuation, so skip them only when deciding
  /// whether a neighbouring line starts/ends with a closing/opening mark.
  static String _visibleEdge(String text, {required bool fromStart}) {
    var index = fromStart ? 0 : text.length - 1;
    while (index >= 0 && index < text.length) {
      final code = text.codeUnitAt(index);
      if (code < 0xE000 || code > 0xF8FF) return text[index];
      index += fromStart ? 1 : -1;
    }
    return '';
  }

  /// Detect a fixed-width source only within runs without blank lines.
  ///
  /// Four or more lines must agree within one code point on a column from
  /// 14..120, and those lines must be at least 75% of the run. An isolated
  /// long paragraph or irregular novel paragraphs are left unchanged.
  static List<int?> _fixedWidthColumns(List<String> lines) {
    final result = List<int?>.filled(lines.length, null);
    var start = 0;
    while (start < lines.length) {
      if (lines[start].trim().isEmpty) {
        start++;
        continue;
      }
      var end = start;
      final frequencies = <int, int>{};
      while (end < lines.length && lines[end].trim().isNotEmpty) {
        final length = lines[end].trim().runes.length;
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

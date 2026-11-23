import 'package:night_reader/features/reader/chapter/reader_content_transformer.dart';
import 'package:night_reader/features/reader/text_view/overlay/selection_service.dart';

/// 選到的字（照段落切開的 [selection]）在替換規則全部套用之後的原文
/// [pattern]，與選到的那幾段的原文 [paragraphs]；有一段對不齊時傳回 null。
///
/// 每段照選取位置逐字對齊取出（[sourceRangeOf]）。跨段時段與段之間放規則
/// 看到的那兩段之間的字（[RuleStageText.gaps]：換行，原文有空行時連空行），
/// 新規則接在既有規則之後才比對得到（同 Legado，規則連換行一起比對）。
({String pattern, String paragraphs})? selectionSourceOf(
  ParagraphSelection selection,
  RuleStageText stage,
) {
  final pieces = selection.pieces;
  if (pieces.isEmpty) return null;
  final pattern = StringBuffer();
  final paragraphs = StringBuffer();
  for (var i = 0; i < pieces.length; i += 1) {
    final piece = pieces[i];
    final index = piece.paragraphIndex;
    if (index >= stage.paragraphs.length) return null;
    final source = stage.paragraphs[index];
    final range = sourceRangeOf(
      source: source,
      shown: piece.paragraph,
      start: piece.start,
      end: piece.end,
    );
    if (range == null) return null;
    final last = i == pieces.length - 1;
    if (!last && index >= stage.gaps.length) return null;
    final gap = last ? '' : stage.gaps[index];
    pattern
      ..write(
        source.substring(
          i == 0 ? range.start : 0,
          last ? range.end : source.length,
        ),
      )
      ..write(gap);
    paragraphs
      ..write(source)
      ..write(gap);
  }
  return (pattern: pattern.toString(), paragraphs: paragraphs.toString());
}

/// 畫面上一段正文 [shown] 裡選到的 [start]–[end]，在同一段的原文 [source]
/// 裡是哪個範圍。
///
/// [source] 是替換規則全部套用之後、排版整理之前的那一段
/// （`ReaderContentTransformer.ruleStageParagraphs`），[shown] 是它經過排版
/// 整理（標點換成全形、刪掉中文之間的空白、`...` 變 `……`）與繁簡轉換後畫
/// 在畫面上的樣子。兩邊逐字對齊：略過空白，漢字只認位置（繁簡轉換一字換
/// 一字），英數字不分全半形，其他標點與符號只認位置。刪節號與破折號排版時
/// 會改長度：逐字對不齊時，連續的刪節號或破折號各算一個再對一次。對不齊
/// （例如排版改了字數）或只選到空白時回傳 null。
({int start, int end})? sourceRangeOf({
  required String source,
  required String shown,
  required int start,
  required int end,
}) {
  for (final mergeRuns in const <bool>[false, true]) {
    final sourceKey = _AlignmentKey.of(source, mergeRuns: mergeRuns);
    final shownKey = _AlignmentKey.of(shown, mergeRuns: mergeRuns);
    if (sourceKey.key != shownKey.key) continue;
    final first = shownKey.firstUnitFrom(start);
    final last = shownKey.firstUnitFrom(end) - 1;
    if (last < first) return null;
    return (start: sourceKey.starts[first], end: sourceKey.ends[last]);
  }
  return null;
}

/// 對齊用的字：每個單位記得它在原字串裡的範圍。
final class _AlignmentKey {
  _AlignmentKey._(this.key, this.starts, this.ends);

  factory _AlignmentKey.of(String text, {required bool mergeRuns}) {
    final key = StringBuffer();
    final starts = <int>[];
    final ends = <int>[];
    var offset = 0;
    String? previous;
    for (final rune in text.runes) {
      final start = offset;
      offset += rune > 0xFFFF ? 2 : 1;
      final unit = _unitOf(rune);
      if (unit == null) continue;
      if (mergeRuns &&
          unit == previous &&
          (unit == _ellipsis || unit == _dash)) {
        ends[ends.length - 1] = offset;
        continue;
      }
      previous = unit;
      key.write(unit);
      starts.add(start);
      ends.add(offset);
    }
    return _AlignmentKey._(key.toString(), starts, ends);
  }

  final String key;
  final List<int> starts;
  final List<int> ends;

  /// 第一個從 [offset] 或之後開始的單位。
  int firstUnitFrom(int offset) {
    var index = 0;
    while (index < starts.length && starts[index] < offset) {
      index += 1;
    }
    return index;
  }

  static const String _han = 'H';
  static const String _ellipsis = '…';
  static const String _dash = '—';
  static const String _symbol = '·';

  /// 一個字對齊時的樣子；空白、控制字元與零寬字元回傳 null（略過）。
  /// 每個字都是一個單位，[key] 的長度就是單位數。
  static String? _unitOf(int rune) {
    if (_isIgnorable(rune)) return null;
    if (_hanPattern.hasMatch(String.fromCharCode(rune))) return _han;
    // 全形英數字與標點（U+FF01–FF5E）換成半形。
    final halfWidth = rune >= 0xFF01 && rune <= 0xFF5E ? rune - 0xFEE0 : rune;
    if (_ellipsisRunes.contains(halfWidth)) return _ellipsis;
    if (_dashRunes.contains(halfWidth)) return _dash;
    if (_isAsciiLetterOrDigit(halfWidth)) {
      return String.fromCharCode(halfWidth);
    }
    return _symbol;
  }

  static bool _isIgnorable(int rune) =>
      rune <= 0x20 ||
      (rune >= 0x7F && rune <= 0xA0) ||
      rune == 0x3000 ||
      rune == 0x200B ||
      rune == 0xFEFF;

  static bool _isAsciiLetterOrDigit(int rune) =>
      (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A);

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

  static final RegExp _hanPattern = RegExp(r'\p{Script=Han}', unicode: true);
}

import 'dart:math' as math;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

import 'reader_paragraph_layout.dart';

final class VisualLineBlockPlan {
  const VisualLineBlockPlan({
    required this.end,
    required this.visualLineBreakOffsets,
  });

  final int end;
  final List<int> visualLineBreakOffsets;
}

final class _LineRange {
  const _LineRange(this.start, this.end);
  final int start;
  final int end;
}

/// Product policy for choosing a visual-line break from native shaping facts.
///
/// Native word boundaries are evidence, not authority. Whole-word rollback is
/// only meaningful for Latin-style word tokens; CJK and other scripts remain
/// grapheme-placeable so a glyph that physically fits is never moved merely
/// because ICU grouped it into a linguistic word. Whitespace is a separator
/// and never owns a new visual line.
final class VisualLineBreakPolicy {
  const VisualLineBreakPolicy();

  bool isSeparator(String text, ShapedGrapheme grapheme) {
    final slice = text.substring(grapheme.start, grapheme.end);
    if (slice.isEmpty) return false;
    return slice.runes.every(_isWhitespaceCodePoint);
  }

  int? preferredWordBreak({
    required String text,
    required ShapedGrapheme overflowing,
    required int lineStart,
    required Set<int> graphemeStarts,
  }) {
    final wordStart = overflowing.wordStart;
    final wordEnd = overflowing.wordEnd;
    if (wordStart <= lineStart ||
        wordStart >= overflowing.end ||
        wordEnd <= wordStart ||
        wordEnd > text.length) {
      return null;
    }
    if (!graphemeStarts.contains(wordStart)) return null;
    if (!_isLatinWordSpan(text, wordStart, wordEnd)) return null;
    return wordStart;
  }

  bool _isLatinWordSpan(String text, int start, int end) {
    if (start < 0 || end > text.length || start >= end) return false;
    var sawLetterOrDigit = false;
    for (final rune in text.substring(start, end).runes) {
      if (_isLatinLetter(rune) || _isAsciiDigit(rune)) {
        sawLetterOrDigit = true;
        continue;
      }
      if (_isCombiningMark(rune) ||
          rune == 0x27 || // '
          rune == 0x2019 || // ’
          rune == 0x2D || // -
          rune == 0x5F) {
        continue;
      }
      return false;
    }
    return sawLetterOrDigit;
  }

  bool _isLatinLetter(int rune) =>
      (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A) ||
      (rune >= 0x00C0 && rune <= 0x024F) ||
      (rune >= 0x1E00 && rune <= 0x1EFF);

  bool _isAsciiDigit(int rune) => rune >= 0x30 && rune <= 0x39;

  bool _isCombiningMark(int rune) =>
      (rune >= 0x0300 && rune <= 0x036F) ||
      (rune >= 0x1AB0 && rune <= 0x1AFF) ||
      (rune >= 0x1DC0 && rune <= 0x1DFF) ||
      (rune >= 0x20D0 && rune <= 0x20FF) ||
      (rune >= 0xFE20 && rune <= 0xFE2F);

  bool _isWhitespaceCodePoint(int rune) =>
      (rune >= 0x09 && rune <= 0x0D) ||
      rune == 0x20 ||
      rune == 0x85 ||
      rune == 0xA0 ||
      rune == 0x1680 ||
      (rune >= 0x2000 && rune <= 0x200A) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202F ||
      rune == 0x205F ||
      rune == 0x3000;
}

/// Sole owner of visual-line breaking in Hybrid B.
///
/// A grapheme stays on the current line whenever its shaped geometry fits the
/// physical content width. Punctuation has no special veto. This class never
/// reads SkParagraph soft-wrap line boundaries.
final class VisualLineLayoutEngine {
  const VisualLineLayoutEngine({
    this.paragraphLayout = const ReaderParagraphLayout(),
    this.breakPolicy = const VisualLineBreakPolicy(),
  });

  final ReaderParagraphLayout paragraphLayout;
  final VisualLineBreakPolicy breakPolicy;

  static const int _probeLookaheadCodeUnits = 256;
  static const double _fitEpsilon = 0.01;

  VisualLineBlockPlan planBlock({
    required String text,
    required int start,
    required int maxBlockChars,
    required HybridBlockTextStyle textStyle,
    required double contentWidth,
    required double? cellWidth,
    required int indentChars,
  }) {
    if (start < 0 || start > text.length) {
      throw RangeError.range(start, 0, text.length, 'start');
    }
    if (start == text.length) {
      return VisualLineBlockPlan(
        end: start,
        visualLineBreakOffsets: const <int>[],
      );
    }
    if (!contentWidth.isFinite || contentWidth <= 0) {
      throw StateError('Visual line width must be finite and positive.');
    }

    final targetEnd = _safeBoundary(
      text,
      math.min(text.length, start + math.max(1, maxBlockChars)),
    );
    final targetRelative = math.max(1, targetEnd - start);
    var lookahead = _probeLookaheadCodeUnits;

    while (true) {
      final probeEnd = _safeBoundary(
        text,
        math.min(text.length, start + targetRelative + lookahead),
      );
      if (probeEnd <= start) {
        throw StateError('Visual-line probe did not advance.');
      }
      final window = text.substring(start, probeEnd);
      if (window.contains('\n') || window.contains('\r')) {
        throw StateError(
          'Semantic hard breaks must be owned before visual-line planning.',
        );
      }

      final shaped = paragraphLayout.shapeGraphemes(
        text: window,
        textStyle: textStyle,
      );
      if (shaped.isEmpty) {
        throw StateError('Native shaping produced no graphemes.');
      }

      final indent = paragraphLayout.indentWidth(
        indentChars: indentChars,
        fontSize: textStyle.fontSize,
        cellWidth: cellWidth,
      );
      if (indent >= contentWidth - _fitEpsilon) {
        throw StateError('Paragraph indent consumes the content width.');
      }

      final lines = _breakLines(
        shaped,
        text: window,
        windowLength: window.length,
        contentWidth: contentWidth,
        firstLineIndent: indent,
      );

      if (probeEnd == text.length && window.length <= targetRelative) {
        return VisualLineBlockPlan(
          end: text.length,
          visualLineBreakOffsets: <int>[
            for (final line in lines.skip(1)) line.start,
          ],
        );
      }

      final complete = probeEnd == text.length
          ? lines
          : lines.length <= 1
          ? const <_LineRange>[]
          : lines.sublist(0, lines.length - 1);
      _LineRange? chosen;
      for (final line in complete) {
        if (line.end <= targetRelative) {
          chosen = line;
        } else {
          break;
        }
      }
      chosen ??= complete.isEmpty ? null : complete.first;
      if (chosen != null) {
        final blockEnd = chosen.end;
        return VisualLineBlockPlan(
          end: start + blockEnd,
          visualLineBreakOffsets: <int>[
            for (final line in complete.skip(1))
              if (line.start < blockEnd) line.start,
          ],
        );
      }

      lookahead *= 2;
    }
  }

  List<_LineRange> _breakLines(
    List<ShapedGrapheme> shaped, {
    required String text,
    required int windowLength,
    required double contentWidth,
    required double firstLineIndent,
  }) {
    final lines = <_LineRange>[];
    final graphemeIndexByStart = <int, int>{
      for (var i = 0; i < shaped.length; i += 1) shaped[i].start: i,
    };
    var lineStart = shaped.first.start;
    var lineOrigin = shaped.first.left;
    var available = contentWidth - firstLineIndent;
    var index = 0;

    while (index < shaped.length) {
      final grapheme = shaped[index];
      final occupied = grapheme.right - lineOrigin;
      final hasContent = grapheme.start > lineStart;
      if (hasContent && occupied > available + _fitEpsilon) {
        // A separator belongs to the preceding line. Do not create a visual
        // line whose only content is the whitespace between two words; the
        // following token will choose the real boundary.
        if (breakPolicy.isSeparator(text, grapheme)) {
          index += 1;
          continue;
        }
        final wordBreak = breakPolicy.preferredWordBreak(
          text: text,
          overflowing: grapheme,
          lineStart: lineStart,
          graphemeStarts: graphemeIndexByStart.keys.toSet(),
        );
        final breakOffset = wordBreak ?? grapheme.start;
        final breakIndex = graphemeIndexByStart[breakOffset];
        if (breakIndex == null || breakOffset <= lineStart) {
          throw StateError(
            'Reader line policy produced an invalid break at $breakOffset.',
          );
        }
        lines.add(_LineRange(lineStart, breakOffset));
        lineStart = breakOffset;
        lineOrigin = shaped[breakIndex].left;
        available = contentWidth;
        index = breakIndex;
        continue;
      }
      index += 1;
    }

    if (lineStart < windowLength) {
      lines.add(_LineRange(lineStart, windowLength));
    }
    return lines;
  }

  int _safeBoundary(String text, int offset) {
    final safe = offset.clamp(0, text.length).toInt();
    if (safe <= 0 || safe >= text.length) return safe;
    final previous = text.codeUnitAt(safe - 1);
    final next = text.codeUnitAt(safe);
    final splitsSurrogate =
        previous >= 0xD800 &&
        previous <= 0xDBFF &&
        next >= 0xDC00 &&
        next <= 0xDFFF;
    return splitsSurrogate ? safe - 1 : safe;
  }
}

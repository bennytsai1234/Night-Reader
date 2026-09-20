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

/// Sole owner of visual-line breaking in Hybrid B.
///
/// A grapheme stays on the current line whenever its shaped geometry fits the
/// physical content width. Punctuation has no special veto. This class never
/// reads SkParagraph soft-wrap line boundaries.
final class VisualLineLayoutEngine {
  const VisualLineLayoutEngine({
    this.paragraphLayout = const ReaderParagraphLayout(),
  });

  final ReaderParagraphLayout paragraphLayout;

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
    required int windowLength,
    required double contentWidth,
    required double firstLineIndent,
  }) {
    final lines = <_LineRange>[];
    var lineStart = shaped.first.start;
    var lineOrigin = shaped.first.left;
    var available = contentWidth - firstLineIndent;
    var hasGrapheme = false;

    for (final grapheme in shaped) {
      final occupied = grapheme.right - lineOrigin;
      if (hasGrapheme && occupied > available + _fitEpsilon) {
        lines.add(_LineRange(lineStart, grapheme.start));
        lineStart = grapheme.start;
        lineOrigin = grapheme.left;
        available = contentWidth;
      }
      hasGrapheme = true;
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

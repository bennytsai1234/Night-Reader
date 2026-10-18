import 'dart:math' as math;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

import 'reader_paragraph_layout.dart';

final class VisualLineBlockPlan {
  const VisualLineBlockPlan({
    required this.end,
    required this.visualLineBreakOffsets,
    this.spacers = const <LineSpacer>[],
  });

  final int end;
  final List<int> visualLineBreakOffsets;

  /// 英數字段補到半格的補白，offset 相對於這一塊的開頭。
  final List<LineSpacer> spacers;
}

final class _LineRange {
  const _LineRange(this.start, this.end, this.spacers);
  final int start;
  final int end;
  final List<LineSpacer> spacers;
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
/// 每個字佔整數個字格：寬度剛好一格的字（漢字、全形標點、emoji）照實際
/// 字寬排；其餘連續的字（英文、數字、半形符號）合成一段，寬度補到半格的
/// 整數倍，補白平分在兩側，所以一段英數字之後的字仍落在半格上。補白
/// 規則：
/// - 鄰接漢字或 emoji 的一側至少留 1/8 格（W3C《中文排版需求》的中西文
///   間隙）；鄰接全形標點的一側不另外留，標點字形本身已有空白。
/// - 行首的一段不補左側、補白全放右側，貼齊左邊界（段首縮排之後也算
///   行首）；行尾的一段不補右側。
///
/// 字放得下就留在這一行，只有避頭尾例外（ADR 0026）：在某處斷行會讓
/// 「，。」』」這類標點落在行首、「「『」留在行尾，或拆開成對的刪節號、
/// 破折號時，往回找可以斷的位置，把前面幾個字一起拉到下一行；這一行空出
/// 的寬度平均攤進字距，右緣仍然切齊。
///
/// This class never reads SkParagraph soft-wrap line boundaries.
final class VisualLineLayoutEngine {
  const VisualLineLayoutEngine({
    this.paragraphLayout = const ReaderParagraphLayout(),
    this.breakPolicy = const VisualLineBreakPolicy(),
  });

  final ReaderParagraphLayout paragraphLayout;
  final VisualLineBreakPolicy breakPolicy;

  static const int _probeLookaheadCodeUnits = 256;
  static const double _fitEpsilon = 0.01;

  /// 字寬與一格相差在這之內就算佔一格；同一字型同一字級的漢字與字格
  /// 量出來只有浮點誤差。
  static const double _cellTolerance = 0.05;

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
    final cell =
        paragraphLayout.measureCellWidth(
          fontSize: textStyle.fontSize,
          letterSpacing: textStyle.letterSpacing,
          bold: textStyle.bold,
        ) ??
        textStyle.fontSize;
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
        cell: cell,
      );

      if (probeEnd == text.length && window.length <= targetRelative) {
        return _planFor(lines, end: text.length - start, start: start);
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
        return _planFor(
          [
            for (final line in complete)
              if (line.start < chosen.end) line,
          ],
          end: chosen.end,
          start: start,
        );
      }

      lookahead *= 2;
    }
  }

  VisualLineBlockPlan _planFor(
    List<_LineRange> lines, {
    required int end,
    required int start,
  }) {
    return VisualLineBlockPlan(
      end: start + end,
      visualLineBreakOffsets: <int>[
        for (final line in lines.skip(1)) line.start,
      ],
      spacers: <LineSpacer>[for (final line in lines) ...line.spacers],
    );
  }

  List<_LineRange> _breakLines(
    List<ShapedGrapheme> shaped, {
    required String text,
    required int windowLength,
    required double contentWidth,
    required double firstLineIndent,
    required double cell,
  }) {
    final graphemeIndexByStart = <int, int>{
      for (var i = 0; i < shaped.length; i += 1) shaped[i].start: i,
    };
    final graphemeStarts = graphemeIndexByStart.keys.toSet();
    final half = cell / 2;
    final minimumGap = cell / 8;
    bool isCell(int index) {
      final advance = shaped[index].right - shaped[index].left;
      return (advance - cell).abs() <= _cellTolerance;
    }

    double gapBeside(int? index) {
      if (index == null || index < 0 || index >= shaped.length) return 0;
      if (!isCell(index)) return 0;
      return _isCjkPunctuation(text, shaped[index]) ? 0 : minimumGap;
    }

    double snap(double width) {
      if (width <= 0) return 0;
      return ((width - _fitEpsilon) / half).ceil() * half;
    }

    // 一段寬 width 的字補到半格後，左側該補多少：補白平分兩側，但每側
    // 不少於該側的最小間隙，不足的從另一側讓出（總補白至少是兩側間隙
    // 之和，所以讓得出來）。
    double leftPadding(double width, double gapLeft, double gapRight) {
      final padding = snap(width + gapLeft + gapRight) - width;
      return (padding / 2).clamp(gapLeft, padding - gapRight).toDouble();
    }

    final lines = <_LineRange>[];
    var lineStart = shaped.first.start;
    var lineStartIndex = 0;
    var spacers = <LineSpacer>[];
    var x = 0.0;
    var available = contentWidth - firstLineIndent;
    // 本行最後一段英數字補在右側的補白；行在它後面結束時拿掉。
    LineSpacer? trailingSpacer;
    var index = 0;

    void endLine(int breakOffset, int nextIndex) {
      if (trailingSpacer != null && trailingSpacer!.offset == breakOffset) {
        spacers.remove(trailingSpacer);
      }
      lines.add(_LineRange(lineStart, breakOffset, spacers));
      lineStart = breakOffset;
      lineStartIndex = nextIndex;
      spacers = <LineSpacer>[];
      trailingSpacer = null;
      x = 0;
      available = contentWidth;
    }

    String charAt(int i) => text.substring(shaped[i].start, shaped[i].end);

    // 第 i 個字之前斷行是否違反避頭尾。
    bool forbidsBreakBefore(int i) {
      final previous = charAt(i - 1);
      final current = charAt(i);
      if (_noLineStart.contains(current) || _noLineEnd.contains(previous)) {
        return true;
      }
      return previous == current && _unsplittablePairs.contains(current);
    }

    // 本來要在 brk 之前斷行；違反避頭尾時往回找可以斷的位置，回傳下一行
    // 的第一個字。整段英數字當成一個字一起拉。找不到（本行會被拉空、或
    // 要拉超過 [_maxKinsokuPull] 個字）就回傳 null，照原本的位置斷。
    int? kinsokuBreak(int brk) {
      var b = brk;
      var pulled = 0;
      while (forbidsBreakBefore(b)) {
        if (pulled == _maxKinsokuPull) return null;
        var previous = b - 1;
        if (!isCell(previous)) {
          while (previous > lineStartIndex && !isCell(previous - 1)) {
            previous -= 1;
          }
        }
        if (previous <= lineStartIndex) return null;
        b = previous;
        pulled += 1;
      }
      return b == brk ? null : b;
    }

    // 在 b 之前斷行，並把這一行空出來的寬度平均攤進字距。只攤在旁邊有
    // 整格字的字距上，英文單字裡面不拉開。行寬補到文字框裡最後一條半格
    // 線，和排滿的行同一個右緣：文字框是整數個字格再加一點防浮點誤差的
    // slack，slack 攤進去會讓原生排版把這一行再折一次。
    void endLineJustified(int b) {
      final breakOffset = shaped[b].start;
      final widths = <int, double>{};
      for (final spacer in spacers) {
        if (spacer.offset < breakOffset) {
          widths[spacer.offset] = (widths[spacer.offset] ?? 0) + spacer.width;
        }
      }
      var used = shaped[b - 1].right - shaped[lineStartIndex].left;
      for (final width in widths.values) {
        used += width;
      }
      final lineWidth = ((available + _fitEpsilon) / half).floor() * half;
      final spread = lineWidth - used;
      final gaps = <int>[
        for (var k = lineStartIndex + 1; k < b; k += 1)
          if (isCell(k) || isCell(k - 1)) k,
      ];
      if (spread > _fitEpsilon && gaps.isNotEmpty) {
        final each = spread / gaps.length;
        for (final k in gaps) {
          final offset = shaped[k].start;
          widths[offset] = (widths[offset] ?? 0) + each;
        }
      }
      spacers = <LineSpacer>[
        for (final offset in widths.keys.toList()..sort())
          LineSpacer(offset, widths[offset]!),
      ];
      trailingSpacer = null;
      endLine(breakOffset, b);
    }

    // 在 brk 之前斷行，違反避頭尾時改斷在前面；回傳下一行的第一個字。
    int breakBefore(int brk) {
      final pulled = kinsokuBreak(brk);
      if (pulled == null) {
        endLine(shaped[brk].start, brk);
        return brk;
      }
      endLineJustified(pulled);
      return pulled;
    }

    while (index < shaped.length) {
      final grapheme = shaped[index];
      if (isCell(index)) {
        final advance = grapheme.right - grapheme.left;
        final hasContent = index > lineStartIndex;
        if (hasContent && x + advance > available + _fitEpsilon) {
          // A separator belongs to the preceding line. Do not create a
          // visual line whose only content is the space before a token.
          if (breakPolicy.isSeparator(text, grapheme)) {
            index += 1;
            continue;
          }
          index = breakBefore(index);
          continue;
        }
        x += advance;
        trailingSpacer = null;
        index += 1;
        continue;
      }

      // 一段連續的非整格字：[index, runEnd)。
      var runEnd = index;
      while (runEnd < shaped.length && !isCell(runEnd)) {
        runEnd += 1;
      }
      final atLineStart = index == lineStartIndex;
      final gapLeft = atLineStart ? 0.0 : gapBeside(index - 1);
      final gapRight = gapBeside(runEnd);
      final runStart = shaped[index].start;

      // 整段放得下：左右補白照規則補，右側補白在行就此結束時拿掉。
      final width = _segmentWidth(shaped, text, index, runEnd);
      final left = atLineStart ? 0.0 : leftPadding(width, gapLeft, gapRight);
      if (x + left + width <= available + _fitEpsilon) {
        final right = atLineStart
            ? snap(width + gapRight) - width
            : snap(width + gapLeft + gapRight) - width - left;
        if (left > _fitEpsilon) spacers.add(LineSpacer(runStart, left));
        x += left + width;
        trailingSpacer = null;
        if (right > _fitEpsilon && runEnd < shaped.length) {
          final spacer = LineSpacer(shaped[runEnd].start, right);
          spacers.add(spacer);
          trailingSpacer = spacer;
          x += right;
        }
        index = runEnd;
        continue;
      }

      // 放不下：這段在本行結束。找出能放進本行的最長前段（行尾空白不
      // 算寬度），再依斷詞規則決定斷點。
      double leftFor(double w) =>
          atLineStart ? 0.0 : leftPadding(w, gapLeft, 0);
      var fits = index;
      while (fits < runEnd) {
        final w = _segmentWidth(
          shaped,
          text,
          index,
          fits + 1,
          trimTrailingSeparators: true,
        );
        if (x + leftFor(w) + w > available + _fitEpsilon) break;
        fits += 1;
      }
      int breakOffset;
      if (fits == runEnd) {
        // 整段當行尾放得下（不需要右側間隙）。
        breakOffset = runEnd < shaped.length ? shaped[runEnd].start : -1;
      } else {
        final overflowing = shaped[fits];
        breakOffset =
            breakPolicy.preferredWordBreak(
              text: text,
              overflowing: overflowing,
              lineStart: lineStart,
              graphemeStarts: graphemeStarts,
            ) ??
            overflowing.start;
        if (breakOffset <= runStart) {
          if (!atLineStart) {
            // 第一個字就放不下，而本行已有內容：整段移到下一行。
            index = breakBefore(index);
            continue;
          }
          // 行首的一個英文字比整行還寬：只能從字中間斷，至少放一個字。
          final forced = math.max(fits, index + 1);
          breakOffset = forced < shaped.length ? shaped[forced].start : -1;
        }
      }
      final segmentEnd = breakOffset < 0
          ? runEnd
          : graphemeIndexByStart[breakOffset]!;
      final segmentWidth = _segmentWidth(
        shaped,
        text,
        index,
        segmentEnd,
        trimTrailingSeparators: true,
      );
      final segmentLeft = leftFor(segmentWidth);
      if (segmentLeft > _fitEpsilon) {
        spacers.add(LineSpacer(runStart, segmentLeft));
      }
      trailingSpacer = null;
      if (breakOffset < 0) {
        // 視窗在這段之後就結束了。
        index = runEnd;
        continue;
      }
      if (segmentEnd == runEnd) {
        // 整段留在行尾，下一行從整格字開始：照避頭尾檢查。
        index = breakBefore(segmentEnd);
      } else {
        endLine(breakOffset, segmentEnd);
        index = segmentEnd;
      }
      continue;
    }

    if (lineStart < windowLength) {
      if (trailingSpacer != null && trailingSpacer!.offset >= windowLength) {
        spacers.remove(trailingSpacer);
      }
      lines.add(_LineRange(lineStart, windowLength, spacers));
    }
    return lines;
  }

  /// [from, to) 這段字的寬度；行尾的空白不算。
  double _segmentWidth(
    List<ShapedGrapheme> shaped,
    String text,
    int from,
    int to, {
    bool trimTrailingSeparators = false,
  }) {
    var last = to - 1;
    if (trimTrailingSeparators) {
      while (last >= from && breakPolicy.isSeparator(text, shaped[last])) {
        last -= 1;
      }
    }
    if (last < from) return 0;
    return shaped[last].right - shaped[from].left;
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

/// 不放行首的標點。
const Set<String> _noLineStart = {
  '，', '。', '、', '；', '：', '！', '？', '」', '』', '）', '】', '》', '〉', //
  '〕', '｝', '．', '・', '‧', '·', '”', '’', ',', '.', ';', ':', '!', '?', //
  ')', ']', '}',
};

/// 不放行尾的標點。
const Set<String> _noLineEnd = {
  '「', '『', '（', '【', '《', '〈', '〔', '｛', '“', '‘', '(', '[', '{', //
};

/// 成對使用、不拆到兩行的符號：刪節號「……」與破折號「——」。
const Set<String> _unsplittablePairs = {'…', '—'};

/// 避頭尾最多往回拉幾個字（整段英數字算一個）。最常見的是拉一個字陪標點
/// 下去；句號接下引號這樣兩個收尾標點連在一起時要拉兩個，再留一個餘裕。
/// 超過就照原本的位置斷，免得一行被拉得太短、字距攤得太開。
const int _maxKinsokuPull = 3;

/// 全形標點：字形本身已帶空白，旁邊的英數字不另外留間隙。
bool _isCjkPunctuation(String text, ShapedGrapheme grapheme) {
  final rune = text.substring(grapheme.start, grapheme.end).runes.first;
  return (rune >= 0x3000 && rune <= 0x303F) ||
      (rune >= 0xFE30 && rune <= 0xFE4F) ||
      (rune >= 0xFF01 && rune <= 0xFF0F) ||
      (rune >= 0xFF1A && rune <= 0xFF20) ||
      (rune >= 0xFF3B && rune <= 0xFF40) ||
      (rune >= 0xFF5B && rune <= 0xFF65) ||
      (rune >= 0x2010 && rune <= 0x2027) ||
      rune == 0x22EF ||
      rune == 0x30FB;
}

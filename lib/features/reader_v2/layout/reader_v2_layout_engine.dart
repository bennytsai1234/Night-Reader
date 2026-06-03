import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/content/reader_v2_content.dart';

import 'reader_v2_layout.dart';
import 'reader_v2_layout_spec.dart';
import 'reader_v2_typography.dart';

typedef ReaderV2LayoutStatsObserver =
    void Function(ReaderV2LayoutEngineStats stats);

class ReaderV2LayoutEngineStats {
  const ReaderV2LayoutEngineStats({
    required this.chapterIndex,
    required this.elapsed,
    required this.lineLayoutPasses,
    required this.widthMeasurePasses,
    required this.fittingFallbacks,
    required this.fittingBinarySearchPasses,
    required this.lineCount,
    required this.pageCount,
  });

  final int chapterIndex;
  final Duration elapsed;
  final int lineLayoutPasses;
  final int widthMeasurePasses;
  final int fittingFallbacks;
  final int fittingBinarySearchPasses;
  final int lineCount;
  final int pageCount;
}

class ReaderV2LayoutEngine {
  static const String _lineStartForbidden = '。，、：；！？）》」』〉】〗;:!?)]}>';
  static const String _lineEndForbidden = '（《「『〈【〖([{<';
  static ReaderV2LayoutEngineStats? debugLastStats;
  static ReaderV2LayoutStatsObserver? debugOnStats;

  /// Reusable TextPainter for measuring line widths to reduce GC pressure.
  final TextPainter _measurePainter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
    maxLines: 1,
  );

  /// Reusable TextPainter for binary-search fitting.
  final TextPainter _fitPainter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
    maxLines: 1,
  );

  int _lineLayoutPasses = 0;
  int _widthMeasurePasses = 0;
  int _fittingFallbacks = 0;
  int _fittingBinarySearchPasses = 0;

  ReaderV2ChapterLayout layout(
    ReaderV2Content content,
    ReaderV2LayoutSpec spec,
  ) {
    _resetStats();
    final stopwatch = Stopwatch()..start();
    final lines = <ReaderV2TextLine>[];
    var y = 0.0;

    if (content.title.isNotEmpty) {
      final titleLines = _layoutBlock(
        chapterIndex: content.chapterIndex,
        firstLineIndex: lines.length,
        text: content.title,
        style: _titleTextStyle(spec),
        maxWidth: spec.contentWidth,
        top: y,
        startOffset: 0,
        isTitle: true,
        paragraphIndex: -1,
      );
      lines.addAll(titleLines);
      if (titleLines.isNotEmpty) {
        y = titleLines.last.bottom + spec.style.paragraphSpacing * 8;
      }
    }

    var paragraphOffset = content.bodyStartOffset;
    for (
      var paragraphIndex = 0;
      paragraphIndex < content.paragraphs.length;
      paragraphIndex++
    ) {
      final paragraph = content.paragraphs[paragraphIndex];
      final paragraphLines = _layoutBlock(
        chapterIndex: content.chapterIndex,
        firstLineIndex: lines.length,
        text: paragraph,
        style: _contentTextStyle(spec),
        maxWidth: spec.contentWidth,
        top: y,
        startOffset: paragraphOffset,
        paragraphIndex: paragraphIndex,
        textIndent: spec.style.textIndent,
      );
      lines.addAll(paragraphLines);
      if (paragraphLines.isNotEmpty) {
        y = paragraphLines.last.bottom + _paragraphSpacingPixels(spec);
      }
      paragraphOffset += paragraph.length + 2;
    }

    final pages = _paginate(lines: lines, spec: spec, content: content);
    final layout = ReaderV2ChapterLayout(
      chapterIndex: content.chapterIndex,
      displayText: content.displayText,
      contentHash: content.contentHash,
      layoutSignature: spec.layoutSignature,
      lines: List<ReaderV2TextLine>.unmodifiable(lines),
      pages: List<ReaderV2PageSlice>.unmodifiable(pages),
      contentHeight: lines.isEmpty ? 0.0 : lines.last.bottom,
    );
    _publishStats(
      chapterIndex: content.chapterIndex,
      elapsed: stopwatch.elapsed,
      lineCount: lines.length,
      pageCount: pages.length,
    );
    return layout;
  }

  void _resetStats() {
    _lineLayoutPasses = 0;
    _widthMeasurePasses = 0;
    _fittingFallbacks = 0;
    _fittingBinarySearchPasses = 0;
  }

  void _publishStats({
    required int chapterIndex,
    required Duration elapsed,
    required int lineCount,
    required int pageCount,
  }) {
    final stats = ReaderV2LayoutEngineStats(
      chapterIndex: chapterIndex,
      elapsed: elapsed,
      lineLayoutPasses: _lineLayoutPasses,
      widthMeasurePasses: _widthMeasurePasses,
      fittingFallbacks: _fittingFallbacks,
      fittingBinarySearchPasses: _fittingBinarySearchPasses,
      lineCount: lineCount,
      pageCount: pageCount,
    );
    debugLastStats = stats;
    debugOnStats?.call(stats);
  }

  TextStyle _contentTextStyle(ReaderV2LayoutSpec spec) {
    return TextStyle(
      fontSize: spec.style.fontSize,
      height: spec.style.effectiveLineHeight,
      letterSpacing: spec.style.letterSpacing,
      fontWeight: spec.style.bold ? FontWeight.bold : FontWeight.normal,
      fontFeatures: kReaderV2CjkFontFeatures,
    );
  }

  TextStyle _titleTextStyle(ReaderV2LayoutSpec spec) {
    return TextStyle(
      fontSize: spec.style.fontSize + 4,
      height: spec.style.effectiveLineHeight,
      letterSpacing: spec.style.letterSpacing,
      fontWeight: FontWeight.bold,
      fontFeatures: kReaderV2CjkFontFeatures,
    );
  }

  double _paragraphSpacingPixels(ReaderV2LayoutSpec spec) {
    return (spec.style.fontSize * spec.style.effectiveLineHeight) *
        spec.style.paragraphSpacing;
  }

  List<ReaderV2TextLine> _layoutBlock({
    required int chapterIndex,
    required int firstLineIndex,
    required String text,
    required TextStyle style,
    required double maxWidth,
    required double top,
    required int startOffset,
    required int paragraphIndex,
    bool isTitle = false,
    int textIndent = 0,
  }) {
    if (text.isEmpty) return const <ReaderV2TextLine>[];
    final lines = <ReaderV2TextLine>[];
    final segments = text.split('\n');
    var segmentStart = 0;
    var lineTop = top;

    for (var segmentIndex = 0; segmentIndex < segments.length; segmentIndex++) {
      final segment = segments[segmentIndex];
      final isFirstSegment = segmentIndex == 0;
      final isLastSegment = segmentIndex == segments.length - 1;
      final segmentLines = _layoutInlineSegment(
        chapterIndex: chapterIndex,
        firstLineIndex: firstLineIndex + lines.length,
        text: segment,
        style: style,
        maxWidth: maxWidth,
        top: lineTop,
        startOffset: startOffset + segmentStart,
        isTitle: isTitle,
        paragraphIndex: paragraphIndex,
        isParagraphStartSegment: isFirstSegment,
        isParagraphEndSegment: isLastSegment,
        textIndent: isFirstSegment ? textIndent : 0,
      );
      lines.addAll(segmentLines);
      if (segmentLines.isNotEmpty) {
        lineTop = segmentLines.last.bottom;
      } else if (!isLastSegment) {
        lineTop += _fallbackLineHeight(style);
      }

      if (!isLastSegment && lines.isNotEmpty) {
        final hardBreakEnd = startOffset + segmentStart + segment.length + 1;
        final lastIndex = lines.length - 1;
        lines[lastIndex] = _copyLine(
          lines[lastIndex],
          endCharOffset: hardBreakEnd,
          isParagraphEnd: false,
        );
      }
      segmentStart += segment.length + (isLastSegment ? 0 : 1);
    }
    return lines;
  }

  List<ReaderV2TextLine> _layoutInlineSegment({
    required int chapterIndex,
    required int firstLineIndex,
    required String text,
    required TextStyle style,
    required double maxWidth,
    required double top,
    required int startOffset,
    required int paragraphIndex,
    required bool isParagraphStartSegment,
    required bool isParagraphEndSegment,
    bool isTitle = false,
    int textIndent = 0,
  }) {
    if (text.isEmpty) return const <ReaderV2TextLine>[];
    final indentText =
        !isTitle && textIndent > 0 ? '　' * textIndent.clamp(0, 8) : '';
    final laidOutText = indentText.isEmpty ? text : '$indentText$text';
    final indentLength = indentText.length;
    final painter = TextPainter(
      text: const TextSpan(text: ''),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: null,
    );
    final lines = <ReaderV2TextLine>[];
    var localStart = 0;
    var lineTop = top;
    var lineIndex = 0;

    while (localStart < laidOutText.length) {
      final remaining = laidOutText.substring(localStart);
      painter.text = TextSpan(text: remaining, style: style);
      _lineLayoutPasses += 1;
      painter.layout(maxWidth: maxWidth);
      final metrics = painter.computeLineMetrics();
      if (metrics.isEmpty) break;
      final metric = metrics.first;
      var charsConsumed = _lineCharsConsumed(
        painter: painter,
        remaining: remaining,
      );
      charsConsumed = _fitLineChars(
        text: remaining,
        style: style,
        maxWidth: maxWidth,
        preferredChars: charsConsumed,
      );
      if (charsConsumed <= 0) break;

      final localEnd =
          (localStart + charsConsumed)
              .clamp(localStart + 1, laidOutText.length)
              .toInt();
      final lineText = laidOutText.substring(localStart, localEnd);
      final contentStart =
          (localStart - indentLength).clamp(0, text.length).toInt();
      final contentEnd =
          (localEnd - indentLength).clamp(contentStart, text.length).toInt();
      final lineHeight =
          metric.height > 0
              ? metric.height
              : (style.fontSize ?? 0) * (style.height ?? 1.0);
      final lineBottom = lineTop + lineHeight;
      final isParagraphEnd = localEnd >= laidOutText.length;
      lines.add(
        ReaderV2TextLine(
          text: lineText,
          chapterIndex: chapterIndex,
          lineIndex: firstLineIndex + lines.length,
          startCharOffset: startOffset + contentStart,
          endCharOffset: startOffset + contentEnd,
          top: lineTop,
          bottom: lineBottom,
          baseline: lineTop + metric.baseline,
          width: _measureLineWidth(lineText, style),
          isTitle: isTitle,
          paragraphIndex: paragraphIndex,
          isParagraphStart: isParagraphStartSegment && lineIndex == 0,
          isParagraphEnd: isParagraphEndSegment && isParagraphEnd,
        ),
      );
      localStart = localEnd;
      lineTop = lineBottom;
      lineIndex += 1;
    }
    return lines;
  }

  ReaderV2TextLine _copyLine(
    ReaderV2TextLine line, {
    required int endCharOffset,
    required bool isParagraphEnd,
  }) {
    return ReaderV2TextLine(
      text: line.text,
      chapterIndex: line.chapterIndex,
      lineIndex: line.lineIndex,
      startCharOffset: line.startCharOffset,
      endCharOffset: endCharOffset,
      top: line.top,
      bottom: line.bottom,
      baseline: line.baseline,
      width: line.width,
      isTitle: line.isTitle,
      paragraphIndex: line.paragraphIndex,
      isParagraphStart: line.isParagraphStart,
      isParagraphEnd: isParagraphEnd,
    );
  }

  double _fallbackLineHeight(TextStyle style) {
    return (style.fontSize ?? 0) * (style.height ?? 1.0);
  }

  int _lineCharsConsumed({
    required TextPainter painter,
    required String remaining,
  }) {
    if (remaining.isEmpty) return 0;
    var boundary = painter.getLineBoundary(const TextPosition(offset: 0));
    var end = boundary.end.clamp(0, remaining.length).toInt();
    if (end <= 0 && remaining.length > 1) {
      boundary = painter.getLineBoundary(const TextPosition(offset: 1));
      end = boundary.end.clamp(0, remaining.length).toInt();
    }
    if (end <= 0) return 0;

    if (end < remaining.length) {
      final nextChar = remaining.substring(end, end + 1);
      if (_lineStartForbidden.contains(nextChar) && end > 1) {
        end -= 1;
      }
    }
    if (end > 1) {
      final lastChar = remaining.substring(end - 1, end);
      if (_lineEndForbidden.contains(lastChar)) {
        end -= 1;
      }
    }
    return end <= 0 ? 1 : end.clamp(0, remaining.length).toInt();
  }

  int _fitLineChars({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required int preferredChars,
  }) {
    if (text.isEmpty) return 0;
    final preferred = preferredChars.clamp(1, text.length).toInt();
    final candidate = text.substring(0, preferred);
    if (_measureLineWidth(candidate, style) <= maxWidth + 0.5) {
      return preferred;
    }
    return _maxFittingPrefix(
      text: text,
      style: style,
      maxWidth: maxWidth,
      preferredChars: preferred,
    );
  }

  int _maxFittingPrefix({
    required String text,
    required TextStyle style,
    required double maxWidth,
    int? preferredChars,
  }) {
    _fittingFallbacks += 1;
    final clusterEndOffsets = <int>[];
    var cursor = 0;
    for (final cluster in text.characters) {
      cursor += cluster.length;
      clusterEndOffsets.add(cursor);
    }
    if (clusterEndOffsets.isEmpty) return 0;
    var low = 1;
    var high = clusterEndOffsets.length;
    var best = 1;

    if (preferredChars != null && preferredChars > 0) {
      var preferredIndex = clusterEndOffsets.indexOf(preferredChars);
      if (preferredIndex == -1) {
        preferredIndex = 0;
        for (var i = 0; i < clusterEndOffsets.length; i++) {
          if (clusterEndOffsets[i] <= preferredChars) {
            preferredIndex = i;
          } else {
            break;
          }
        }
      }

      final int candidateLowIndex = (preferredIndex - 12).clamp(0, clusterEndOffsets.length - 1);
      final int candidateHighIndex = preferredIndex.clamp(candidateLowIndex, clusterEndOffsets.length - 1);

      final checkOffset = clusterEndOffsets[candidateLowIndex];
      final checkText = text.substring(0, checkOffset);
      _fitPainter.text = TextSpan(text: checkText, style: style);
      _fittingBinarySearchPasses += 1;
      _fitPainter.layout(maxWidth: double.infinity);

      if (_fitPainter.width <= maxWidth) {
        low = candidateLowIndex + 1;
        high = candidateHighIndex + 1;
        best = candidateLowIndex + 1;
      } else {
        high = preferredIndex + 1;
      }
    }

    while (low <= high) {
      final mid = (low + high) >> 1;
      final candidate = text.substring(0, clusterEndOffsets[mid - 1]);
      _fitPainter.text = TextSpan(text: candidate, style: style);
      _fittingBinarySearchPasses += 1;
      _fitPainter.layout(maxWidth: double.infinity);
      if (_fitPainter.width <= maxWidth) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return clusterEndOffsets[best - 1];
  }


  double _measureLineWidth(String text, TextStyle style) {
    if (text.isEmpty) return 0;
    _measurePainter.text = TextSpan(text: text, style: style);
    _widthMeasurePasses += 1;
    _measurePainter.layout(maxWidth: double.infinity);
    return _measurePainter.width;
  }

  List<ReaderV2PageSlice> _paginate({
    required List<ReaderV2TextLine> lines,
    required ReaderV2LayoutSpec spec,
    required ReaderV2Content content,
  }) {
    final contentHeight = spec.contentHeight <= 0 ? 1.0 : spec.contentHeight;
    final viewportHeight =
        spec.viewportSize.height <= 0
            ? contentHeight
            : spec.viewportSize.height;
    if (lines.isEmpty) {
      return <ReaderV2PageSlice>[
        ReaderV2PageSlice(
          chapterIndex: content.chapterIndex,
          pageIndex: 0,
          pageCount: 1,
          startLineIndex: 0,
          endLineIndexExclusive: 0,
          startCharOffset: 0,
          endCharOffset: content.displayText.length,
          localStartY: 0,
          localEndY: contentHeight,
          contentWidth: spec.contentWidth,
          contentHeight: contentHeight,
          viewportHeight: viewportHeight,
          isChapterStart: true,
          isChapterEnd: true,
        ),
      ];
    }

    final ranges = <({int start, int end, double top})>[];
    var startLineIndex = 0;
    var pageStartY = lines.first.top;
    final pageBottomLimit =
        (contentHeight - _pageBottomSafetyPx(spec))
            .clamp(1.0, contentHeight)
            .toDouble();

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final needsNewPage =
          index > startLineIndex &&
          line.bottom - pageStartY > pageBottomLimit + 0.01;
      if (needsNewPage) {
        ranges.add((start: startLineIndex, end: index, top: pageStartY));
        startLineIndex = index;
        pageStartY = line.top;
      }
    }
    ranges.add((start: startLineIndex, end: lines.length, top: pageStartY));

    final pageCount = ranges.length;
    return <ReaderV2PageSlice>[
      for (var pageIndex = 0; pageIndex < ranges.length; pageIndex++)
        _pageFromRange(
          range: ranges[pageIndex],
          pageIndex: pageIndex,
          pageCount: pageCount,
          lines: lines,
          spec: spec,
          content: content,
          contentHeight: contentHeight,
          viewportHeight: viewportHeight,
        ),
    ];
  }

  ReaderV2PageSlice _pageFromRange({
    required ({int start, int end, double top}) range,
    required int pageIndex,
    required int pageCount,
    required List<ReaderV2TextLine> lines,
    required ReaderV2LayoutSpec spec,
    required ReaderV2Content content,
    required double contentHeight,
    required double viewportHeight,
  }) {
    final first = lines[range.start];
    final last = lines[range.end - 1];
    return ReaderV2PageSlice(
      chapterIndex: content.chapterIndex,
      pageIndex: pageIndex,
      pageCount: pageCount,
      startLineIndex: range.start,
      endLineIndexExclusive: range.end,
      startCharOffset: first.startCharOffset,
      endCharOffset: last.endCharOffset,
      localStartY: range.top,
      localEndY: range.top + contentHeight,
      contentWidth: spec.contentWidth,
      contentHeight: contentHeight,
      viewportHeight: viewportHeight,
      isChapterStart: pageIndex == 0,
      isChapterEnd: pageIndex == pageCount - 1,
    );
  }

  double _pageBottomSafetyPx(ReaderV2LayoutSpec spec) {
    final lineHeight = spec.style.fontSize * spec.style.effectiveLineHeight;
    if (!lineHeight.isFinite || lineHeight <= 0) return 2.0;
    return (lineHeight * 0.12).clamp(2.0, 6.0).toDouble();
  }
}

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';

import 'reader_v2_layout.dart';
import 'reader_v2_layout_spec.dart';
import 'reader_v2_typography.dart';

typedef ReaderV2LayoutStatsObserver =
    void Function(ReaderV2LayoutEngineStats stats);

/// 排版進度游標：記錄 [ReaderV2LayoutEngine.layoutStep] 下次該從哪裡繼續排。
/// 不可變，每次 step 都會產生新的游標實例。
class ReaderV2LayoutCursor {
  const ReaderV2LayoutCursor({
    required this.chapterIndex,
    required this.layoutSignature,
    required this.nextParagraphIndex,
    required this.nextParagraphOffset,
    required this.yCursor,
    required this.titleEmitted,
    required this.isComplete,
  });

  factory ReaderV2LayoutCursor.start({
    required ReaderV2Content content,
    required ReaderV2LayoutSpec spec,
  }) {
    return ReaderV2LayoutCursor(
      chapterIndex: content.chapterIndex,
      layoutSignature: spec.layoutSignature,
      nextParagraphIndex: 0,
      nextParagraphOffset: content.bodyStartOffset,
      yCursor: 0.0,
      titleEmitted: false,
      isComplete: false,
    );
  }

  final int chapterIndex;
  final int layoutSignature;
  final int nextParagraphIndex;
  final int nextParagraphOffset;
  final double yCursor;
  final bool titleEmitted;
  final bool isComplete;
}

class ReaderV2LayoutStepResult {
  const ReaderV2LayoutStepResult({required this.layout, required this.cursor});

  final ReaderV2ChapterLayout layout;
  final ReaderV2LayoutCursor cursor;
}

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
  TextPainter? _blockPainter;

  /// 單一段落排版的預算：超過這個累積耗時就在段落邊界讓出一次主執行緒，
  /// 避免超長章節的排版一次性佔滿一整個（或連續多個）frame 造成卡頓。
  /// 短章節通常整章都排不到這個門檻，行為與讓出前完全一致。
  ///
  /// 預算取「半個幀」而非固定值：60Hz 幀預算 16.6ms 下半幀約 8.3ms（與舊
  /// 常數 8ms 一致），120Hz 幀預算只有 8.3ms，固定 8ms 的切片會吃掉整幀，
  /// 滾動中跨章排版必然掉幀，因此改依實際刷新率縮短切片。
  static Duration _layoutYieldBudget() {
    double refreshRate = 60.0;
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isNotEmpty) {
      final reported = views.first.display.refreshRate;
      if (reported.isFinite && reported >= 30.0) refreshRate = reported;
    }
    final halfFrameUs = (1e6 / refreshRate / 2).round();
    return Duration(microseconds: halfFrameUs);
  }

  /// 讓出一次主執行緒。零延遲 timer 只讓出 event loop、不等 vsync——同一個
  /// 幀間隔內可能連跑多片排版切片，把 120Hz 的幀預算吃穿（fling 減速中的
  /// 微頓挫來源）。改成幀感知：動畫進行中（有排程幀或正在幀內）改等
  /// [SchedulerBinding.endOfFrame]，每幀最多一片、且排在該幀完成之後；閒置
  /// 背景排版（無排程幀）與純 Dart 測試（無 binding）維持零延遲讓出，追趕
  /// 速度不變。32ms 保底 timer 讓「幀已排程但永遠不會 pump」的測試環境不會
  /// 卡死。
  static Future<void> _yieldSlice() {
    final binding = _schedulerBindingOrNull();
    if (binding == null ||
        (!binding.hasScheduledFrame &&
            binding.schedulerPhase == SchedulerPhase.idle)) {
      return Future<void>.delayed(Duration.zero);
    }
    final completer = Completer<void>();
    final fallback = Timer(const Duration(milliseconds: 32), () {
      if (!completer.isCompleted) completer.complete();
    });
    binding.endOfFrame.then((_) {
      fallback.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  static SchedulerBinding? _schedulerBindingOrNull() {
    try {
      return SchedulerBinding.instance;
    } catch (_) {
      // 純 Dart 測試沒有初始化 binding。
      return null;
    }
  }

  bool _isEnglishLetter(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  /// 排完整章才回傳，行為與輸出結果與改動前完全相同。內部用
  /// [layoutStep] 迴圈跑到 `isComplete`，供不需要局部提早回傳的呼叫者
  /// （例如 TTS 取整章文字）使用。
  Future<ReaderV2ChapterLayout> layout(
    ReaderV2Content content,
    ReaderV2LayoutSpec spec,
  ) async {
    var lines = const <ReaderV2TextLine>[];
    ReaderV2LayoutCursor? cursor;
    ReaderV2ChapterLayout layout;
    while (true) {
      final step = await layoutStep(
        content: content,
        spec: spec,
        linesSoFar: lines,
        cursor: cursor,
        minNewExtentPx: double.infinity,
      );
      lines = step.layout.lines;
      cursor = step.cursor;
      layout = step.layout;
      if (cursor.isComplete) break;
    }
    return layout;
  }

  /// 只排出「至少 [minNewExtentPx] 新內容」或排到章節結尾就回傳，不必一次
  /// 排完整章。從 [cursor] 續跑（null 代表從頭開始），回傳的
  /// [ReaderV2LayoutStepResult.layout] 是「[linesSoFar] + 本次新排出的行」
  /// 這個累積快照，[ReaderV2LayoutStepResult.cursor] 記錄下次要從哪裡繼續。
  ///
  /// 單一段落過長時仍套用既有的 8ms yield 安全網，避免單一 step 內部就把
  /// 主執行緒佔滿。
  Future<ReaderV2LayoutStepResult> layoutStep({
    required ReaderV2Content content,
    required ReaderV2LayoutSpec spec,
    List<ReaderV2TextLine> linesSoFar = const <ReaderV2TextLine>[],
    ReaderV2LayoutCursor? cursor,
    required double minNewExtentPx,
  }) async {
    final effectiveCursor =
        cursor ?? ReaderV2LayoutCursor.start(content: content, spec: spec);
    if (effectiveCursor.isComplete) {
      return ReaderV2LayoutStepResult(
        layout: _snapshotLayout(
          content: content,
          spec: spec,
          lines: linesSoFar,
          isComplete: true,
        ),
        cursor: effectiveCursor,
      );
    }

    _resetStats();
    final stopwatch = Stopwatch()..start();
    final lines = List<ReaderV2TextLine>.of(linesSoFar);
    var y = effectiveCursor.yCursor;
    var titleEmitted = effectiveCursor.titleEmitted;

    if (!titleEmitted && content.title.isNotEmpty) {
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
    titleEmitted = true;

    var paragraphIndex = effectiveCursor.nextParagraphIndex;
    var paragraphOffset = effectiveCursor.nextParagraphOffset;
    var newExtent = 0.0;
    var elapsedSinceYield = stopwatch.elapsed;
    final yieldBudget = _layoutYieldBudget();

    while (paragraphIndex < content.paragraphs.length) {
      final paragraph = content.paragraphs[paragraphIndex];
      final beforeY = y;
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
      newExtent += y - beforeY;
      paragraphOffset += paragraph.length + 2;
      paragraphIndex += 1;

      if (paragraphIndex >= content.paragraphs.length) break;
      if (newExtent >= minNewExtentPx) break;

      if (stopwatch.elapsed - elapsedSinceYield >= yieldBudget) {
        await _yieldSlice();
        elapsedSinceYield = stopwatch.elapsed;
      }
    }

    final isComplete = paragraphIndex >= content.paragraphs.length;
    final nextCursor = ReaderV2LayoutCursor(
      chapterIndex: content.chapterIndex,
      layoutSignature: spec.layoutSignature,
      nextParagraphIndex: paragraphIndex,
      nextParagraphOffset: paragraphOffset,
      yCursor: y,
      titleEmitted: titleEmitted,
      isComplete: isComplete,
    );
    final layoutResult = _snapshotLayout(
      content: content,
      spec: spec,
      lines: lines,
      isComplete: isComplete,
    );
    _publishStats(
      chapterIndex: content.chapterIndex,
      elapsed: stopwatch.elapsed,
      lineCount: layoutResult.lines.length,
      pageCount: layoutResult.pages.length,
    );
    return ReaderV2LayoutStepResult(layout: layoutResult, cursor: nextCursor);
  }

  ReaderV2ChapterLayout _snapshotLayout({
    required ReaderV2Content content,
    required ReaderV2LayoutSpec spec,
    required List<ReaderV2TextLine> lines,
    required bool isComplete,
  }) {
    final pages = _paginate(
      lines: lines,
      spec: spec,
      content: content,
      isComplete: isComplete,
    );
    return ReaderV2ChapterLayout(
      chapterIndex: content.chapterIndex,
      displayText: content.displayText,
      contentHash: content.contentHash,
      layoutSignature: spec.layoutSignature,
      lines: List<ReaderV2TextLine>.unmodifiable(lines),
      pages: List<ReaderV2PageSlice>.unmodifiable(pages),
      contentHeight: lines.isEmpty ? 0.0 : lines.last.bottom,
      isComplete: isComplete,
    );
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
      fontFamily: kReaderV2PunctFontFamily,
      fontSize: spec.style.fontSize,
      height: spec.style.effectiveLineHeight,
      letterSpacing: spec.style.letterSpacing,
      fontWeight: spec.style.bold ? FontWeight.bold : FontWeight.normal,
      fontFeatures: kReaderV2CjkFontFeatures,
    );
  }

  TextStyle _titleTextStyle(ReaderV2LayoutSpec spec) {
    return TextStyle(
      fontFamily: kReaderV2PunctFontFamily,
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
    _blockPainter ??= TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: null,
    );
    final painter = _blockPainter!;
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
      // C7: 避免英文單字被從中切斷
      if (charsConsumed > 0 && charsConsumed < remaining.length) {
        final lastChar = remaining.substring(charsConsumed - 1, charsConsumed);
        final nextChar = remaining.substring(charsConsumed, charsConsumed + 1);
        if (_isEnglishLetter(lastChar) && _isEnglishLetter(nextChar)) {
          var temp = charsConsumed;
          while (temp > 0 &&
              _isEnglishLetter(remaining.substring(temp - 1, temp))) {
            temp--;
          }
          if (temp > 0) {
            charsConsumed = temp;
          }
        }
      }
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

      final int candidateLowIndex = (preferredIndex - 12).clamp(
        0,
        clusterEndOffsets.length - 1,
      );
      final int candidateHighIndex = preferredIndex.clamp(
        candidateLowIndex,
        clusterEndOffsets.length - 1,
      );

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
    required bool isComplete,
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
          isChapterEnd: isComplete,
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
          // 尾頁只有在整章真的排完時才算章節結尾；部分結果的尾頁只是
          // 「目前排到這裡」，後面還會再長出新頁。
          isChapterEnd: pageIndex == pageCount - 1 ? isComplete : false,
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
    required bool isChapterEnd,
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
      isChapterEnd: isChapterEnd,
    );
  }

  double _pageBottomSafetyPx(ReaderV2LayoutSpec spec) {
    final lineHeight = spec.style.fontSize * spec.style.effectiveLineHeight;
    if (!lineHeight.isFinite || lineHeight <= 0) return 2.0;
    return (lineHeight * 0.12).clamp(2.0, 6.0).toDouble();
  }
}

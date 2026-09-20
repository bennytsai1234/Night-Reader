import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/scheduler.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';

import '../layout/reader_paragraph_layout.dart';
import '../layout/visual_line_layout_engine.dart';
import 'budget_governor.dart';
import 'layout_cost_model.dart';

final class LayoutPump implements HybridLayoutPump {
  @visibleForTesting
  static void Function()? debugOnIntermediateParagraphDisposed;

  static const double lastLineLetterSpacingCap = 2.0;
  static const double _minBlockHeight = 1e-6;
  static const ReaderParagraphLayout _paragraphLayout =
      ReaderParagraphLayout();
  static const VisualLineLayoutEngine _lineLayoutEngine =
      VisualLineLayoutEngine(paragraphLayout: _paragraphLayout);

  @Deprecated('Typography measurement belongs to ReaderParagraphLayout.')
  static double? measureCellWidth({
    required double fontSize,
    required double letterSpacing,
    required bool bold,
  }) => _paragraphLayout.measureCellWidth(
    fontSize: fontSize,
    letterSpacing: letterSpacing,
    bold: bold,
  );

  LayoutPump({
    required ParagraphCache paragraphCache,
    required HybridMeasurementStore measurementStore,
    required MeasurementNamespace namespace,
    BudgetGovernor? governor,
    LayoutCostModel? costModel,
  }) : _paragraphCache = paragraphCache,
       _measurementStore = measurementStore,
       _namespace = namespace,
       _governor = governor ?? BudgetGovernor(),
       _costModel = costModel ?? LayoutCostModel();

  final ParagraphCache _paragraphCache;
  final HybridMeasurementStore _measurementStore;
  final MeasurementNamespace _namespace;
  final BudgetGovernor _governor;
  final LayoutCostModel _costModel;
  final Queue<_PumpWork> _queue = Queue<_PumpWork>();
  final StreamController<BlockReady> _completed =
      StreamController<BlockReady>.broadcast(sync: true);
  PumpState _state = PumpState.idle;
  ({int first, int last})? _demand;
  int? _scheduledFrame;
  int _spentThisFrame = 0;
  int _discardedWorkCount = 0;
  bool _draining = false;
  bool _disposed = false;

  int get queueDepth => _queue.length;
  int get discardedWorkCount => _discardedWorkCount;
  int get frameWorkMicros => _spentThisFrame;
  int maxCharsForBudget(Duration budget) => _costModel.maxCharsFor(budget);

  @override
  Stream<BlockReady> get completed => _completed.stream;

  /// Demand belongs to this pump instance. Queued probes and drawable layout
  /// are revoked together, even when navigation does not change layout epoch.
  void setDemandRange(int first, int last) {
    if (_demand == (first: first, last: last)) return;
    _demand = (first: first, last: last);
    _removeWhere((work) => !_wantsChapter(work.chapter));
  }

  bool _wantsChapter(int chapter) {
    final demand = _demand;
    return demand == null ||
        (chapter >= demand.first && chapter <= demand.last);
  }

  void _removeWhere(bool Function(_PumpWork) remove) {
    final removed = _queue.where(remove).toList(growable: false);
    _queue.removeWhere(remove);
    for (final work in removed) {
      _discardedWorkCount += 1;
      work.cancel();
    }
    if (_queue.isEmpty && _scheduledFrame != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_scheduledFrame!);
      _scheduledFrame = null;
    }
  }

  void invalidateChapter(int chapterIndex) =>
      _removeWhere((work) => work.chapter == chapterIndex);

  /// A new navigation transaction replaces speculative drawable requests.
  /// Valid chapter preparation can be reused; no screen-side pending ledger
  /// needs a discard callback to roll it back.
  void clearPendingLayouts() => _removeWhere((work) => work is _LayoutWork);

  Future<ChapterBlocks?> planChapterVisualLines(
    ChapterBlocks source, {
    required int maxBlockChars,
    required HybridBlockTextStyle bodyStyle,
    required HybridBlockTextStyle titleStyle,
    required double contentWidth,
    required double? cellWidth,
    required int textIndent,
    LayoutTaskPriority priority = LayoutTaskPriority.visible,
  }) {
    if (_disposed || !_wantsChapter(source.chapterIndex)) {
      return Future<ChapterBlocks?>.value();
    }
    for (final work in _queue.whereType<_ChapterWork>()) {
      if (work.chapter == source.chapterIndex &&
          work.sourceIdentity == source.layoutIdentity) {
        return work.result.future;
      }
    }
    invalidateChapter(source.chapterIndex);
    final work = _ChapterWork(
      source.chapterIndex,
      priority.index,
      source.layoutIdentity,
      _alignmentSteps(
        source,
        maxBlockChars: math.max(1, maxBlockChars),
        bodyStyle: bodyStyle,
        titleStyle: titleStyle,
        contentWidth: contentWidth,
        cellWidth: cellWidth,
        textIndent: textIndent,
      ).iterator,
    );
    _queue.add(work);
    _scheduleFrame();
    return work.result.future;
  }

  @Deprecated('Use planChapterVisualLines; line breaks are reader-owned.')
  Future<ChapterBlocks?> alignChapterBlocksToVisualLines(
    ChapterBlocks source, {
    required int maxBlockChars,
    required HybridBlockTextStyle bodyStyle,
    required double contentWidth,
    required double? cellWidth,
    required int textIndent,
    LayoutTaskPriority priority = LayoutTaskPriority.visible,
  }) => planChapterVisualLines(
    source,
    maxBlockChars: maxBlockChars,
    bodyStyle: bodyStyle,
    titleStyle: bodyStyle,
    contentWidth: contentWidth,
    cellWidth: cellWidth,
    textIndent: textIndent,
    priority: priority,
  );

  @override
  void submit(LayoutTask task) {
    if (_disposed ||
        !_wantsChapter(task.block.chapterIndex) ||
        task.epoch != _namespace.epoch ||
        task.fingerprint != _namespace.fingerprint)
      return;
    for (final work in _queue.whereType<_LayoutWork>()) {
      if (work.task.block.key == task.block.key) {
        work.task = task;
        return;
      }
    }
    _queue.add(_LayoutWork(task));
    _scheduleFrame();
  }

  @override
  void onScrollStateChanged(PumpState state) {
    _state = state;
    // A gesture changes scheduling priority/budget, not content identity.
    _scheduleFrame();
  }

  void _scheduleFrame() {
    if (_disposed || _queue.isEmpty || _scheduledFrame != null) return;
    _scheduledFrame = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _scheduledFrame = null;
      if (_disposed) return;
      _spentThisFrame = 0;
      _drain();
      _scheduleFrame();
    });
  }

  /// Manual consumers share exactly the same frame credit as scheduled work.
  /// Awaiting this Future cannot mint another budget in the microtask queue.
  Future<int> pumpPending() async {
    final completed = _drain();
    _scheduleFrame();
    return completed;
  }

  int _drain() {
    if (_disposed || _draining) return 0;
    _draining = true;
    var completed = 0;
    try {
      final budget = _governor.frameBudgetMicros(_state);
      while (!_disposed && _queue.isNotEmpty && _spentThisFrame < budget) {
        final work = _queue.reduce((a, b) => a.priority <= b.priority ? a : b);
        final predicted = work is _LayoutWork
            ? _costModel.predict(work.task).inMicroseconds
            : _governor.ballisticSliceBudget.inMicroseconds;
        if (_spentThisFrame > 0 && _spentThisFrame + predicted > budget) break;
        _queue.remove(work);
        final watch = Stopwatch()..start();
        bool done;
        try {
          done = work.step(this);
        } catch (error, stack) {
          work.fail(error, stack);
          rethrow;
        } finally {
          final elapsed = watch.elapsed;
          _spentThisFrame += math.max(1, elapsed.inMicroseconds);
          _governor.recordPumpWork(elapsed);
        }
        if (done) {
          completed += 1;
        } else if (!_disposed && _wantsChapter(work.chapter)) {
          _queue.add(work);
        } else {
          work.cancel();
        }
      }
    } finally {
      _draining = false;
    }
    return completed;
  }

  void _layoutTask(LayoutTask task) {
    final started = Stopwatch()..start();
    final layoutPasses = _costModel.layoutPassesFor(task);
    final paragraph = _buildParagraph(task);
    final groupBlocks = task.groupBlocks;
    final splitYs = _groupSplitYs(task, paragraph);
    final metricsList = _metricsFromSplitYs(task, paragraph, splitYs);
    final keys = <BlockKey>[for (final block in groupBlocks) block.key];
    _paragraphCache.putGroup(
      keys,
      splitYs.sublist(0, groupBlocks.length),
      task.epoch,
      paragraph,
      bakedColor: task.textColor,
    );
    for (var i = 0; i < keys.length; i += 1) {
      _measurementStore.put(_namespace, keys[i], metricsList[i]);
    }
    final elapsed = started.elapsed;
    _costModel.record(
      charCount: task.layoutText.length,
      elapsed: elapsed,
      layoutPasses: layoutPasses,
    );
    for (var i = 0; i < keys.length; i += 1) {
      _completed.add(
        BlockReady(key: keys[i], epoch: task.epoch, metrics: metricsList[i]),
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _removeWhere((_) => true);
    unawaited(_completed.close());
  }

  void _disposeIntermediateParagraph(ui.Paragraph paragraph) {
    paragraph.dispose();
    debugOnIntermediateParagraphDisposed?.call();
  }

  Iterable<ChapterBlocks?> _alignmentSteps(
    ChapterBlocks source, {
    required int maxBlockChars,
    required HybridBlockTextStyle bodyStyle,
    required HybridBlockTextStyle titleStyle,
    required double contentWidth,
    required double? cellWidth,
    required int textIndent,
  }) sync* {
    final result = <ChapterBlock>[];
    var blockIndex = 0;

    for (final semanticGroup in source.paragraphGroups()) {
      final head = semanticGroup.first;
      final text = semanticGroup.map((block) => block.text).join();
      final groupStart = semanticGroup.first.charRange.start;
      final textStyle = head.isTitle ? titleStyle : bodyStyle;

      if (text.isEmpty) {
        result.add(
          ChapterBlock(
            key: BlockKey(
              chapterIndex: source.chapterIndex,
              blockIndex: blockIndex++,
            ),
            text: text,
            charRange: HybridTextRange(groupStart, groupStart),
            sourceParagraphIndex: head.sourceParagraphIndex,
            isTitle: head.isTitle,
            isContinuation: head.isContinuation,
            layoutBreakBefore: head.layoutBreakBefore,
          ),
        );
        yield null;
        continue;
      }

      var cursor = 0;
      var transactionIndex = 0;
      while (cursor < text.length) {
        final indentChars =
            head.isTitle || head.isContinuation || transactionIndex > 0
            ? 0
            : textIndent;
        final plan = _lineLayoutEngine.planBlock(
          text: text,
          start: cursor,
          maxBlockChars: maxBlockChars,
          textStyle: textStyle,
          contentWidth: contentWidth,
          cellWidth: cellWidth,
          indentChars: indentChars,
        );
        if (plan.end <= cursor || plan.end > text.length) {
          throw StateError(
            'VisualLineLayoutEngine returned a non-advancing transaction.',
          );
        }

        result.add(
          ChapterBlock(
            key: BlockKey(
              chapterIndex: source.chapterIndex,
              blockIndex: blockIndex++,
            ),
            text: text.substring(cursor, plan.end),
            charRange: HybridTextRange(
              groupStart + cursor,
              groupStart + plan.end,
            ),
            sourceParagraphIndex: head.sourceParagraphIndex,
            isTitle: head.isTitle,
            isContinuation: head.isContinuation || transactionIndex > 0,
            layoutBreakBefore:
                head.layoutBreakBefore || transactionIndex > 0,
            visualLineBreakOffsets: plan.visualLineBreakOffsets,
          ),
        );
        cursor = plan.end;
        transactionIndex += 1;
        yield null;
      }
    }

    yield ChapterBlocks(
      chapterIndex: source.chapterIndex,
      title: source.title,
      displayText: source.displayText,
      contentHash: source.contentHash,
      blocks: result,
    );
  }

  int _safeUtf16BoundaryAtOrBefore(String text, int offset) {
    final safe = offset.clamp(0, text.length).toInt();
    if (safe <= 0 || safe >= text.length) return safe;
    final previous = text.codeUnitAt(safe - 1);
    final next = text.codeUnitAt(safe);
    final splitsSurrogatePair =
        previous >= 0xD800 &&
        previous <= 0xDBFF &&
        next >= 0xDC00 &&
        next <= 0xDFFF;
    return splitsSurrogatePair ? safe - 1 : safe;
  }

  ui.Paragraph _buildParagraph(LayoutTask task) {
    if (!LayoutCostModel.mayCompensateLastLine(task)) {
      return _buildParagraphWithLetterSpacing(
        task,
        extraLetterSpacing: 0,
        textAlignOverride: task.textStyle.textAlign,
      );
    }

    final paragraph = _buildParagraphWithLetterSpacing(
      task,
      extraLetterSpacing: 0,
      textAlignOverride: ui.TextAlign.start,
    );

    try {
      final lines = paragraph.computeLineMetrics();
      if (lines.length < 2) {
        return _buildParagraphWithLetterSpacing(
          task,
          extraLetterSpacing: 0,
          textAlignOverride: task.textStyle.textAlign,
        );
      }
      final lastLineIndex = lines.lastIndexWhere((line) => line.hardBreak);
      if (lastLineIndex <= 0) {
        return _buildParagraphWithLetterSpacing(
          task,
          extraLetterSpacing: 0,
          textAlignOverride: task.textStyle.textAlign,
        );
      }
      final indent = _indentFor(task);
      final renderedText = '$indent${task.layoutText}';
      final textLength = renderedText.length;
      final lineRanges = _lineRanges(paragraph, textLength, lines.length);
      if (lineRanges.length <= lastLineIndex) {
        return _buildParagraphWithLetterSpacing(
          task,
          extraLetterSpacing: 0,
          textAlignOverride: task.textStyle.textAlign,
        );
      }

      final extraLetterSpacing = _averageJustifyExpansion(
        paragraph,
        lines,
        lineRanges,
        renderedText,
        lastLineIndex,
        task,
      );
      if (extraLetterSpacing <= 0) {
        return _buildParagraphWithLetterSpacing(
          task,
          extraLetterSpacing: 0,
          textAlignOverride: task.textStyle.textAlign,
        );
      }

      final lastLine = lineRanges[lastLineIndex];
      final lastLineBoxes = _boxesForTextClusters(
        paragraph,
        renderedText,
        lastLine,
      );
      final lastLineGaps = lastLineBoxes.length - 1;
      if (lastLineGaps <= 0) {
        return _buildParagraphWithLetterSpacing(
          task,
          extraLetterSpacing: 0,
          textAlignOverride: task.textStyle.textAlign,
        );
      }
      final lastLineHeadroom =
          (task.contentWidth - lines[lastLineIndex].width) /
          lastLineBoxes.length.toDouble();
      final safeExtraLetterSpacing = extraLetterSpacing
          .clamp(0.0, lastLineHeadroom > 0 ? lastLineHeadroom : 0.0)
          .toDouble();
      if (safeExtraLetterSpacing <= 0) {
        return _buildParagraphWithLetterSpacing(
          task,
          extraLetterSpacing: 0,
          textAlignOverride: task.textStyle.textAlign,
        );
      }
      final start = lastLine.start.clamp(indent.length, textLength).toInt();
      final end = lastLine.end.clamp(start, textLength).toInt();
      if (end <= start) {
        return _buildParagraphWithLetterSpacing(
          task,
          extraLetterSpacing: 0,
          textAlignOverride: task.textStyle.textAlign,
        );
      }

      return _buildParagraphWithLetterSpacing(
        task,
        extraLetterSpacing: safeExtraLetterSpacing,
        extraStart: start,
        extraEnd: end,
        textAlignOverride: task.textStyle.textAlign,
      );
    } finally {
      _disposeIntermediateParagraph(paragraph);
    }
  }

  double _visibleParagraphBottom(LayoutTask task, ui.Paragraph paragraph) {
    if (task.trailingLayoutLookahead.isEmpty) return paragraph.height;
    final indentLength = _indentFor(task).length;
    final semanticEnd = indentLength + task.combinedText.length;
    final lookaheadLineNumber = paragraph.getLineNumberAt(semanticEnd);
    final lookaheadLine = lookaheadLineNumber == null
        ? null
        : paragraph.getLineMetricsAt(lookaheadLineNumber);
    final lookaheadLineTop = lookaheadLine == null
        ? null
        : lookaheadLine.baseline - lookaheadLine.ascent;
    assert(
      lookaheadLineTop != null && lookaheadLineTop > 0,
      'A visual-segment lookahead must begin on the following visual line.',
    );
    return lookaheadLineTop != null && lookaheadLineTop > 0
        ? lookaheadLineTop
        : paragraph.height;
  }

  List<double> _groupSplitYs(LayoutTask task, ui.Paragraph paragraph) {
    final blocks = task.groupBlocks;
    final ys = <double>[0.0];
    final indentLength = _indentFor(task).length;
    final semanticTextLength = indentLength + task.combinedText.length;
    if (blocks.length > 1) {
      final groupStart = blocks.first.charRange.start;
      for (var i = 1; i < blocks.length; i += 1) {
        final localOffset =
            indentLength + (blocks[i].charRange.start - groupStart);
        final top =
            _lineTopForOffset(paragraph, localOffset, semanticTextLength) ??
            ys.last;
        ys.add(math.max(ys.last, top));
      }
    }
    final visibleBottom = _visibleParagraphBottom(task, paragraph);
    ys.add(math.max(ys.last, visibleBottom));
    return ys;
  }

  List<BlockMetrics> _metricsFromSplitYs(
    LayoutTask task,
    ui.Paragraph paragraph,
    List<double> splitYs,
  ) {
    final blocks = task.groupBlocks;
    List<double>? lineTops;
    final needsExplicitLineCount =
        blocks.length > 1 || task.trailingLayoutLookahead.isNotEmpty;
    final result = <BlockMetrics>[];
    for (var i = 0; i < blocks.length; i += 1) {
      final top = splitYs[i];
      final bottom = splitYs[i + 1];
      final isLast = i == blocks.length - 1;
      final ownHeight = math.max(0.0, bottom - top);
      final height = isLast ? ownHeight + task.trailingSpacing : ownHeight;
      final int lineCount;
      if (!needsExplicitLineCount) {
        lineCount = paragraph.numberOfLines;
      } else {
        lineTops ??= [
          for (final line in paragraph.computeLineMetrics())
            line.baseline - line.ascent,
        ];
        lineCount = lineTops
            .where((t) => t >= top - 0.01 && t < bottom - 0.01)
            .length;
      }
      result.add(
        BlockMetrics(
          height: height <= 0 ? _minBlockHeight : height,
          lineCount: lineCount,
        ),
      );
    }
    return result;
  }

  double? _lineTopForOffset(
    ui.Paragraph paragraph,
    int offset,
    int textLength,
  ) {
    if (textLength <= 0) return 0.0;
    final safeOffset = offset.clamp(0, textLength).toInt();
    final start = safeOffset >= textLength ? textLength - 1 : safeOffset;
    var boxes = paragraph.getBoxesForRange(start, start + 1);
    if (boxes.isEmpty && start + 1 < textLength) {
      boxes = paragraph.getBoxesForRange(
        start,
        math.min(textLength, start + 2),
      );
    }
    if (boxes.isEmpty) return null;
    return boxes.first.top;
  }

  double _averageJustifyExpansion(
    ui.Paragraph paragraph,
    List<ui.LineMetrics> lines,
    List<ui.TextRange> lineRanges,
    String renderedText,
    int lastLineIndex,
    LayoutTask task,
  ) {
    final expansions = <double>[];
    for (var index = 0; index < lastLineIndex; index += 1) {
      if (lines[index].hardBreak) continue;
      final line = lineRanges[index];
      final boxes = _boxesForTextClusters(paragraph, renderedText, line);
      final gaps = boxes.length - 1;
      if (gaps <= 0) continue;

      final expansion =
          (task.contentWidth - lines[index].width) / gaps.toDouble();
      if (expansion.isFinite && expansion > 0) {
        expansions.add(expansion);
      }
    }
    if (expansions.isEmpty) return 0;
    final average =
        expansions.reduce((total, value) => total + value) / expansions.length;
    return average.clamp(0.0, lastLineLetterSpacingCap).toDouble();
  }

  List<ui.TextBox> _boxesForTextClusters(
    ui.Paragraph paragraph,
    String renderedText,
    ui.TextRange range,
  ) {
    final boxes = <ui.TextBox>[];
    var offset = range.start;
    while (offset < range.end) {
      final codeUnit = renderedText.codeUnitAt(offset);
      final isHighSurrogate = codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
      final clusterEnd = (offset + (isHighSurrogate ? 2 : 1))
          .clamp(0, range.end)
          .toInt();
      if (clusterEnd <= offset) break;
      boxes.addAll(paragraph.getBoxesForRange(offset, clusterEnd));
      offset = clusterEnd;
    }
    return boxes;
  }

  List<ui.TextRange> _lineRanges(
    ui.Paragraph paragraph,
    int textLength,
    int lineCount,
  ) {
    final ranges = <ui.TextRange>[];
    var offset = 0;
    while (ranges.length < lineCount && offset < textLength) {
      final range = paragraph.getLineBoundary(
        ui.TextPosition(offset: offset, affinity: ui.TextAffinity.downstream),
      );
      if (!range.isValid || range.end <= offset) break;
      ranges.add(range);
      if (range.end >= textLength) break;
      offset = range.end;
    }
    return ranges;
  }

  ui.Paragraph _buildParagraphWithLetterSpacing(
    LayoutTask task, {
    required double extraLetterSpacing,
    int? extraStart,
    int? extraEnd,
    required ui.TextAlign textAlignOverride,
  }) {
    final paragraphStyle = ui.ParagraphStyle(
      textAlign: textAlignOverride,
      textDirection: ui.TextDirection.ltr,
      fontSize: task.textStyle.fontSize,
      height: task.textStyle.lineHeight,
    );
    final indentLength = _indentFor(task).length;
    final body = task.layoutText;
    final textLength = indentLength + body.length;
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(_textStyle(task));
    final indentCellWidth = task.cellWidth ?? task.textStyle.fontSize;
    for (var i = 0; i < indentLength; i += 1) {
      builder.addPlaceholder(
        indentCellWidth,
        task.textStyle.fontSize,
        ui.PlaceholderAlignment.bottom,
      );
    }
    final start = extraStart?.clamp(indentLength, textLength).toInt();
    final end = extraEnd?.clamp(start ?? indentLength, textLength).toInt();
    if (extraLetterSpacing > 0 && start != null && end != null && end > start) {
      final bodyStart = start - indentLength;
      final bodyEnd = end - indentLength;
      if (bodyStart > 0) builder.addText(body.substring(0, bodyStart));
      builder
        ..pushStyle(
          _textStyle(
            task,
            letterSpacing: task.textStyle.letterSpacing + extraLetterSpacing,
          ),
        )
        ..addText(body.substring(bodyStart, bodyEnd))
        ..pop();
      if (bodyEnd < body.length) builder.addText(body.substring(bodyEnd));
    } else {
      builder.addText(body);
    }
    return builder.build()
      ..layout(ui.ParagraphConstraints(width: task.contentWidth));
  }

  String _indentFor(LayoutTask task) {
    return task.indentChars <= 0 ? '' : '　' * task.indentChars.clamp(0, 8);
  }

  ui.TextStyle _textStyle(LayoutTask task, {double? letterSpacing}) {
    return ui.TextStyle(
      color: task.textColor,
      fontSize: task.textStyle.fontSize,
      height: task.textStyle.lineHeight,
      letterSpacing: letterSpacing ?? task.textStyle.letterSpacing,
      fontWeight: task.textStyle.bold
          ? ui.FontWeight.bold
          : ui.FontWeight.normal,
      fontFeatures: kReaderV2CjkFontFeatures,
    );
  }
}

sealed class _PumpWork {
  int get chapter;
  int get priority;
  bool step(LayoutPump pump);
  void cancel() {}
  void fail(Object error, StackTrace stack) {}
}

final class _LayoutWork extends _PumpWork {
  _LayoutWork(this.task);
  LayoutTask task;
  @override
  int get chapter => task.block.chapterIndex;
  @override
  int get priority => task.priority.index;
  @override
  bool step(LayoutPump pump) {
    pump._layoutTask(task);
    return true;
  }
}

final class _ChapterWork extends _PumpWork {
  _ChapterWork(this.chapter, this.priority, this.sourceIdentity, this.steps);
  @override
  final int chapter;
  @override
  final int priority;
  final String sourceIdentity;
  final Iterator<ChapterBlocks?> steps;
  final Completer<ChapterBlocks?> result = Completer<ChapterBlocks?>();
  @override
  bool step(LayoutPump pump) {
    if (!steps.moveNext()) {
      if (!result.isCompleted) result.complete();
      return true;
    }
    final value = steps.current;
    if (value == null) return false;
    result.complete(value);
    return true;
  }

  @override
  void cancel() {
    if (!result.isCompleted) result.complete();
  }

  @override
  void fail(Object error, StackTrace stack) {
    if (!result.isCompleted) result.completeError(error, stack);
  }
}

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

import 'budget_governor.dart';
import 'layout_cost_model.dart';

final class LayoutPumpTaskStats {
  const LayoutPumpTaskStats({
    required this.elapsed,
    required this.predicted,
    required this.charCount,
    required this.groupBlockCount,
    required this.layoutPasses,
    required this.state,
  });

  final Duration elapsed;
  final Duration predicted;
  final int charCount;
  final int groupBlockCount;
  final double layoutPasses;
  final PumpState state;
}

final class LayoutPump implements HybridLayoutPump {
  @visibleForTesting
  static void Function()? debugOnIntermediateParagraphDisposed;

  static const double lastLineLetterSpacingCap = 2.0;
  static const double _minBlockHeight = 1e-6;
  static final Map<String, double> _cellWidthCache = <String, double>{};

  static double? measureCellWidth({
    required double fontSize,
    required double letterSpacing,
    required bool bold,
  }) {
    if (!fontSize.isFinite || fontSize <= 0) return null;
    if (!letterSpacing.isFinite) return null;
    final key =
        '$fontSize|$letterSpacing|$bold|$kReaderV2CjkTypographyFeatureSignature';
    final cached = _cellWidthCache[key];
    if (cached != null) return cached;
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textDirection: ui.TextDirection.ltr,
              fontSize: fontSize,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              fontSize: fontSize,
              letterSpacing: letterSpacing,
              fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
              fontFeatures: kReaderV2CjkFontFeatures,
            ),
          )
          ..addText('一一');
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: fontSize * 8));
    double? cell;
    final first = paragraph.getBoxesForRange(0, 1);
    final second = paragraph.getBoxesForRange(1, 2);
    if (first.isNotEmpty && second.isNotEmpty) {
      final advance = second.first.left - first.first.left;
      if (advance.isFinite && advance > 0) cell = advance;
    }
    paragraph.dispose();
    if (cell == null) return null;
    _cellWidthCache[key] = cell;
    return cell;
  }

  LayoutPump({
    required ParagraphCache paragraphCache,
    required HybridMeasurementStore measurementStore,
    required MeasurementNamespace namespace,
    BudgetGovernor? governor,
    LayoutCostModel? costModel,
    void Function(LayoutPumpTaskStats stats)? onTaskCompleted,
    bool Function(LayoutTask task)? isTaskStillDesired,
    void Function(LayoutTask task)? onTaskDiscarded,
  }) : _paragraphCache = paragraphCache,
       _measurementStore = measurementStore,
       _namespace = namespace,
       _governor = governor ?? BudgetGovernor(),
       _costModel = costModel ?? LayoutCostModel(),
       _onTaskCompleted = onTaskCompleted,
       _isTaskStillDesired = isTaskStillDesired,
       _onTaskDiscarded = onTaskDiscarded;

  final ParagraphCache _paragraphCache;
  final HybridMeasurementStore _measurementStore;
  final MeasurementNamespace _namespace;
  final BudgetGovernor _governor;
  final LayoutCostModel _costModel;
  final void Function(LayoutPumpTaskStats stats)? _onTaskCompleted;

  /// 「這個 task 現在還需要嗎？」——由呼叫端依當前 viewport 需求回答。
  /// 佇列本身只記得「歷史上誰要求過排版」；沒有這個述詞時，跳章後屬於
  /// 舊中心的 task 仍會被完整排版，其 metrics 再也接不上重定中心後的
  /// DocumentIndex（連續性要求，見 AdmissionController._flushPending），
  /// 等於整段排版時間白費並卡住 settle 契約。
  final bool Function(LayoutTask task)? _isTaskStillDesired;

  /// 被 [purgeUndesiredTasks] 丟棄的 task；呼叫端據此回收自己的
  /// 「已投放」記錄，否則同一個 group 之後回到視窗內時無法重新投放。
  final void Function(LayoutTask task)? _onTaskDiscarded;
  final Queue<LayoutTask> _queue = Queue<LayoutTask>();
  final StreamController<BlockReady> _completed =
      StreamController<BlockReady>.broadcast(sync: true);
  PumpState _state = PumpState.idle;
  int _stateRevision = 0;
  bool _disposed = false;

  int get queueDepth => _queue.length;

  int maxCharsForBudget(Duration budget) => _costModel.maxCharsFor(budget);

  /// Converts arbitrary preprocessor chunks into actual layout transactions.
  ///
  /// Preprocessing is allowed to split at UTF-16-safe text boundaries for
  /// scheduling, but those boundaries are not layout boundaries. A long
  /// logical paragraph is measured in bounded probes and is only separated at
  /// visual line starts. This keeps wrapping identical while preventing
  /// `paragraphGroups()` from reconstructing the entire logical paragraph into
  /// one synchronous ui.Paragraph.layout transaction.
  ///
  /// `maxBlockChars` is a target transaction size rather than permission to
  /// split a visual line. If one visual line itself exceeds the target, the
  /// smallest correct transaction is that line; correctness wins over an
  /// artificial code-unit cut.
  Future<ChapterBlocks> alignChapterBlocksToVisualLines(
    ChapterBlocks source, {
    required int maxBlockChars,
    required HybridBlockTextStyle bodyStyle,
    required double contentWidth,
    required double? cellWidth,
    required int textIndent,
  }) async {
    if (_disposed || maxBlockChars <= 0) return source;
    final ownerRevision = _stateRevision;

    void ensureLayoutOwnership() {
      if (_disposed ||
          _state == PumpState.dragging ||
          _stateRevision != ownerRevision) {
        throw StateError('Reader V2 layout ownership changed during segmentation.');
      }
    }

    ensureLayoutOwnership();
    final result = <ChapterBlock>[];
    var blockIndex = 0;
    var frameWork = Stopwatch()..start();

    Future<void> yieldIfBudgetConsumed() async {
      ensureLayoutOwnership();
      final budget = math.max(
        1,
        _governor.frameBudgetMicros(PumpState.rebuilding),
      );
      if (frameWork.elapsedMicroseconds < budget) return;
      _governor.recordPumpWork(frameWork.elapsed);
      SchedulerBinding.instance.ensureVisualUpdate();
      await SchedulerBinding.instance.endOfFrame;
      ensureLayoutOwnership();
      frameWork = Stopwatch()..start();
    }

    for (final semanticGroup in source.paragraphGroups()) {
      ensureLayoutOwnership();
      final head = semanticGroup.first;
      final text = semanticGroup.map((block) => block.text).join();
      final groupStart = semanticGroup.first.charRange.start;
      final groupEnd = semanticGroup.last.charRange.end;
      if (head.isTitle || text.length <= maxBlockChars) {
        result.add(
          ChapterBlock(
            key: BlockKey(
              chapterIndex: source.chapterIndex,
              blockIndex: blockIndex++,
            ),
            text: text,
            charRange: HybridTextRange(groupStart, groupEnd),
            sourceParagraphIndex: head.sourceParagraphIndex,
            isTitle: head.isTitle,
            isContinuation: head.isContinuation,
            layoutBreakBefore: head.layoutBreakBefore,
          ),
        );
        continue;
      }

      final segments = await _visualLineSegments(
        text: text,
        maxBlockChars: maxBlockChars,
        textStyle: bodyStyle,
        contentWidth: contentWidth,
        cellWidth: cellWidth,
        textIndent: head.isContinuation ? 0 : textIndent,
        ensureLayoutOwnership: ensureLayoutOwnership,
        yieldIfBudgetConsumed: yieldIfBudgetConsumed,
      );
      ensureLayoutOwnership();
      for (var index = 0; index < segments.length; index += 1) {
        final segment = segments[index];
        result.add(
          ChapterBlock(
            key: BlockKey(
              chapterIndex: source.chapterIndex,
              blockIndex: blockIndex++,
            ),
            text: text.substring(segment.start, segment.end),
            charRange: HybridTextRange(
              groupStart + segment.start,
              groupStart + segment.end,
            ),
            sourceParagraphIndex: head.sourceParagraphIndex,
            isTitle: false,
            isContinuation: head.isContinuation || index > 0,
            layoutBreakBefore: head.layoutBreakBefore || index > 0,
          ),
        );
      }
    }

    ensureLayoutOwnership();
    _governor.recordPumpWork(frameWork.elapsed);
    return ChapterBlocks(
      chapterIndex: source.chapterIndex,
      title: source.title,
      displayText: source.displayText,
      contentHash: source.contentHash,
      blocks: result,
    );
  }

  Future<List<({int start, int end})>> _visualLineSegments({
    required String text,
    required int maxBlockChars,
    required HybridBlockTextStyle textStyle,
    required double contentWidth,
    required double? cellWidth,
    required int textIndent,
    required void Function() ensureLayoutOwnership,
    required Future<void> Function() yieldIfBudgetConsumed,
  }) async {
    final segments = <({int start, int end})>[];
    final preserveLastLineCompensation =
        _namespace.fingerprint.lastLineSpacingCompensation &&
        textStyle.textAlign == ui.TextAlign.justify;
    var cursor = 0;
    while (cursor < text.length) {
      ensureLayoutOwnership();
      final remaining = text.length - cursor;
      if (remaining <= maxBlockChars) {
        if (preserveLastLineCompensation && segments.isNotEmpty) {
          final candidate = text.substring(cursor);
          final probeBlock = ChapterBlock(
            key: const BlockKey(chapterIndex: 0, blockIndex: 0),
            text: candidate,
            charRange: HybridTextRange(0, candidate.length),
            sourceParagraphIndex: 0,
            isContinuation: true,
            layoutBreakBefore: true,
          );
          final probeTask = LayoutTask(
            block: probeBlock,
            epoch: _namespace.epoch,
            fingerprint: _namespace.fingerprint,
            textStyle: textStyle,
            contentWidth: contentWidth,
            cellWidth: cellWidth,
          );
          final paragraph = _buildParagraphWithLetterSpacing(
            probeTask,
            extraLetterSpacing: 0,
            textAlignOverride: ui.TextAlign.start,
          );
          final tailLineCount = paragraph.numberOfLines;
          paragraph.dispose();
          await yieldIfBudgetConsumed();
          ensureLayoutOwnership();
          if (tailLineCount < 2) {
            final previous = segments.removeLast();
            segments.add((start: previous.start, end: text.length));
            break;
          }
        }
        segments.add((start: cursor, end: text.length));
        break;
      }

      var probeChars = math.min(
        remaining,
        math.max(maxBlockChars + 1, maxBlockChars * 2),
      );
      int? cut;
      while (cut == null) {
        ensureLayoutOwnership();
        final probeEnd = _safeUtf16BoundaryAtOrBefore(
          text,
          math.min(text.length, cursor + probeChars),
        );
        if (probeEnd <= cursor) {
          segments.add((start: cursor, end: text.length));
          return segments;
        }
        final candidate = text.substring(cursor, probeEnd);
        final probeBlock = ChapterBlock(
          key: const BlockKey(chapterIndex: 0, blockIndex: 0),
          text: candidate,
          charRange: HybridTextRange(0, candidate.length),
          sourceParagraphIndex: 0,
          isContinuation: cursor > 0,
          layoutBreakBefore: cursor > 0,
        );
        final probeTask = LayoutTask(
          block: probeBlock,
          epoch: _namespace.epoch,
          fingerprint: _namespace.fingerprint,
          textStyle: textStyle,
          contentWidth: contentWidth,
          cellWidth: cellWidth,
          indentChars: cursor == 0 ? textIndent : 0,
        );
        final paragraph = _buildParagraphWithLetterSpacing(
          probeTask,
          extraLetterSpacing: 0,
          textAlignOverride: ui.TextAlign.start,
        );
        try {
          final indentLength = _indentFor(probeTask).length;
          final lineRanges = _lineRanges(
            paragraph,
            indentLength + candidate.length,
            paragraph.numberOfLines,
          );
          int? preferred;
          int? firstInterior;
          for (final range in lineRanges) {
            final bodyEnd = (range.end - indentLength)
                .clamp(0, candidate.length)
                .toInt();
            if (bodyEnd <= 0 || bodyEnd >= candidate.length) continue;
            firstInterior ??= bodyEnd;
            if (bodyEnd <= maxBlockChars) preferred = bodyEnd;
          }
          cut = preferred ?? firstInterior;
        } finally {
          paragraph.dispose();
        }
        await yieldIfBudgetConsumed();
        ensureLayoutOwnership();
        if (cut != null) break;
        if (probeEnd >= text.length) {
          cut = text.length - cursor;
          break;
        }
        probeChars = math.min(remaining, probeChars + maxBlockChars);
      }

      final end = _safeUtf16BoundaryAtOrBefore(text, cursor + cut);
      if (end <= cursor) {
        segments.add((start: cursor, end: text.length));
        break;
      }
      segments.add((start: cursor, end: end));
      cursor = end;
    }
    return segments;
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

  @override
  Stream<BlockReady> get completed => _completed.stream;

  @override
  void submit(LayoutTask task) {
    if (_disposed) return;
    _queue.removeWhere((queued) => queued.block.key == task.block.key);
    if (task.priority == LayoutTaskPriority.anchor) {
      _queue.addFirst(task);
    } else {
      _queue.add(task);
    }
  }

  void invalidateChapter(int chapterIndex) {
    _queue.removeWhere((task) => task.block.chapterIndex == chapterIndex);
  }

  @override
  void onScrollStateChanged(PumpState state) {
    if (_state == state) return;
    _state = state;
    _stateRevision += 1;
  }

  /// 丟棄已不在當前需求視窗內的 task。純記帳、不做排版，因此在 dragging
  /// 期間呼叫也不違反 I4。回傳丟棄數量。
  int purgeUndesiredTasks() {
    final predicate = _isTaskStillDesired;
    if (predicate == null || _queue.isEmpty) return 0;
    final retained = <LayoutTask>[];
    var discarded = 0;
    for (final task in _queue) {
      if (predicate(task)) {
        retained.add(task);
        continue;
      }
      discarded += 1;
      _onTaskDiscarded?.call(task);
    }
    if (discarded == 0) return 0;
    _queue
      ..clear()
      ..addAll(retained);
    return discarded;
  }

  Future<int> pumpPending() async {
    if (_disposed) return 0;
    // 先讓佇列反映「現在需要什麼」再談預算：queueDepth 是 restore settle
    // 契約的判準之一，帶著陳舊 task 的深度會讓它永遠等不到 0。
    purgeUndesiredTasks();
    if (_state == PumpState.dragging) {
      assert(
        _state != PumpState.dragging,
        'I4: LayoutPump must not layout while dragging.',
      );
      return 0;
    }
    final budgetMicros = _governor.frameBudgetMicros(_state);
    var completed = 0;
    final stopwatch = Stopwatch()..start();
    while (_queue.isNotEmpty && budgetMicros > 0) {
      if (completed > 0) {
        final predicted = _costModel.predict(_peekTask()).inMicroseconds;
        if (stopwatch.elapsedMicroseconds + predicted > budgetMicros) break;
      }
      final task = _nextTask();
      final predicted = _costModel.predict(task);
      final started = Stopwatch()..start();
      final layoutPasses = _costModel.layoutPassesFor(task);
      final paragraph = _buildParagraph(task);
      final groupBlocks = task.groupBlocks;
      final splitYs = _groupSplitYs(task, paragraph);
      final metricsList = _metricsFromSplitYs(task, paragraph, splitYs);
      final keys = <BlockKey>[for (final block in groupBlocks) block.key];
      final localTops = splitYs.sublist(0, groupBlocks.length);
      _paragraphCache.putGroup(
        keys,
        localTops,
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
      _onTaskCompleted?.call(
        LayoutPumpTaskStats(
          elapsed: elapsed,
          predicted: predicted,
          charCount: task.layoutText.length,
          groupBlockCount: groupBlocks.length,
          layoutPasses: layoutPasses,
          state: _state,
        ),
      );
      for (var i = 0; i < keys.length; i += 1) {
        _completed.add(
          BlockReady(key: keys[i], epoch: task.epoch, metrics: metricsList[i]),
        );
      }
      completed += 1;
      if (stopwatch.elapsedMicroseconds >= budgetMicros) break;
    }
    _governor.recordPumpWork(stopwatch.elapsed);
    return completed;
  }

  @override
  void dispose() {
    _disposed = true;
    _stateRevision += 1;
    _queue.clear();
    unawaited(_completed.close());
  }

  void _disposeIntermediateParagraph(ui.Paragraph paragraph) {
    paragraph.dispose();
    debugOnIntermediateParagraphDisposed?.call();
  }

  LayoutTask _peekTask() {
    if (_queue.length <= 1) return _queue.first;
    var best = _queue.first;
    var bestScore = _score(best);
    for (final task in _queue) {
      final score = _score(task);
      if (score < bestScore) {
        bestScore = score;
        best = task;
      }
    }
    return best;
  }

  LayoutTask _nextTask() {
    if (_queue.length <= 1) return _queue.removeFirst();
    var bestIndex = 0;
    var bestScore = _score(_queue.first);
    var index = 0;
    for (final task in _queue) {
      final score = _score(task);
      if (score < bestScore) {
        bestScore = score;
        bestIndex = index;
      }
      index += 1;
    }
    for (var i = 0; i < bestIndex; i += 1) {
      _queue.add(_queue.removeFirst());
    }
    return _queue.removeFirst();
  }

  int _score(LayoutTask task) {
    final priorityScore = switch (task.priority) {
      LayoutTaskPriority.anchor => 0,
      LayoutTaskPriority.visible => 10,
      LayoutTaskPriority.prefetch => 20,
    };
    final directionScore = task.direction == HybridScrollDirection.forward
        ? 0
        : 1;
    return priorityScore + directionScore;
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
      boxes = paragraph.getBoxesForRange(start, math.min(textLength, start + 2));
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

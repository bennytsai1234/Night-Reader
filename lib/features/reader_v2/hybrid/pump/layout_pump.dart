import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';

import 'budget_governor.dart';
import 'layout_cost_model.dart';

final class LayoutPump implements HybridLayoutPump {
  /// 避免短末行因少數字元而被拉得過鬆；單位為 logical pixels。
  static const double lastLineLetterSpacingCap = 2.0;

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
  final Queue<LayoutTask> _queue = Queue<LayoutTask>();
  final StreamController<BlockReady> _completed =
      StreamController<BlockReady>.broadcast(sync: true);
  PumpState _state = PumpState.idle;
  bool _disposed = false;

  int get queueDepth => _queue.length;

  int maxCharsForBudget(Duration budget) => _costModel.maxCharsFor(budget);

  @override
  Stream<BlockReady> get completed => _completed.stream;

  @override
  void submit(LayoutTask task) {
    if (_disposed) return;
    if (task.priority == LayoutTaskPriority.anchor) {
      _queue.addFirst(task);
    } else {
      _queue.add(task);
    }
  }

  @override
  void onScrollStateChanged(PumpState state) {
    _state = state;
  }

  Future<int> pumpPending() async {
    if (_disposed || _state == PumpState.dragging) {
      assert(
        _state != PumpState.dragging,
        'I4: LayoutPump must not layout while dragging.',
      );
      return 0;
    }
    // 預算消費制：governor 給出本幀可用 µs，逐 task 以 cost model 預測
    // 打包；首片只要預算 > 0 就執行（block 已按 ballisticSliceBudget
    // 預先切塊，單片有界；歸零起跑會讓 idle/rebuilding 供給停擺）。
    final budgetMicros = _governor.frameBudgetMicros(_state);
    var completed = 0;
    final stopwatch = Stopwatch()..start();
    while (_queue.isNotEmpty && budgetMicros > 0) {
      if (completed > 0) {
        final predicted = _costModel.predict(_peekTask()).inMicroseconds;
        if (stopwatch.elapsedMicroseconds + predicted > budgetMicros) break;
      }
      final task = _nextTask();
      final started = Stopwatch()..start();
      final layoutPasses = _costModel.layoutPassesFor(task);
      final paragraph = _buildParagraph(task);
      final contentHeight = paragraph.height <= 0 ? 1.0 : paragraph.height;
      final metrics = BlockMetrics(
        height: contentHeight + task.trailingSpacing,
        // numberOfLines 是 O(1) getter；computeLineMetrics 會配置整串
        // LineMetrics，不可進 ballistic 切片。
        lineCount: paragraph.numberOfLines,
      );
      _paragraphCache.put(
        task.key,
        task.epoch,
        paragraph,
        bakedColor: task.textColor,
      );
      _measurementStore.put(_namespace, task.key, metrics);
      _costModel.record(
        charCount: task.block.text.length,
        elapsed: started.elapsed,
        layoutPasses: layoutPasses,
      );
      _completed.add(
        BlockReady(key: task.key, epoch: task.epoch, metrics: metrics),
      );
      completed += 1;
      if (stopwatch.elapsedMicroseconds >= budgetMicros) break;
    }
    _governor.recordPumpWork(stopwatch.elapsed);
    return completed;
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    unawaited(_completed.close());
  }

  /// 與 [_nextTask] 同一套計分的唯讀預覽（平手取先入者，兩者一致）。
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
    final directionScore =
        task.direction == HybridScrollDirection.forward ? 0 : 1;
    return priorityScore + directionScore;
  }

  ui.Paragraph _buildParagraph(LayoutTask task) {
    if (!_shouldCompensateLastLine(task)) {
      return _buildParagraphWithLetterSpacing(
        task,
        extraLetterSpacing: 0,
        textAlignOverride: task.textStyle.textAlign,
      );
    }

    // Flutter 的 LineMetrics 沒有字元索引，而 justify 後的 TextBox 寬度也
    // 可能已包含引擎分配的額外間距。先用 start 建立自然寬度的 Pass 1，
    // 再以同一組斷行範圍建立 justify + 末行補償的 Pass 2；對齊方式不參與
    // 斷行，因此兩個 Paragraph 的 line boundary 相同。
    final paragraph = _buildParagraphWithLetterSpacing(
      task,
      extraLetterSpacing: 0,
      textAlignOverride: ui.TextAlign.start,
    );

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
    final lineRanges = _lineRanges(
      paragraph,
      _indentFor(task).length + task.block.text.length,
      lines.length,
    );
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
      '${_indentFor(task)}${task.block.text}',
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

    final indent = _indentFor(task);
    final textLength = indent.length + task.block.text.length;
    final lastLine = lineRanges[lastLineIndex];
    final renderedText = '$indent${task.block.text}';
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
        lastLineGaps.toDouble();
    final safeExtraLetterSpacing =
        extraLetterSpacing
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

    // Pass 2：只對末行字元範圍增加 letterSpacing，文字與 displayText 完全
    // 不變；因此 TTS range、錨點與 contentHash 仍在同一座標系。
    return _buildParagraphWithLetterSpacing(
      task,
      extraLetterSpacing: safeExtraLetterSpacing,
      extraStart: start,
      extraEnd: end,
      textAlignOverride: task.textStyle.textAlign,
    );
  }

  bool _shouldCompensateLastLine(LayoutTask task) {
    return task.fingerprint.lastLineSpacingCompensation &&
        !task.block.isTitle &&
        !task.block.isContinuation &&
        task.textStyle.textAlign == ui.TextAlign.justify;
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
      final clusterEnd =
          (offset + (isHighSurrogate ? 2 : 1)).clamp(0, range.end).toInt();
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
    final body = task.block.text;
    final textLength = indentLength + body.length;
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(_textStyle(task));
    // 縮排以 placeholder 而非 U+3000 文字送進 Paragraph：justify 會把
    // 行首全形空白視為可分配空白——縮排被壓成 0 寬、其寬度平攤進整行
    // 字距，造成 soft-wrap 行字距異常放大且失去縮排。placeholder 不是
    // 空白字元故不受影響；每個仍佔 1 code unit（U+FFFC），因此
    // charOffset / TTS / 錨點的座標換算與 U+3000 前綴完全相同。
    for (var i = 0; i < indentLength; i += 1) {
      builder.addPlaceholder(
        task.textStyle.fontSize,
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
    final paragraph =
        builder.build()
          ..layout(ui.ParagraphConstraints(width: task.contentWidth));
    return paragraph;
  }

  /// 縮排在座標系上的替身字串：實際 Paragraph 以等量 placeholder 呈現
  /// （見 [_buildParagraphWithLetterSpacing]），此字串只用來計算前綴
  /// 長度與逐字 cluster 邊界，兩者每字元都佔 1 code unit，座標一致。
  String _indentFor(LayoutTask task) {
    return task.indentChars <= 0 ? '' : '　' * task.indentChars.clamp(0, 8);
  }

  ui.TextStyle _textStyle(LayoutTask task, {double? letterSpacing}) {
    return ui.TextStyle(
      color: task.textColor,
      fontSize: task.textStyle.fontSize,
      height: task.textStyle.lineHeight,
      letterSpacing: letterSpacing ?? task.textStyle.letterSpacing,
      fontWeight:
          task.textStyle.bold ? ui.FontWeight.bold : ui.FontWeight.normal,
      fontFeatures: kReaderV2CjkFontFeatures,
    );
  }
}

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/paragraph/paragraph_cache.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';

import 'budget_governor.dart';
import 'layout_cost_model.dart';

/// 一個 LayoutTask 從開始建立 Paragraph 到 metrics 回寫完成的實測資料。
///
/// 這不是功能邏輯的另一條路徑，只是把既有 pump 的同步工作切點暴露給
/// telemetry，讓 120Hz 的 P99 掉幀可以回溯到「哪種 task、多少字、預估錯
/// 多少」，而不是只看到 frame 已經超時。
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

  /// 避免短末行因少數字元而被拉得過鬆；單位為 logical pixels。
  static const double lastLineLetterSpacingCap = 2.0;

  /// group 內多個效能切點同落在同一實體行時，切點之間的 own height 合法
  /// 為 0（該行整行畫在別的切塊視窗裡，見 [_groupSplitYs]）。`BlockMetrics`
  /// 要求 height > 0（sliver extent／admission 需要每個 block 佔據可辨識的
  /// 座標），因此改用遠低於既有幾何測試容差（0.01px）的極小正值頂住，不能
  /// 像過去那樣頂到 1.0px——多個零高度切點疊加會讓整組總高度多出好幾個
  /// 人工像素，使切法之後的世界座標系統性偏移於連續排版。
  static const double _minBlockHeight = 1e-6;

  static final Map<String, double> _cellWidthCache = <String, double>{};

  /// em-grid 鎖寬的 cell 來源：以真實引擎量「一一」兩字的 x 差取得目前
  /// 內文樣式下單一全形字的 advance（含 letterSpacing）。必須與 [_textStyle]
  /// 同一組字型鏈與 fontFeatures，否則鎖出來的格與實排不同步；也因此
  /// 不可用 fontSize + letterSpacing 公式推算（次像素差乘上每列字數會
  /// 累積回漂移）。量測失敗回 null（呼叫端不鎖寬）。
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
      final predicted = _costModel.predict(task);
      final started = Stopwatch()..start();
      final layoutPasses = _costModel.layoutPassesFor(task);
      final paragraph = _buildParagraph(task);
      final groupBlocks = task.groupBlocks;
      // group 內每個效能切塊各自的 Y 窗邊界；單一 block 時等同
      // [0, paragraph.height]。切塊本身從不新增排版單位之外的間距，只有
      // group 真正的最後一塊才計入 trailingSpacing（呼叫端已依此設值）。
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
        charCount: task.combinedText.length,
        elapsed: elapsed,
        layoutPasses: layoutPasses,
      );
      _onTaskCompleted?.call(
        LayoutPumpTaskStats(
          elapsed: elapsed,
          predicted: predicted,
          charCount: task.combinedText.length,
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
    _queue.clear();
    unawaited(_completed.close());
  }

  void _disposeIntermediateParagraph(ui.Paragraph paragraph) {
    paragraph.dispose();
    debugOnIntermediateParagraphDisposed?.call();
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
    final directionScore = task.direction == HybridScrollDirection.forward
        ? 0
        : 1;
    return priorityScore + directionScore;
  }

  ui.Paragraph _buildParagraph(LayoutTask task) {
    // 條件含單行寬度上界估算：必為單行的 block（對白短句為大宗）
    // 不進兩段式路徑，維持單次 layout；與 cost model 的
    // layoutPassesFor 共用同一判斷，成本預測不失準。
    if (!LayoutCostModel.mayCompensateLastLine(task)) {
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
      final lineRanges = _lineRanges(
        paragraph,
        _indentFor(task).length + task.combinedText.length,
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
        '${_indentFor(task)}${task.combinedText}',
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
      final textLength = indent.length + task.combinedText.length;
      final lastLine = lineRanges[lastLineIndex];
      final renderedText = '$indent${task.combinedText}';
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
      // letterSpacing 加在範圍內每個字元之後（含末字），總增量是
      // spacing × 字數而非 × 間隙數；分母若用 gaps，近滿末行會超寬
      // 一個 spacing 而把末字擠到下一行。
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

      // Pass 2：只對末行字元範圍增加 letterSpacing，文字與 displayText 完全
      // 不變；因此 TTS range、錨點與 contentHash 仍在同一座標系。
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

  /// group 內每個效能切塊各自的 Y 窗邊界，長度為
  /// `task.groupBlocks.length + 1`：`ys[i]`/`ys[i+1]` 是第 i 個切塊在
  /// [paragraph] 座標系裡的頂／底。邊界一律落在切塊第一個字元所在行的
  /// 行頂——同一實體行只會整行畫在其中一個切塊的視窗裡，不會被垂直
  /// 切一半。單一 block（非 group）時直接回傳 `[0, paragraph.height]`。
  List<double> _groupSplitYs(LayoutTask task, ui.Paragraph paragraph) {
    final blocks = task.groupBlocks;
    final ys = <double>[0.0];
    if (blocks.length > 1) {
      final indentLength = _indentFor(task).length;
      final groupStart = blocks.first.charRange.start;
      final totalTextLength = indentLength + task.combinedText.length;
      for (var i = 1; i < blocks.length; i += 1) {
        final localOffset =
            indentLength + (blocks[i].charRange.start - groupStart);
        final top =
            _lineTopForOffset(paragraph, localOffset, totalTextLength) ??
            ys.last;
        ys.add(math.max(ys.last, top));
      }
    }
    ys.add(math.max(ys.last, paragraph.height));
    return ys;
  }

  /// 依 [splitYs] 把整個 group 的高度／行數分回每個切塊自己的
  /// [BlockMetrics]；只有 group 真正的最後一塊計入 `task.trailingSpacing`
  /// （呼叫端已依「是否為邏輯段落真正結尾」決定這個值，切塊之間恆為 0）。
  List<BlockMetrics> _metricsFromSplitYs(
    LayoutTask task,
    ui.Paragraph paragraph,
    List<double> splitYs,
  ) {
    final blocks = task.groupBlocks;
    List<double>? lineTops;
    final result = <BlockMetrics>[];
    for (var i = 0; i < blocks.length; i += 1) {
      final top = splitYs[i];
      final bottom = splitYs[i + 1];
      final isLast = i == blocks.length - 1;
      final ownHeight = math.max(0.0, bottom - top);
      final height = isLast ? ownHeight + task.trailingSpacing : ownHeight;
      final int lineCount;
      if (blocks.length == 1) {
        // numberOfLines 是 O(1) getter；computeLineMetrics 會配置整串
        // LineMetrics，單一 block 時不需要，避免多一次配置進 ballistic 切片。
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

  /// 與 [_HybridReaderScreenState._textBoxTopForOffset] 同款幾何：以
  /// `getBoxesForRange` 取單一字元的 box top 作為所在行的行頂，供 group
  /// 內切點的視覺邊界與呼叫端（capture／restore／TTS）共用同一套座標。
  double? _lineTopForOffset(
    ui.Paragraph paragraph,
    int offset,
    int textLength,
  ) {
    if (textLength <= 0) return 0.0;
    final safeOffset = offset.clamp(0, textLength).toInt();
    final start = safeOffset >= textLength ? textLength - 1 : safeOffset;
    final boxes = paragraph.getBoxesForRange(start, start + 1);
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
    final body = task.combinedText;
    final textLength = indentLength + body.length;
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(_textStyle(task));
    // 縮排以 placeholder 而非 U+3000 文字送進 Paragraph：justify 會把
    // 行首全形空白視為可分配空白——縮排被壓成 0 寬、其寬度平攤進整行
    // 字距，造成 soft-wrap 行字距異常放大且失去縮排。placeholder 不是
    // 空白字元故不受影響；每個仍佔 1 code unit（U+FFFC），因此
    // charOffset / TTS / 錨點的座標換算與 U+3000 前綴完全相同。
    // placeholder 寬用鎖寬 cell（= 全形字 advance 含 letterSpacing），
    // 縮排才恰好佔整數格；未鎖寬時退回 fontSize 舊行為。
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
    final paragraph = builder.build()
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
      fontWeight: task.textStyle.bold
          ? ui.FontWeight.bold
          : ui.FontWeight.normal,
      fontFeatures: kReaderV2CjkFontFeatures,
    );
  }
}

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
    final allowed = _governor.allowedSlices(_state);
    var completed = 0;
    while (completed < allowed && _queue.isNotEmpty) {
      final task = _nextTask();
      final started = Stopwatch()..start();
      final paragraph = _buildParagraph(task);
      final contentHeight = paragraph.height <= 0 ? 1.0 : paragraph.height;
      final metrics = BlockMetrics(
        height: contentHeight + task.trailingSpacing,
        lineCount: paragraph.computeLineMetrics().length,
      );
      _paragraphCache.put(task.key, task.epoch, paragraph);
      _measurementStore.put(_namespace, task.key, metrics);
      _costModel.record(
        charCount: task.block.text.length,
        elapsed: started.elapsed,
      );
      _completed.add(
        BlockReady(key: task.key, epoch: task.epoch, metrics: metrics),
      );
      completed += 1;
      if (_state == PumpState.ballistic &&
          started.elapsed > _governor.ballisticSliceBudget) {
        break;
      }
    }
    return completed;
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    unawaited(_completed.close());
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
    final paragraphStyle = ui.ParagraphStyle(
      textAlign: task.textStyle.textAlign,
      textDirection: ui.TextDirection.ltr,
      fontSize: task.textStyle.fontSize,
      height: task.textStyle.lineHeight,
    );
    final indent =
        task.indentChars <= 0 ? '' : '　' * task.indentChars.clamp(0, 8);
    final builder =
        ui.ParagraphBuilder(paragraphStyle)
          ..pushStyle(
            ui.TextStyle(
              fontSize: task.textStyle.fontSize,
              height: task.textStyle.lineHeight,
              letterSpacing: task.textStyle.letterSpacing,
              fontWeight:
                  task.textStyle.bold
                      ? ui.FontWeight.bold
                      : ui.FontWeight.normal,
              fontFeatures: kReaderV2CjkFontFeatures,
            ),
          )
          ..addText('$indent${task.block.text}');
    final paragraph =
        builder.build()
          ..layout(ui.ParagraphConstraints(width: task.contentWidth));
    return paragraph;
  }
}

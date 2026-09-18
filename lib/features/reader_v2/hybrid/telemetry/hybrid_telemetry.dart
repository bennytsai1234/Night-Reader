import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

final class HybridTelemetrySnapshot {
  const HybridTelemetrySnapshot({
    required this.frameP50Micros,
    required this.frameP95Micros,
    required this.frameP99Micros,
    required this.jankOver8ms,
    required this.jankOver16ms,
    required this.jankOver33ms,
    required this.worstFrameMicros,
    required this.consecutiveMissedFrames,
    required this.maxConsecutiveMissedFrames,
    required this.layoutTaskCount,
    required this.layoutTaskP99Micros,
    required this.worstLayoutTaskMicros,
    required this.worstLayoutTaskPredictedMicros,
    required this.worstLayoutTaskCharCount,
    required this.layoutTasksOver8ms,
    required this.vsyncOverheadP99Micros,
    required this.buildP99Micros,
    required this.rasterP99Micros,
    required this.worstVsyncOverheadMicros,
    required this.worstBuildMicros,
    required this.worstRasterMicros,
    required this.pumpQueueDepth,
    required this.forwardLeadPx,
    required this.backwardLeadPx,
    required this.paragraphCacheHitRate,
    required this.diskMetricsHitRate,
  });

  final double frameP50Micros;
  final double frameP95Micros;
  final double frameP99Micros;
  final int jankOver8ms;
  final int jankOver16ms;
  final int jankOver33ms;
  final double worstFrameMicros;
  final int consecutiveMissedFrames;
  final int maxConsecutiveMissedFrames;
  final int layoutTaskCount;
  final double layoutTaskP99Micros;
  final double worstLayoutTaskMicros;
  final double worstLayoutTaskPredictedMicros;
  final int worstLayoutTaskCharCount;
  final int layoutTasksOver8ms;
  final double vsyncOverheadP99Micros;
  final double buildP99Micros;
  final double rasterP99Micros;
  final double worstVsyncOverheadMicros;
  final double worstBuildMicros;
  final double worstRasterMicros;
  final int pumpQueueDepth;
  final double forwardLeadPx;
  final double backwardLeadPx;
  final double paragraphCacheHitRate;
  final double diskMetricsHitRate;
}

final class HybridTelemetry extends ChangeNotifier {
  /// 120Hz 的嚴格驗收線：P99 必須小於 8ms，而不是只少於 16/33ms。
  static const int strict120HzFrameP99TargetMicros = 8000;

  /// session 累計幀時直方圖的桶寬與桶數（0–100ms，超出入 overflow 桶）。
  /// snapshot 的百分位數只看最近 240 幀（debug overlay 用）；session
  /// summary 要涵蓋整段閱讀，逐幀保存太貴，直方圖百分位誤差 ≤ 半個
  /// 桶寬（0.5ms），足供 fling p99 對比。
  static const int _sessionBucketMicros = 500;
  static const int _sessionBucketCount = 200;
  static const int _missedFrameBudgetMicros = 8333;
  static const int _jankOver16msMicros = 16667;
  static const int _jankOver33msMicros = 33333;
  static const int _layoutTaskBucketMicros = 500;
  static const int _layoutTaskBucketCount = 400;
  static const int _frameComponentBucketMicros = 500;
  static const int _frameComponentBucketCount = 400;

  final Queue<double> _frameMicros = Queue<double>();
  final List<int> _sessionBuckets = List<int>.filled(
    _sessionBucketCount + 1,
    0,
  );
  int _sessionFrames = 0;
  int _jankOver8ms = 0;
  int _jankOver16ms = 0;
  int _jankOver33ms = 0;
  double _worstFrameMicros = 0;
  int _consecutiveMissedFrames = 0;
  int _maxConsecutiveMissedFrames = 0;
  final List<int> _layoutTaskBuckets = List<int>.filled(
    _layoutTaskBucketCount + 1,
    0,
  );
  int _layoutTaskCount = 0;
  double _worstLayoutTaskMicros = 0;
  double _worstLayoutTaskPredictedMicros = 0;
  int _worstLayoutTaskCharCount = 0;
  int _layoutTasksOver8ms = 0;
  final Queue<double> _vsyncOverheadMicros = Queue<double>();
  final Queue<double> _buildMicros = Queue<double>();
  final Queue<double> _rasterMicros = Queue<double>();
  final List<int> _sessionVsyncOverheadBuckets = List<int>.filled(
    _frameComponentBucketCount + 1,
    0,
  );
  final List<int> _sessionBuildBuckets = List<int>.filled(
    _frameComponentBucketCount + 1,
    0,
  );
  final List<int> _sessionRasterBuckets = List<int>.filled(
    _frameComponentBucketCount + 1,
    0,
  );
  int _componentFrames = 0;
  double _worstVsyncOverheadMicros = 0;
  double _worstBuildMicros = 0;
  double _worstRasterMicros = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _diskHits = 0;
  int _diskMisses = 0;
  int _pumpQueueDepth = 0;
  int _maxPumpQueueDepth = 0;
  double _forwardLead = double.infinity;
  double _backwardLead = double.infinity;
  double _minForwardLead = double.infinity;
  double _minBackwardLead = double.infinity;

  HybridTelemetrySnapshot get snapshot {
    final frames = _frameMicros.toList()..sort();
    double percentile(double p) => _queuePercentile(frames, p);

    double ratio(int hit, int miss) {
      final total = hit + miss;
      return total == 0 ? 1.0 : hit / total;
    }

    return HybridTelemetrySnapshot(
      frameP50Micros: percentile(0.50),
      frameP95Micros: percentile(0.95),
      frameP99Micros: percentile(0.99),
      jankOver8ms: _jankOver8ms,
      jankOver16ms: _jankOver16ms,
      jankOver33ms: _jankOver33ms,
      worstFrameMicros: _worstFrameMicros,
      consecutiveMissedFrames: _consecutiveMissedFrames,
      maxConsecutiveMissedFrames: _maxConsecutiveMissedFrames,
      layoutTaskCount: _layoutTaskCount,
      layoutTaskP99Micros: _layoutTaskPercentile(0.99),
      worstLayoutTaskMicros: _worstLayoutTaskMicros,
      worstLayoutTaskPredictedMicros: _worstLayoutTaskPredictedMicros,
      worstLayoutTaskCharCount: _worstLayoutTaskCharCount,
      layoutTasksOver8ms: _layoutTasksOver8ms,
      vsyncOverheadP99Micros: _queuePercentile(_vsyncOverheadMicros, 0.99),
      buildP99Micros: _queuePercentile(_buildMicros, 0.99),
      rasterP99Micros: _queuePercentile(_rasterMicros, 0.99),
      worstVsyncOverheadMicros: _worstVsyncOverheadMicros,
      worstBuildMicros: _worstBuildMicros,
      worstRasterMicros: _worstRasterMicros,
      pumpQueueDepth: _pumpQueueDepth,
      forwardLeadPx: _forwardLead,
      backwardLeadPx: _backwardLead,
      paragraphCacheHitRate: ratio(_cacheHits, _cacheMisses),
      diskMetricsHitRate: ratio(_diskHits, _diskMisses),
    );
  }

  void recordFrameTimings(List<ui.FrameTiming> timings) {
    for (final timing in timings) {
      recordFrameSpanMicros(timing.totalSpan.inMicroseconds.toDouble());
      _recordFrameComponents(timing);
    }
    notifyListeners();
  }

  @visibleForTesting
  void recordFrameSpanMicros(double micros) {
    _frameMicros.add(micros);
    while (_frameMicros.length > 240) {
      _frameMicros.removeFirst();
    }
    final bucket = (micros / _sessionBucketMicros)
        .floor()
        .clamp(0, _sessionBucketCount)
        .toInt();
    _sessionBuckets[bucket] += 1;
    _sessionFrames += 1;
    if (micros > _missedFrameBudgetMicros) {
      _jankOver8ms += 1;
      _consecutiveMissedFrames += 1;
      if (_consecutiveMissedFrames > _maxConsecutiveMissedFrames) {
        _maxConsecutiveMissedFrames = _consecutiveMissedFrames;
      }
    } else {
      _consecutiveMissedFrames = 0;
    }
    if (micros > _jankOver16msMicros) _jankOver16ms += 1;
    if (micros > _jankOver33msMicros) _jankOver33ms += 1;
    if (micros > _worstFrameMicros) _worstFrameMicros = micros;
  }

  void _recordFrameComponents(ui.FrameTiming timing) {
    _componentFrames += 1;
    _recordComponent(
      timing.vsyncOverhead.inMicroseconds.toDouble(),
      _vsyncOverheadMicros,
      _sessionVsyncOverheadBuckets,
      (value) {
        if (value > _worstVsyncOverheadMicros) {
          _worstVsyncOverheadMicros = value;
        }
      },
    );
    _recordComponent(
      timing.buildDuration.inMicroseconds.toDouble(),
      _buildMicros,
      _sessionBuildBuckets,
      (value) {
        if (value > _worstBuildMicros) _worstBuildMicros = value;
      },
    );
    _recordComponent(
      timing.rasterDuration.inMicroseconds.toDouble(),
      _rasterMicros,
      _sessionRasterBuckets,
      (value) {
        if (value > _worstRasterMicros) _worstRasterMicros = value;
      },
    );
  }

  void _recordComponent(
    double micros,
    Queue<double> rolling,
    List<int> sessionBuckets,
    void Function(double value) recordWorst,
  ) {
    if (!micros.isFinite || micros < 0) return;
    rolling.add(micros);
    while (rolling.length > 240) {
      rolling.removeFirst();
    }
    final bucket = (micros / _frameComponentBucketMicros)
        .floor()
        .clamp(0, _frameComponentBucketCount)
        .toInt();
    sessionBuckets[bucket] += 1;
    recordWorst(micros);
  }

  double _queuePercentile(Iterable<double> values, double p) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) return 0;
    final index = ((sorted.length - 1) * p).round();
    return sorted[index];
  }

  double _bucketPercentile(List<int> buckets, int count, double p) {
    if (count == 0) return 0;
    final target = (count * p).ceil();
    var cumulative = 0;
    for (var bucket = 0; bucket < buckets.length; bucket += 1) {
      cumulative += buckets[bucket];
      if (cumulative >= target) {
        return ((bucket + 1) * _frameComponentBucketMicros).toDouble();
      }
    }
    return ((buckets.length) * _frameComponentBucketMicros).toDouble();
  }

  /// session 累計摘要（JSON-able），供 session 結束時寫入 AppLog 回收
  /// 分析；rolling snapshot 只涵蓋最近 240 幀，不能拿來當驗收數據。
  /// lead 的 double.infinity（尚未觀測）以 null 表示。
  Map<String, Object?> sessionSummary() {
    double percentile(double p) {
      if (_sessionFrames == 0) return 0;
      final target = (_sessionFrames * p).ceil();
      var cumulative = 0;
      for (var bucket = 0; bucket < _sessionBuckets.length; bucket += 1) {
        cumulative += _sessionBuckets[bucket];
        if (cumulative >= target) {
          return ((bucket + 1) * _sessionBucketMicros).toDouble();
        }
      }
      return (_sessionBuckets.length * _sessionBucketMicros).toDouble();
    }

    double? finiteOrNull(double value) => value.isFinite ? value : null;

    return <String, Object?>{
      'frames': _sessionFrames,
      'frameP50Micros': percentile(0.50),
      'frameP95Micros': percentile(0.95),
      'frameP99Micros': percentile(0.99),
      'jankOver8ms': _jankOver8ms,
      'jankOver16ms': _jankOver16ms,
      'jankOver33ms': _jankOver33ms,
      'worstFrameMicros': _worstFrameMicros,
      'maxConsecutiveMissedFrames': _maxConsecutiveMissedFrames,
      'layoutTaskCount': _layoutTaskCount,
      'layoutTaskP99Micros': _layoutTaskPercentile(0.99),
      'worstLayoutTaskMicros': _worstLayoutTaskMicros,
      'worstLayoutTaskPredictedMicros': _worstLayoutTaskPredictedMicros,
      'worstLayoutTaskCharCount': _worstLayoutTaskCharCount,
      'layoutTasksOver8ms': _layoutTasksOver8ms,
      'vsyncOverheadP99Micros': _bucketPercentile(
        _sessionVsyncOverheadBuckets,
        _componentFrames,
        0.99,
      ),
      'buildP99Micros': _bucketPercentile(
        _sessionBuildBuckets,
        _componentFrames,
        0.99,
      ),
      'rasterP99Micros': _bucketPercentile(
        _sessionRasterBuckets,
        _componentFrames,
        0.99,
      ),
      'worstVsyncOverheadMicros': _worstVsyncOverheadMicros,
      'worstBuildMicros': _worstBuildMicros,
      'worstRasterMicros': _worstRasterMicros,
      'paragraphCacheHits': _cacheHits,
      'paragraphCacheMisses': _cacheMisses,
      'diskMetricsHits': _diskHits,
      'diskMetricsMisses': _diskMisses,
      'maxPumpQueueDepth': _maxPumpQueueDepth,
      'minForwardLeadPx': finiteOrNull(_minForwardLead),
      'minBackwardLeadPx': finiteOrNull(_minBackwardLead),
    };
  }

  /// 清除只供效能驗收使用的 frame/task window。
  ///
  /// Reader 開啟與初始 restore 是 warm-up，不應掩蓋之後 scroll/chapter
  /// workload 的 P99；cache、queue、lead 與功能計數不受影響。正式 session
  /// log 不會主動呼叫這個 seam。
  void resetPerformanceWindow() {
    _frameMicros.clear();
    _sessionBuckets.fillRange(0, _sessionBuckets.length, 0);
    _sessionFrames = 0;
    _jankOver8ms = 0;
    _jankOver16ms = 0;
    _jankOver33ms = 0;
    _worstFrameMicros = 0;
    _consecutiveMissedFrames = 0;
    _maxConsecutiveMissedFrames = 0;
    _vsyncOverheadMicros.clear();
    _buildMicros.clear();
    _rasterMicros.clear();
    _sessionVsyncOverheadBuckets.fillRange(
      0,
      _sessionVsyncOverheadBuckets.length,
      0,
    );
    _sessionBuildBuckets.fillRange(0, _sessionBuildBuckets.length, 0);
    _sessionRasterBuckets.fillRange(0, _sessionRasterBuckets.length, 0);
    _componentFrames = 0;
    _layoutTaskBuckets.fillRange(0, _layoutTaskBuckets.length, 0);
    _layoutTaskCount = 0;
    _worstLayoutTaskMicros = 0;
    _worstLayoutTaskPredictedMicros = 0;
    _worstLayoutTaskCharCount = 0;
    _layoutTasksOver8ms = 0;
    _worstVsyncOverheadMicros = 0;
    _worstBuildMicros = 0;
    _worstRasterMicros = 0;
  }

  /// 低頻率長時間觀測用摘要；保留 session 累計值，另外補上當下 rolling
  /// frame、queue、lead 與 cache 狀態，讓外部 runner 能判斷 backlog 是否
  /// 在某個時間點排空，而不必等到 Reader dispose 才看到最後摘要。
  Map<String, Object?> heartbeatSummary() {
    final rolling = snapshot;
    final summary = sessionSummary();
    summary.addAll(<String, Object?>{
      'rollingFrameP50Micros': rolling.frameP50Micros,
      'rollingFrameP95Micros': rolling.frameP95Micros,
      'rollingFrameP99Micros': rolling.frameP99Micros,
      'pumpQueueDepth': rolling.pumpQueueDepth,
      'maxPumpQueueDepth': _maxPumpQueueDepth,
      'rollingJankOver33ms': rolling.jankOver33ms,
      'worstFrameMicros': rolling.worstFrameMicros,
      'consecutiveMissedFrames': rolling.consecutiveMissedFrames,
      'maxConsecutiveMissedFrames': rolling.maxConsecutiveMissedFrames,
      'rollingVsyncOverheadP99Micros': rolling.vsyncOverheadP99Micros,
      'rollingBuildP99Micros': rolling.buildP99Micros,
      'rollingRasterP99Micros': rolling.rasterP99Micros,
      'worstVsyncOverheadMicros': rolling.worstVsyncOverheadMicros,
      'worstBuildMicros': rolling.worstBuildMicros,
      'worstRasterMicros': rolling.worstRasterMicros,
      'forwardLeadPx': _finiteOrNull(rolling.forwardLeadPx),
      'backwardLeadPx': _finiteOrNull(rolling.backwardLeadPx),
      'paragraphCacheHitRate': rolling.paragraphCacheHitRate,
      'diskMetricsHitRate': rolling.diskMetricsHitRate,
    });
    return summary;
  }

  void recordParagraphCacheHit(bool hit) {
    hit ? _cacheHits += 1 : _cacheMisses += 1;
    notifyListeners();
  }

  void recordDiskMetricsHit(bool hit) {
    hit ? _diskHits += 1 : _diskMisses += 1;
    notifyListeners();
  }

  /// 更新 pump queue 的目前與峰值，不觸發 overlay rebuild。
  ///
  /// heartbeat 會定期取樣這個值；在 lead 尚未可計算或沒有新 layout
  /// 完成的期間，也能觀察 queue 是否持續堆積。
  void recordPumpQueueDepth(int depth) {
    final normalized = depth < 0 ? 0 : depth;
    _pumpQueueDepth = normalized;
    if (normalized > _maxPumpQueueDepth) {
      _maxPumpQueueDepth = normalized;
    }
  }

  /// 記錄單一同步 layout task，供 frame P99 超標時定位真正的工作來源。
  /// 不 notify，避免 diagnostics 自己增加 UI thread 工作量。
  void recordLayoutTask({
    required double elapsedMicros,
    required double predictedMicros,
    required int charCount,
  }) {
    if (!elapsedMicros.isFinite || elapsedMicros < 0) return;
    final bucket = (elapsedMicros / _layoutTaskBucketMicros)
        .floor()
        .clamp(0, _layoutTaskBucketCount)
        .toInt();
    _layoutTaskBuckets[bucket] += 1;
    _layoutTaskCount += 1;
    if (elapsedMicros > _worstLayoutTaskMicros) {
      _worstLayoutTaskMicros = elapsedMicros;
      _worstLayoutTaskPredictedMicros = predictedMicros.isFinite
          ? predictedMicros
          : 0;
      _worstLayoutTaskCharCount = charCount;
    }
    if (elapsedMicros > _missedFrameBudgetMicros) _layoutTasksOver8ms += 1;
  }

  double _layoutTaskPercentile(double p) {
    if (_layoutTaskCount == 0) return 0;
    final target = (_layoutTaskCount * p).ceil();
    var cumulative = 0;
    for (var bucket = 0; bucket < _layoutTaskBuckets.length; bucket += 1) {
      cumulative += _layoutTaskBuckets[bucket];
      if (cumulative >= target) {
        return ((bucket + 1) * _layoutTaskBucketMicros).toDouble();
      }
    }
    return ((_layoutTaskBucketCount + 1) * _layoutTaskBucketMicros).toDouble();
  }

  void updateRuntimeStats({
    required int pumpQueueDepth,
    required double forwardLeadPx,
    required double backwardLeadPx,
  }) {
    recordPumpQueueDepth(pumpQueueDepth);
    _forwardLead = forwardLeadPx;
    _backwardLead = backwardLeadPx;
    if (forwardLeadPx < _minForwardLead) _minForwardLead = forwardLeadPx;
    if (backwardLeadPx < _minBackwardLead) _minBackwardLead = backwardLeadPx;
    notifyListeners();
  }
}

double? _finiteOrNull(double value) => value.isFinite ? value : null;

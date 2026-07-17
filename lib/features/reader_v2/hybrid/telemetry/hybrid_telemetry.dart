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
  final int pumpQueueDepth;
  final double forwardLeadPx;
  final double backwardLeadPx;
  final double paragraphCacheHitRate;
  final double diskMetricsHitRate;
}

final class HybridTelemetry extends ChangeNotifier {
  /// session 累計幀時直方圖的桶寬與桶數（0–100ms，超出入 overflow 桶）。
  /// snapshot 的百分位數只看最近 240 幀（debug overlay 用）；session
  /// summary 要涵蓋整段閱讀，逐幀保存太貴，直方圖百分位誤差 ≤ 半個
  /// 桶寬（0.5ms），足供 fling p99 對比。
  static const int _sessionBucketMicros = 500;
  static const int _sessionBucketCount = 200;

  final Queue<double> _frameMicros = Queue<double>();
  final List<int> _sessionBuckets = List<int>.filled(
    _sessionBucketCount + 1,
    0,
  );
  int _sessionFrames = 0;
  int _jankOver8ms = 0;
  int _jankOver16ms = 0;
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
    double percentile(double p) {
      if (frames.isEmpty) return 0;
      final index = ((frames.length - 1) * p).round();
      return frames[index];
    }

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
    if (micros > 8333) _jankOver8ms += 1;
    if (micros > 16667) _jankOver16ms += 1;
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
      'paragraphCacheHits': _cacheHits,
      'paragraphCacheMisses': _cacheMisses,
      'diskMetricsHits': _diskHits,
      'diskMetricsMisses': _diskMisses,
      'maxPumpQueueDepth': _maxPumpQueueDepth,
      'minForwardLeadPx': finiteOrNull(_minForwardLead),
      'minBackwardLeadPx': finiteOrNull(_minBackwardLead),
    };
  }

  void recordParagraphCacheHit(bool hit) {
    hit ? _cacheHits += 1 : _cacheMisses += 1;
    notifyListeners();
  }

  void recordDiskMetricsHit(bool hit) {
    hit ? _diskHits += 1 : _diskMisses += 1;
    notifyListeners();
  }

  void updateRuntimeStats({
    required int pumpQueueDepth,
    required double forwardLeadPx,
    required double backwardLeadPx,
  }) {
    _pumpQueueDepth = pumpQueueDepth;
    if (pumpQueueDepth > _maxPumpQueueDepth) {
      _maxPumpQueueDepth = pumpQueueDepth;
    }
    _forwardLead = forwardLeadPx;
    _backwardLead = backwardLeadPx;
    if (forwardLeadPx < _minForwardLead) _minForwardLead = forwardLeadPx;
    if (backwardLeadPx < _minBackwardLead) _minBackwardLead = backwardLeadPx;
    notifyListeners();
  }
}

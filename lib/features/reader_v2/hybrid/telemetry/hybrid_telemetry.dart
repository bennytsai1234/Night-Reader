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
  final Queue<double> _frameMicros = Queue<double>();
  int _jankOver8ms = 0;
  int _jankOver16ms = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _diskHits = 0;
  int _diskMisses = 0;
  int _pumpQueueDepth = 0;
  double _forwardLead = double.infinity;
  double _backwardLead = double.infinity;

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
      final micros = timing.totalSpan.inMicroseconds.toDouble();
      _frameMicros.add(micros);
      while (_frameMicros.length > 240) {
        _frameMicros.removeFirst();
      }
      if (micros > 8333) _jankOver8ms += 1;
      if (micros > 16667) _jankOver16ms += 1;
    }
    notifyListeners();
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
    _forwardLead = forwardLeadPx;
    _backwardLead = backwardLeadPx;
    notifyListeners();
  }
}

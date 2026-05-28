import 'dart:ui';

import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_engine.dart';

class ReaderV2PerformanceSnapshot {
  const ReaderV2PerformanceSnapshot({
    required this.frameSampleCount,
    required this.averageFrameTotalMs,
    required this.averageFrameBuildMs,
    required this.averageFrameRasterMs,
    required this.worstFrameTotalMs,
    required this.jankyFrameCount,
    required this.layoutSampleCount,
    required this.averageLayoutMs,
    required this.worstLayoutMs,
    required this.fullScreenLoadingSampleCount,
    required this.overlayLoadingSampleCount,
    required this.slidePlaceholderSampleCount,
    required this.slidePlaceholderExposureCount,
  });

  final int frameSampleCount;
  final double averageFrameTotalMs;
  final double averageFrameBuildMs;
  final double averageFrameRasterMs;
  final double worstFrameTotalMs;
  final int jankyFrameCount;
  final int layoutSampleCount;
  final double averageLayoutMs;
  final double worstLayoutMs;
  final int fullScreenLoadingSampleCount;
  final int overlayLoadingSampleCount;
  final int slidePlaceholderSampleCount;
  final int slidePlaceholderExposureCount;

  String toProfilingSignal() {
    final jankRatio =
        frameSampleCount == 0 ? 0.0 : jankyFrameCount / frameSampleCount * 100;
    final avgPlaceholders =
        slidePlaceholderSampleCount == 0
            ? 0.0
            : slidePlaceholderExposureCount / slidePlaceholderSampleCount;
    return 'frame(avg=${averageFrameTotalMs.toStringAsFixed(2)}ms, '
        'worst=${worstFrameTotalMs.toStringAsFixed(2)}ms, '
        'jank=${jankyFrameCount}/${frameSampleCount} ${jankRatio.toStringAsFixed(1)}%), '
        'layout(avg=${averageLayoutMs.toStringAsFixed(2)}ms, '
        'worst=${worstLayoutMs.toStringAsFixed(2)}ms, n=$layoutSampleCount), '
        'loading(full=$fullScreenLoadingSampleCount, overlay=$overlayLoadingSampleCount), '
        'placeholder(avg=${avgPlaceholders.toStringAsFixed(2)}, '
        'samples=$slidePlaceholderSampleCount)';
  }
}

class ReaderV2PerformanceMetricsRecorder {
  static const double _jankFrameThresholdMs = 16.7;

  int _frameSampleCount = 0;
  double _frameTotalMsSum = 0;
  double _frameBuildMsSum = 0;
  double _frameRasterMsSum = 0;
  double _frameWorstTotalMs = 0;
  int _jankyFrameCount = 0;

  int _layoutSampleCount = 0;
  double _layoutElapsedMsSum = 0;
  double _layoutWorstMs = 0;

  int _fullScreenLoadingSampleCount = 0;
  int _overlayLoadingSampleCount = 0;
  int _slidePlaceholderSampleCount = 0;
  int _slidePlaceholderExposureCount = 0;

  void clear() {
    _frameSampleCount = 0;
    _frameTotalMsSum = 0;
    _frameBuildMsSum = 0;
    _frameRasterMsSum = 0;
    _frameWorstTotalMs = 0;
    _jankyFrameCount = 0;
    _layoutSampleCount = 0;
    _layoutElapsedMsSum = 0;
    _layoutWorstMs = 0;
    _fullScreenLoadingSampleCount = 0;
    _overlayLoadingSampleCount = 0;
    _slidePlaceholderSampleCount = 0;
    _slidePlaceholderExposureCount = 0;
  }

  void recordFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final totalMs = timing.totalSpan.inMicroseconds / 1000;
      final buildMs = timing.buildDuration.inMicroseconds / 1000;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000;
      recordFrameSample(totalMs: totalMs, buildMs: buildMs, rasterMs: rasterMs);
    }
  }

  void recordFrameSample({
    required double totalMs,
    required double buildMs,
    required double rasterMs,
  }) {
    _frameSampleCount += 1;
    _frameTotalMsSum += totalMs;
    _frameBuildMsSum += buildMs;
    _frameRasterMsSum += rasterMs;
    if (totalMs > _frameWorstTotalMs) {
      _frameWorstTotalMs = totalMs;
    }
    if (totalMs > _jankFrameThresholdMs) {
      _jankyFrameCount += 1;
    }
  }

  void recordLayoutStats(ReaderV2LayoutEngineStats stats) {
    final elapsedMs = stats.elapsed.inMicroseconds / 1000;
    _layoutSampleCount += 1;
    _layoutElapsedMsSum += elapsedMs;
    if (elapsedMs > _layoutWorstMs) {
      _layoutWorstMs = elapsedMs;
    }
  }

  void recordFullScreenLoadingSample() {
    _fullScreenLoadingSampleCount += 1;
  }

  void recordOverlayLoadingSample() {
    _overlayLoadingSampleCount += 1;
  }

  void recordSlidePlaceholderExposure(int placeholderCount) {
    if (placeholderCount <= 0) return;
    _slidePlaceholderSampleCount += 1;
    _slidePlaceholderExposureCount += placeholderCount;
  }

  ReaderV2PerformanceSnapshot snapshot() {
    double avg(double sum, int count) {
      if (count <= 0) return 0;
      return sum / count;
    }

    return ReaderV2PerformanceSnapshot(
      frameSampleCount: _frameSampleCount,
      averageFrameTotalMs: avg(_frameTotalMsSum, _frameSampleCount),
      averageFrameBuildMs: avg(_frameBuildMsSum, _frameSampleCount),
      averageFrameRasterMs: avg(_frameRasterMsSum, _frameSampleCount),
      worstFrameTotalMs: _frameWorstTotalMs,
      jankyFrameCount: _jankyFrameCount,
      layoutSampleCount: _layoutSampleCount,
      averageLayoutMs: avg(_layoutElapsedMsSum, _layoutSampleCount),
      worstLayoutMs: _layoutWorstMs,
      fullScreenLoadingSampleCount: _fullScreenLoadingSampleCount,
      overlayLoadingSampleCount: _overlayLoadingSampleCount,
      slidePlaceholderSampleCount: _slidePlaceholderSampleCount,
      slidePlaceholderExposureCount: _slidePlaceholderExposureCount,
    );
  }
}

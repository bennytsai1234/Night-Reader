import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:night_reader/features/reader_v2/hybrid/telemetry/hybrid_telemetry.dart';

void main() {
  group('HybridTelemetry sessionSummary', () {
    test('session 百分位涵蓋全部幀而非只剩 rolling window', () {
      final telemetry = HybridTelemetry();
      // 1000 幀 4ms + 10 幀 30ms：rolling window（240）只剩尾段，
      // session 直方圖必須涵蓋全部 1010 幀。
      for (var i = 0; i < 1000; i += 1) {
        telemetry.recordFrameSpanMicros(4000);
      }
      for (var i = 0; i < 10; i += 1) {
        telemetry.recordFrameSpanMicros(30000);
      }
      final summary = telemetry.sessionSummary();
      expect(summary['frames'], 1010);
      // p50 落在 4ms 桶（上界 4.5ms 內）；p99 = 30ms 桶前仍在 4ms 群。
      expect(summary['frameP50Micros'], lessThanOrEqualTo(4500));
      expect(summary['frameP99Micros'], lessThanOrEqualTo(4500));
      expect(summary['jankOver8ms'], 10);
      expect(summary['jankOver16ms'], 10);
      expect(summary['jankOver33ms'], 0);
      expect(summary['worstFrameMicros'], 30000);
    });

    test('p99 反映尾端慢幀且 summary 可 JSON 序列化', () {
      final telemetry = HybridTelemetry();
      for (var i = 0; i < 90; i += 1) {
        telemetry.recordFrameSpanMicros(4000);
      }
      for (var i = 0; i < 10; i += 1) {
        telemetry.recordFrameSpanMicros(20000);
      }
      telemetry.updateRuntimeStats(
        pumpQueueDepth: 3,
        forwardLeadPx: 1200,
        backwardLeadPx: 800,
      );
      telemetry.updateRuntimeStats(
        pumpQueueDepth: 1,
        forwardLeadPx: 2400,
        backwardLeadPx: 1600,
      );
      final summary = telemetry.sessionSummary();
      expect(summary['frameP99Micros'], greaterThanOrEqualTo(20000));
      expect(summary['maxPumpQueueDepth'], 3, reason: '保留 session 峰值');
      expect(summary['minForwardLeadPx'], 1200, reason: '保留 session 最低領先量');
      expect(summary['minBackwardLeadPx'], 800);
      expect(summary['jankOver33ms'], 0);
      expect(summary['maxConsecutiveMissedFrames'], 10);
      expect(jsonEncode(summary), isA<String>());
    });

    test('records >33ms frames and consecutive missed-frame streaks', () {
      final telemetry = HybridTelemetry();

      telemetry.recordFrameSpanMicros(9000);
      telemetry.recordFrameSpanMicros(34000);
      telemetry.recordFrameSpanMicros(35000);
      telemetry.recordFrameSpanMicros(4000);

      final snapshot = telemetry.snapshot;
      expect(snapshot.jankOver33ms, 2);
      expect(snapshot.worstFrameMicros, 35000);
      expect(snapshot.consecutiveMissedFrames, 0);
      expect(snapshot.maxConsecutiveMissedFrames, 3);

      final summary = telemetry.sessionSummary();
      expect(summary['jankOver33ms'], 2);
      expect(summary['worstFrameMicros'], 35000);
      expect(summary['maxConsecutiveMissedFrames'], 3);
    });

    test('120Hz gate 使用嚴格 P99 < 8ms，並保留 layout task 證據', () {
      final telemetry = HybridTelemetry();

      expect(HybridTelemetry.strict120HzFrameP99TargetMicros, 8000);
      telemetry.recordFrameSpanMicros(7999);
      telemetry.recordLayoutTask(
        elapsedMicros: 9500,
        predictedMicros: 2000,
        charCount: 1024,
      );

      final snapshot = telemetry.snapshot;
      expect(snapshot.layoutTaskCount, 1);
      expect(snapshot.layoutTaskP99Micros, greaterThanOrEqualTo(9500));
      expect(snapshot.worstLayoutTaskMicros, 9500);
      expect(snapshot.worstLayoutTaskPredictedMicros, 2000);
      expect(snapshot.worstLayoutTaskCharCount, 1024);
      expect(snapshot.layoutTasksOver8ms, 1);

      final summary = telemetry.sessionSummary();
      expect(summary['layoutTaskCount'], 1);
      expect(summary['layoutTasksOver8ms'], 1);
      expect(summary['worstLayoutTaskCharCount'], 1024);
    });

    test('FrameTiming 會分開保留 vsync overhead、build 與 raster 證據', () {
      final telemetry = HybridTelemetry();
      telemetry.recordFrameTimings(<ui.FrameTiming>[
        ui.FrameTiming(
          vsyncStart: 1000,
          buildStart: 5000,
          buildFinish: 8000,
          rasterStart: 8500,
          rasterFinish: 11000,
          rasterFinishWallTime: 11000,
        ),
      ]);

      final snapshot = telemetry.snapshot;
      expect(snapshot.frameP99Micros, 10000);
      expect(snapshot.vsyncOverheadP99Micros, 4000);
      expect(snapshot.buildP99Micros, 3000);
      expect(snapshot.rasterP99Micros, 2500);
      expect(snapshot.worstVsyncOverheadMicros, 4000);
      expect(snapshot.worstBuildMicros, 3000);
      expect(snapshot.worstRasterMicros, 2500);

      final summary = telemetry.sessionSummary();
      expect(summary['vsyncOverheadP99Micros'], 4500);
      expect(summary['buildP99Micros'], 3500);
      expect(summary['rasterP99Micros'], 3000);
    });

    test('效能 window reset 不影響 queue／lead 功能診斷狀態', () {
      final telemetry = HybridTelemetry();
      telemetry
        ..recordFrameSpanMicros(30000)
        ..recordLayoutTask(
          elapsedMicros: 12000,
          predictedMicros: 2000,
          charCount: 800,
        )
        ..updateRuntimeStats(
          pumpQueueDepth: 7,
          forwardLeadPx: 100,
          backwardLeadPx: 50,
        );

      telemetry.resetPerformanceWindow();
      final summary = telemetry.sessionSummary();
      final heartbeat = telemetry.heartbeatSummary();

      expect(summary['frames'], 0);
      expect(summary['layoutTaskCount'], 0);
      expect(summary['worstFrameMicros'], 0);
      expect(summary['maxPumpQueueDepth'], 7);
      expect(heartbeat['pumpQueueDepth'], 7);
      expect(heartbeat['forwardLeadPx'], 100);
      expect(heartbeat['backwardLeadPx'], 50);
    });

    test('尚無觀測值時 lead 為 null、空 session 百分位為 0', () {
      final summary = HybridTelemetry().sessionSummary();
      expect(summary['frames'], 0);
      expect(summary['frameP99Micros'], 0);
      expect(summary['minForwardLeadPx'], isNull);
      expect(jsonEncode(summary), isA<String>());
    });
  });

  group('HybridTelemetry heartbeat', () {
    test('heartbeat exposes current and peak queue depth', () {
      final telemetry = HybridTelemetry();

      telemetry.recordFrameSpanMicros(10000);
      telemetry.recordPumpQueueDepth(3);
      telemetry.updateRuntimeStats(
        pumpQueueDepth: 8,
        forwardLeadPx: 100,
        backwardLeadPx: 50,
      );
      telemetry.recordPumpQueueDepth(2);

      final heartbeat = telemetry.heartbeatSummary();

      expect(heartbeat['frames'], 1);
      expect(heartbeat['pumpQueueDepth'], 2);
      expect(heartbeat['maxPumpQueueDepth'], 8);
      expect(heartbeat['forwardLeadPx'], 100);
      expect(heartbeat['backwardLeadPx'], 50);
      expect(heartbeat['rollingFrameP50Micros'], 10000);
    });

    test('heartbeat represents unobserved lead values as null', () {
      final heartbeat = HybridTelemetry().heartbeatSummary();

      expect(heartbeat['forwardLeadPx'], isNull);
      expect(heartbeat['backwardLeadPx'], isNull);
      expect(heartbeat['minForwardLeadPx'], isNull);
      expect(heartbeat['minBackwardLeadPx'], isNull);
    });

    test('negative queue depth is clamped and does not lower the peak', () {
      final telemetry = HybridTelemetry();

      telemetry.recordPumpQueueDepth(4);
      telemetry.recordPumpQueueDepth(-1);

      final heartbeat = telemetry.heartbeatSummary();

      expect(heartbeat['pumpQueueDepth'], 0);
      expect(heartbeat['maxPumpQueueDepth'], 4);
    });
  });
}

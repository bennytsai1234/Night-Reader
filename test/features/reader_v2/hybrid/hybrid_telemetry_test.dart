import 'dart:convert';

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
      expect(jsonEncode(summary), isA<String>());
    });

    test('尚無觀測值時 lead 為 null、空 session 百分位為 0', () {
      final summary = HybridTelemetry().sessionSummary();
      expect(summary['frames'], 0);
      expect(summary['frameP99Micros'], 0);
      expect(summary['minForwardLeadPx'], isNull);
      expect(jsonEncode(summary), isA<String>());
    });
  });
}

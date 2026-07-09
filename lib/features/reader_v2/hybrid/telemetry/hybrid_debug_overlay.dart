import 'package:flutter/widgets.dart';

import 'hybrid_telemetry.dart';

final class HybridDebugOverlay extends StatelessWidget {
  const HybridDebugOverlay({super.key, required this.telemetry});

  final HybridTelemetry telemetry;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: telemetry,
      builder: (context, child) {
        final snapshot = telemetry.snapshot;
        return DefaultTextStyle(
          style: const TextStyle(fontSize: 11, color: Color(0xFFFFFFFF)),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Color(0x99000000)),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                'p99 ${(snapshot.frameP99Micros / 1000).toStringAsFixed(1)}ms\n'
                'q ${snapshot.pumpQueueDepth} lead ${snapshot.forwardLeadPx.toStringAsFixed(0)}/${snapshot.backwardLeadPx.toStringAsFixed(0)}\n'
                'cache ${(snapshot.paragraphCacheHitRate * 100).toStringAsFixed(0)}%',
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'dart:math' as math;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/hybrid/measure/document_index.dart';

final class HybridProgress implements HybridProgressCalculator {
  HybridProgress({required this.documentIndex, required this.chapterCount});

  final DocumentIndex documentIndex;
  final int chapterCount;

  @override
  HybridProgressSnapshot progressForOffset(double offset) {
    final hit = documentIndex.hitTest(offset);
    if (hit == null) {
      return HybridProgressSnapshot(
        chapterIndex: 0,
        chapterCount: chapterCount,
        chapterPercent: 0,
      );
    }
    final chapterRange = documentIndex.chapterRange(hit.key.chapterIndex);
    final chapterExtent = chapterRange?.extent ?? 0.0;
    final rawPercent =
        chapterExtent <= 0
            ? 0.0
            : ((offset - chapterRange!.top) / chapterExtent) * 100;
    final isLastChapter =
        chapterCount > 0 && hit.key.chapterIndex >= chapterCount - 1;
    final percent =
        isLastChapter && rawPercent >= 100
            ? 100.0
            : math.min(rawPercent.clamp(0.0, 99.9).toDouble(), 99.9);
    return HybridProgressSnapshot(
      chapterIndex: hit.key.chapterIndex,
      chapterCount: chapterCount,
      chapterPercent: percent,
    );
  }
}

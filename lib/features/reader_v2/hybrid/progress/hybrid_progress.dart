import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

/// Computes published progress from semantic text coordinates.
///
/// DocumentIndex owns only the materialized layout window. It is deliberately
/// absent here because a partial chapter extent cannot represent total chapter
/// progress.
final class HybridProgress implements HybridProgressCalculator {
  const HybridProgress({required this.chapterCount});

  final int chapterCount;

  @override
  HybridProgressSnapshot progressForLocation(
    ReaderV2Location location, {
    required int chapterLength,
  }) {
    final chapterIndex = chapterCount <= 0
        ? 0
        : location.chapterIndex.clamp(0, chapterCount - 1).toInt();
    final chapterPercent = chapterLength <= 0
        ? 0.0
        : (location.charOffset.clamp(0, chapterLength).toInt() /
                  chapterLength *
                  100)
              .clamp(0.0, 100.0)
              .toDouble();
    return HybridProgressSnapshot(
      chapterIndex: chapterIndex,
      chapterCount: chapterCount,
      chapterPercent: chapterPercent,
    );
  }
}

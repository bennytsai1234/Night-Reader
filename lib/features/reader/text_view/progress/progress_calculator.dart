import 'package:night_reader/features/reader/text_view/core/progress_snapshot.dart';
import 'package:night_reader/features/reader/text_view/progress/chapter_shares.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';

/// Computes published progress from semantic text coordinates.
///
/// DocumentIndex owns only the materialized layout window. It is deliberately
/// absent here because a partial chapter extent cannot represent total chapter
/// progress.
final class HybridProgress {
  const HybridProgress({required this.chapterCount, this.shares});

  final int chapterCount;

  /// 每章佔全書多少；沒給時當每章一樣長。
  final ReaderV2ChapterShares? shares;

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
    final known = shares?.chapterCount == chapterCount ? shares : null;
    return HybridProgressSnapshot(
      chapterIndex: chapterIndex,
      chapterCount: chapterCount,
      chapterPercent: chapterPercent,
      chapterStart: known?.startOf(chapterIndex),
      chapterShare: known?.shareOf(chapterIndex),
    );
  }
}

import 'package:night_reader/features/reader/text_view/core/progress_snapshot.dart';
import 'package:night_reader/features/reader/text_view/progress/reader_chapter_shares.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';

/// Computes published progress from semantic text coordinates.
///
/// DocumentIndex owns only the materialized layout window. It is deliberately
/// absent here because a partial chapter extent cannot represent total chapter
/// progress.
final class ProgressCalculator {
  const ProgressCalculator({required this.chapterCount, this.shares});

  final int chapterCount;

  /// 每章佔全書多少；沒給時當每章一樣長。
  final ReaderChapterShares? shares;

  ProgressSnapshot progressForLocation(
    ReaderLocation location, {
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
    return ProgressSnapshot(
      chapterIndex: chapterIndex,
      chapterCount: chapterCount,
      chapterPercent: chapterPercent,
      chapterStart: known?.startOf(chapterIndex),
      chapterShare: known?.shareOf(chapterIndex),
    );
  }
}

class ReaderV2ChapterNavigationResolver {
  const ReaderV2ChapterNavigationResolver._();

  static int? resolveRelativeTarget({
    required int currentChapterIndex,
    required int chapterCount,
    required int delta,
  }) {
    if (chapterCount <= 0) return null;
    final safeCurrent = currentChapterIndex.clamp(0, chapterCount - 1).toInt();
    final target = safeCurrent + delta;
    if (target < 0 || target >= chapterCount) return null;
    return target;
  }
}

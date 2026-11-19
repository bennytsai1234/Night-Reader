class ReaderV2ChapterNavigationResolver {
  const ReaderV2ChapterNavigationResolver._();

  /// 從目前這一章往 [delta] 的方向數過去的那一章；[skip] 的章（付費章節，
  /// ADR 0057）不算，跳過去。沒有時是 null。
  static int? resolveRelativeTarget({
    required int currentChapterIndex,
    required int chapterCount,
    required int delta,
    bool Function(int chapterIndex)? skip,
  }) {
    if (chapterCount <= 0 || delta == 0) return null;
    final step = delta.sign;
    var target = currentChapterIndex.clamp(0, chapterCount - 1).toInt();
    for (var remaining = delta.abs(); remaining > 0; remaining--) {
      do {
        target += step;
        if (target < 0 || target >= chapterCount) return null;
      } while (skip?.call(target) ?? false);
    }
    return target;
  }
}

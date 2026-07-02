class ReaderV2DisplayCoordinator {
  const ReaderV2DisplayCoordinator();

  String formatReadProgress({
    required int chapterIndex,
    required int totalChapters,
    required int charOffset,
    required int chapterEndCharOffset,
  }) {
    if (totalChapters <= 0) return '0.0%';
    final safeChapterIndex = chapterIndex.clamp(0, totalChapters - 1);
    final chapterProgress =
        chapterEndCharOffset <= 0
            ? 0.0
            : (charOffset / chapterEndCharOffset).clamp(0.0, 1.0).toDouble();
    final percent =
        (safeChapterIndex + chapterProgress) / totalChapters.toDouble();
    var formatted = '${(percent * 100).toStringAsFixed(1)}%';
    if (formatted == '100.0%' &&
        (safeChapterIndex + 1 != totalChapters || chapterProgress < 1.0)) {
      formatted = '99.9%';
    }
    return formatted;
  }

  String formatChapterProgress({
    required int charOffset,
    required int chapterEndCharOffset,
  }) {
    if (chapterEndCharOffset <= 0) return '0.0%';
    final progress =
        (charOffset / chapterEndCharOffset).clamp(0.0, 1.0).toDouble();
    return '${(progress * 100).toStringAsFixed(1)}%';
  }

  String formatPageLabel(int pageIndex, int totalPages) {
    if (totalPages <= 0) return '0/0';
    final page = (pageIndex + 1).clamp(1, totalPages).toInt();
    return '$page/$totalPages';
  }

  String formatChapterLabel({
    required int chapterIndex,
    required int totalChapters,
  }) {
    if (totalChapters <= 0) return '0/0';
    final chapter = (chapterIndex + 1).clamp(1, totalChapters).toInt();
    return '$chapter/$totalChapters';
  }

  int resolveScrubChapterIndex({
    required dynamic value,
    required int totalChapters,
  }) {
    if (totalChapters <= 0) return 0;
    final int rawIndex =
        value is double ? (value * (totalChapters - 1)).round() : value as int;
    return rawIndex.clamp(0, totalChapters - 1).toInt();
  }
}

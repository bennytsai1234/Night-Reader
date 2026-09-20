import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_reading_state.dart';

/// 書架只持久化目前章節，沒有目前章節的總字數，因此以「已讀到第幾章」呈現
/// 章節級進度。未開始閱讀維持 0%；進入最後一章時可達 100%。
double bookshelfReadProgress(Book book) {
  final totalChapters = book.totalChapterNum;
  if (totalChapters <= 0) return 0.0;

  if (!book.hasStartedReading) return 0.0;

  final safeChapterIndex = book.chapterIndex.clamp(0, totalChapters - 1);
  return ((safeChapterIndex + 1) / totalChapters).clamp(0.0, 1.0);
}

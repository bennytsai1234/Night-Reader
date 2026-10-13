import 'package:drift/drift.dart';

import '../../models/chapter.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'chapter_dao.g.dart';

@DriftAccessor(tables: [Chapters])
class ChapterDao extends DatabaseAccessor<AppDatabase> with _$ChapterDaoMixin {
  ChapterDao(super.db);

  Future<List<BookChapter>> getByBook(String bookUrl) {
    return (select(chapters)
          ..where((t) => t.bookUrl.equals(bookUrl))
          ..orderBy([(t) => OrderingTerm(expression: t.index)]))
        .get();
  }

  Stream<List<BookChapter>> watchByBook(String bookUrl) {
    return (select(chapters)
          ..where((t) => t.bookUrl.equals(bookUrl))
          ..orderBy([(t) => OrderingTerm(expression: t.index)]))
        .watch();
  }

  Future<void> insertChapters(List<BookChapter> chapterList) async {
    await batch(
      (b) => b.insertAllOnConflictUpdate(
        chapters,
        chapterList
            .map((e) => BookChapterToInsertable(e).toInsertable())
            .toList(),
      ),
    );
  }

  /// 抓正文時書源規則可能改了章節的欄位（例如 `variable`），寫回目錄裡
  /// 已有的那一列。序號沿用資料庫現在的值：呼叫端手上的章節是開始抓之前
  /// 的快照，這段時間書架檢查可能在目錄中間插了章節，序號已經位移。
  /// 目錄裡已經沒有這一章就不寫，不把舊目錄的章節加回去。
  Future<void> updateFetchedChapter(BookChapter chapter) {
    return transaction(() async {
      final current = await (select(
        chapters,
      )..where((t) => t.url.equals(chapter.url))).getSingleOrNull();
      if (current == null) return;
      await into(chapters).insertOnConflictUpdate(
        BookChapterToInsertable(
          chapter.copyWith(index: current.index, bookUrl: current.bookUrl),
        ).toInsertable(),
      );
    });
  }

  Future<BookChapter?> getChapter(String bookUrl, int index) {
    return (select(chapters)
          ..where((t) => t.bookUrl.equals(bookUrl) & t.index.equals(index)))
        .getSingleOrNull();
  }

  Future<void> deleteByBook(String bookUrl) {
    return (delete(chapters)..where((t) => t.bookUrl.equals(bookUrl))).go();
  }
}

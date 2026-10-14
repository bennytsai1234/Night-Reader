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
  /// 目錄裡已經沒有這一章就不寫，不把舊目錄的章節加回去。付費標記也沿用
  /// 資料庫的：那是目錄規則給的，快照可能是改付費之前的。
  Future<void> updateFetchedChapter(BookChapter chapter) {
    return transaction(() async {
      final current = await getByUrl(chapter.url);
      if (current == null) return;
      await into(chapters).insertOnConflictUpdate(
        BookChapterToInsertable(
          chapter.copyWith(
            index: current.index,
            bookUrl: current.bookUrl,
            isVip: current.isVip,
            isPay: current.isPay,
          ),
        ).toInsertable(),
      );
    });
  }

  Future<BookChapter?> getByUrl(String url) {
    return (select(
      chapters,
    )..where((t) => t.url.equals(url))).getSingleOrNull();
  }

  Future<BookChapter?> getChapter(String bookUrl, int index) {
    return (select(chapters)
          ..where((t) => t.bookUrl.equals(bookUrl) & t.index.equals(index)))
        .getSingleOrNull();
  }

  /// 這本書目前的目錄裡這個網址的章節序號；目錄裡沒有這一章時回傳 null。
  Future<int?> indexOfUrl(String bookUrl, String url) async {
    final row =
        await (select(chapters)
              ..where((t) => t.bookUrl.equals(bookUrl) & t.url.equals(url)))
            .getSingleOrNull();
    return row?.index;
  }

  /// 整份換掉這本書的目錄，不留舊目錄的章節佔著序號。
  Future<void> replaceByBook(String bookUrl, List<BookChapter> chapterList) {
    return transaction(() async {
      await deleteByBook(bookUrl);
      await insertChapters(chapterList);
    });
  }

  Future<void> deleteByBook(String bookUrl) {
    return (delete(chapters)..where((t) => t.bookUrl.equals(bookUrl))).go();
  }
}

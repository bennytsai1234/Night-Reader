import 'package:drift/drift.dart';

import '../../models/chapter.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'chapter_dao.g.dart';

@DriftAccessor(tables: [Chapters])
class ChapterDao extends DatabaseAccessor<AppDatabase> with _$ChapterDaoMixin {
  ChapterDao(super.db);

  /// [getByBook] 一批最多讀這麼多章。查詢在背景執行緒，但結果傳回主執行緒
  /// 轉成章節是一口氣做完：五千章在電腦上一次就佔住主執行緒 3–10ms，手機
  /// 上會掉好幾幀；兩百章一批在手機上約 1–2ms（ADR 0018）。
  static const int _readBatch = 200;

  /// 整本目錄，照序號排。分批讀，包在同一個交易裡，讀到的是同一個時間點
  /// 的目錄。
  Future<List<BookChapter>> getByBook(String bookUrl) {
    return transaction(() async {
      final all = <BookChapter>[];
      while (true) {
        final batch =
            await (select(chapters)
                  ..where((t) => t.bookUrl.equals(bookUrl))
                  ..orderBy([
                    (t) => OrderingTerm(expression: t.index),
                    (t) => OrderingTerm(expression: t.url),
                  ])
                  ..limit(_readBatch, offset: all.length))
                .get();
        all.addAll(batch);
        if (batch.length < _readBatch) return all;
      }
    });
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
      final current = await getByUrl(chapter.bookUrl, chapter.url);
      if (current == null) return;
      await into(chapters).insertOnConflictUpdate(
        BookChapterToInsertable(
          chapter.copyWith(
            index: current.index,
            isVip: current.isVip,
            isPay: current.isPay,
          ),
        ).toInsertable(),
      );
    });
  }

  /// 這本書目錄裡網址是 [url] 的那一章。
  Future<BookChapter?> getByUrl(String bookUrl, String url) {
    return (select(chapters)
          ..where((t) => t.bookUrl.equals(bookUrl) & t.url.equals(url)))
        .getSingleOrNull();
  }

  Future<BookChapter?> getChapter(String bookUrl, int index) {
    return (select(chapters)
          ..where((t) => t.bookUrl.equals(bookUrl) & t.index.equals(index)))
        .getSingleOrNull();
  }

  /// 整本目錄的章名，照序號排；同步進度時拿來對另一台的章節。
  Future<List<String>> titlesByBook(String bookUrl) async {
    final query = selectOnly(chapters)
      ..addColumns([chapters.title])
      ..where(chapters.bookUrl.equals(bookUrl))
      ..orderBy([OrderingTerm(expression: chapters.index)]);
    return [for (final row in await query.get()) row.read(chapters.title)!];
  }

  /// 這本書目前的目錄裡這個網址的章節序號；目錄裡沒有這一章時回傳 null。
  Future<int?> indexOfUrl(String bookUrl, String url) async =>
      (await getByUrl(bookUrl, url))?.index;

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

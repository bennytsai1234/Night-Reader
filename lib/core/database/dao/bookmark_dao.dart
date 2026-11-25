import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../models/book/chapter_alignment.dart';
import '../../models/reading/bookmark.dart';
import '../../models/book/book_chapter.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'bookmark_dao.g.dart';

@DriftAccessor(tables: [Bookmarks])
class BookmarkDao extends DatabaseAccessor<AppDatabase>
    with _$BookmarkDaoMixin {
  BookmarkDao(super.db);

  Future<List<Bookmark>> getAll() => select(bookmarks).get();

  /// 所有書籤，新加的在前（「我的」的書籤清單）。
  Stream<List<Bookmark>> watchAll() =>
      (select(bookmarks)..orderBy([(t) => OrderingTerm.desc(t.id)])).watch();

  /// 一本書（書名加作者）的書籤，照在書裡的先後排。
  Stream<List<Bookmark>> watchByBook(String bookName, String bookAuthor) =>
      (select(bookmarks)
            ..where(
              (t) =>
                  t.bookName.equals(bookName) & t.bookAuthor.equals(bookAuthor),
            )
            ..orderBy([
              (t) => OrderingTerm.asc(t.chapterIndex),
              (t) => OrderingTerm.asc(t.charOffset),
            ]))
          .watch();

  /// 新增一個書籤，傳回存進去的那筆。編號是建立時間的毫秒乘 1000 再加
  /// 隨機的三位數（[newId]）。
  Future<Bookmark> add(Bookmark bookmark) => transaction(() async {
    final maxId = bookmarks.id.max();
    final largest =
        await (selectOnly(
          bookmarks,
        )..addColumns([maxId])).map((row) => row.read(maxId)).getSingle() ??
        0;
    final saved = bookmark.copyWith(
      id: newId(DateTime.now().millisecondsSinceEpoch, largest, _random),
    );
    await into(bookmarks).insert(saved.toInsertable());
    return saved;
  });

  static final math.Random _random = math.Random();

  /// 新書籤的編號：兩台各自新增的不能撞號，同步拿它當身分（ADR 0042）。
  /// 只用毫秒時，兩台同一毫秒新增、或一台時鐘曾經偏快（編號比現在大，
  /// 兩台都接在同一個最大編號後面）就會撞號，雲端那筆蓋掉這台的；加上
  /// 隨機的三位數，要同一毫秒又抽到同一個數才會撞。比這台已有的最大編號
  /// 小時接在後面，同樣隔一段隨機的距離。標註也用這個配法。
  static int newId(int nowMillis, int largest, math.Random random) {
    final candidate = nowMillis * 1000 + random.nextInt(1000);
    return candidate > largest ? candidate : largest + 1 + random.nextInt(1000);
  }

  Future<void> upsertAll(List<Bookmark> items) => batch(
    (b) => b.insertAllOnConflictUpdate(
      bookmarks,
      items.map((item) => item.toInsertable()).toList(),
    ),
  );

  Future<void> deleteByIds(Iterable<int> ids) =>
      (delete(bookmarks)..where((t) => t.id.isIn(ids))).go();

  /// 讀者修改書籍資訊：書籤只換書的身分，不更動編號、位置或錨點。
  Future<void> renameBook({
    required String fromName,
    required String fromAuthor,
    required String toName,
    required String toAuthor,
  }) async {
    if (fromName == toName && fromAuthor == toAuthor) return;
    await (update(bookmarks)..where(
          (t) => t.bookName.equals(fromName) & t.bookAuthor.equals(fromAuthor),
        ))
        .write(
          BookmarksCompanion(
            bookName: Value(toName),
            bookAuthor: Value(toAuthor),
          ),
        );
  }

  /// 這本書（書名加作者）的目錄要翻過來（反轉目錄）：還沒記方向的書籤
  /// 記成翻之前的方向 [reversed]，序號不動，之後照記下的方向數
  /// （`chapterIndexByTitle`，ADR 0085）。已經記了的不動：同名同作者好幾個
  /// 書源共用的書籤，翻哪一本、翻幾本都只記一次。
  Future<void> recordTocDirection({
    required String bookName,
    required String bookAuthor,
    required bool reversed,
  }) =>
      (update(bookmarks)..where(
            (t) =>
                t.bookName.equals(bookName) &
                t.bookAuthor.equals(bookAuthor) &
                t.tocReversed.isNull(),
          ))
          .write(BookmarksCompanion(tocReversed: Value(reversed)));

  /// 一本書換了書源：書籤跟著搬到新書源那本（書名、作者照新書源的寫法），
  /// 每個書籤對到新目錄裡的同一章（同換源時的閱讀進度：先找同名的章，再照
  /// 章號與比例估），記下新書的目錄方向 [toReversed]（[fromReversed] 是舊書
  /// 的）。章內第幾個字照舊，跳回時由閱讀器照錨點的前後原文在新的正文裡
  /// 找回同一句。
  Future<void> moveToSource({
    required String fromName,
    required String fromAuthor,
    required String toName,
    required String toAuthor,
    required int oldTotalCount,
    required bool fromReversed,
    required bool toReversed,
    required List<BookChapter> chapters,
  }) async {
    final items =
        await (select(bookmarks)..where(
              (t) =>
                  t.bookName.equals(fromName) & t.bookAuthor.equals(fromAuthor),
            ))
            .get();
    // 記下的序號換成舊書目錄（[fromReversed]）裡的序號：記下時的方向不同
    // 就從另一頭數。
    int oldTocIndex(int index, bool? counted) =>
        counted != null &&
            counted != fromReversed &&
            index >= 0 &&
            index < oldTotalCount
        ? oldTotalCount - 1 - index
        : index;
    final moved = <Bookmark>[];
    for (final item in items) {
      var next = item.copyWith(
        bookName: toName,
        bookAuthor: toAuthor,
        tocReversed: item.tocReversed ?? fromReversed,
      );
      if (chapters.isNotEmpty) {
        final index = alignChapterIndex(
          oldIndex: oldTocIndex(item.chapterIndex, item.tocReversed),
          oldTitle: item.chapterTitle,
          oldTotalCount: oldTotalCount,
          newChapters: chapters,
        );
        next = next.copyWith(
          chapterIndex: index,
          chapterTitle: chapters[index].title,
          tocReversed: toReversed,
        );
      }
      if (next.bookName == item.bookName &&
          next.bookAuthor == item.bookAuthor &&
          next.chapterIndex == item.chapterIndex &&
          next.chapterTitle == item.chapterTitle &&
          next.tocReversed == item.tocReversed) {
        continue;
      }
      moved.add(next);
    }
    if (moved.isNotEmpty) await upsertAll(moved);
  }
}

import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/book/chapter_alignment.dart';
import '../../models/bookmark.dart';
import '../../models/chapter.dart';
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
  /// 小時接在後面，同樣隔一段隨機的距離。
  @visibleForTesting
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

  /// 一本書換了書源：書籤跟著搬到新書源那本（書名、作者照新書源的寫法），
  /// 每個書籤對到新目錄裡的同一章（同換源時的閱讀進度：先找同名的章，再照
  /// 章號與比例估）。章內第幾個字照舊，跳回時由閱讀器照錨點的前後原文在
  /// 新的正文裡找回同一句。
  Future<void> moveToSource({
    required String fromName,
    required String fromAuthor,
    required String toName,
    required String toAuthor,
    required int oldTotalCount,
    required List<BookChapter> chapters,
  }) async {
    final items =
        await (select(bookmarks)..where(
              (t) =>
                  t.bookName.equals(fromName) & t.bookAuthor.equals(fromAuthor),
            ))
            .get();
    final moved = <Bookmark>[];
    for (final item in items) {
      var next = item.copyWith(bookName: toName, bookAuthor: toAuthor);
      if (chapters.isNotEmpty) {
        final index = alignChapterIndex(
          oldIndex: item.chapterIndex,
          oldTitle: item.chapterTitle,
          oldTotalCount: oldTotalCount,
          newChapters: chapters,
        );
        next = next.copyWith(
          chapterIndex: index,
          chapterTitle: chapters[index].title,
        );
      }
      if (next.bookName == item.bookName &&
          next.bookAuthor == item.bookAuthor &&
          next.chapterIndex == item.chapterIndex &&
          next.chapterTitle == item.chapterTitle) {
        continue;
      }
      moved.add(next);
    }
    if (moved.isNotEmpty) await upsertAll(moved);
  }
}

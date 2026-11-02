import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../models/book/chapter_alignment.dart';
import '../../models/chapter.dart';
import '../../models/highlight.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';
import 'bookmark_dao.dart';

part 'highlight_dao.g.dart';

/// 標註的資料表。和書籤同一套（ADR 0042、0043）：跟著書名加作者、編號
/// 用 [BookmarkDao.newId] 的配法、換源時跟著搬。
@DriftAccessor(tables: [Highlights])
class HighlightDao extends DatabaseAccessor<AppDatabase>
    with _$HighlightDaoMixin {
  HighlightDao(super.db);

  Future<List<Highlight>> getAll() => select(highlights).get();

  /// 所有標註，新畫的在前（「我的 → 書籤與標註」）。
  Stream<List<Highlight>> watchAll() =>
      (select(highlights)..orderBy([(t) => OrderingTerm.desc(t.id)])).watch();

  /// 一本書（書名加作者）的標註，照在書裡的先後排。
  Stream<List<Highlight>> watchByBook(String bookName, String bookAuthor) =>
      (select(highlights)
            ..where(
              (t) =>
                  t.bookName.equals(bookName) & t.bookAuthor.equals(bookAuthor),
            )
            ..orderBy([
              (t) => OrderingTerm.asc(t.chapterIndex),
              (t) => OrderingTerm.asc(t.charOffset),
            ]))
          .watch();

  /// 最近畫的一個標註；新標註沿用它的顏色與樣子。
  Future<Highlight?> latest() =>
      (select(highlights)
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(1))
          .getSingleOrNull();

  /// 新增一個標註，傳回存進去的那筆（編號照 [BookmarkDao.newId] 配）。
  Future<Highlight> add(Highlight highlight) => transaction(() async {
    final maxId = highlights.id.max();
    final largest =
        await (selectOnly(
          highlights,
        )..addColumns([maxId])).map((row) => row.read(maxId)).getSingle() ??
        0;
    final saved = highlight.copyWith(
      id: BookmarkDao.newId(
        DateTime.now().millisecondsSinceEpoch,
        largest,
        _random,
      ),
    );
    await into(highlights).insert(saved.toInsertable());
    return saved;
  });

  static final math.Random _random = math.Random();

  Future<void> upsertAll(List<Highlight> items) => batch(
    (b) => b.insertAllOnConflictUpdate(
      highlights,
      items.map((item) => item.toInsertable()).toList(),
    ),
  );

  Future<void> deleteByIds(Iterable<int> ids) =>
      (delete(highlights)..where((t) => t.id.isIn(ids))).go();

  /// 一本書換了書源：標註跟著搬到新書源那本，每個對到新目錄裡的同一章
  /// （同 [BookmarkDao.moveToSource]）。
  Future<void> moveToSource({
    required String fromName,
    required String fromAuthor,
    required String toName,
    required String toAuthor,
    required int oldTotalCount,
    required List<BookChapter> chapters,
  }) async {
    final items =
        await (select(highlights)..where(
              (t) =>
                  t.bookName.equals(fromName) & t.bookAuthor.equals(fromAuthor),
            ))
            .get();
    final moved = <Highlight>[];
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

import 'package:drift/drift.dart';

import '../../models/book.dart';
import '../../models/book_group.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'book_dao.g.dart';

@DriftAccessor(tables: [Books])
class BookDao extends DatabaseAccessor<AppDatabase> with _$BookDaoMixin {
  BookDao(super.db);

  AppDatabase get appDatabase => attachedDatabase;

  Future<List<Book>> getAll() => select(books).get();

  Stream<List<Book>> watchInBookshelf() {
    return (select(books)
          ..where((t) => t.isInBookshelf.equals(true))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.durChapterTime,
              mode: OrderingMode.desc,
            ),
          ]))
        .watch();
  }

  Future<List<Book>> getInBookshelf() {
    return (select(books)
          ..where((t) => t.isInBookshelf.equals(true))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.durChapterTime,
              mode: OrderingMode.desc,
            ),
          ]))
        .get();
  }

  /// 書名相同的書；閱讀統計只記書名，點書名時用它找回那本書。
  Future<List<Book>> getByName(String name) {
    return (select(books)..where((t) => t.name.equals(name))).get();
  }

  Future<Book?> getByUrl(String url) {
    return (select(
      books,
    )..where((t) => t.bookUrl.equals(url))).getSingleOrNull();
  }

  Future<void> upsert(Book book) =>
      into(books).insertOnConflictUpdate(BookToInsertable(book).toInsertable());

  Future<void> upsertAll(List<Book> bookList) async {
    await batch(
      (b) => b.insertAllOnConflictUpdate(
        books,
        bookList.map((e) => BookToInsertable(e).toInsertable()).toList(),
      ),
    );
  }

  Future<void> deleteByUrl(String url) {
    return (delete(books)..where((t) => t.bookUrl.equals(url))).go();
  }

  Future<List<Book>> getInGroup(int groupId) {
    if (groupId == BookGroup.idAll) return getInBookshelf();
    if (groupId == 0) {
      return (select(
        books,
      )..where((t) => t.isInBookshelf.equals(true) & t.group.equals(0))).get();
    }
    return (select(books)..where(
          (t) =>
              t.isInBookshelf.equals(true) &
              t.group
                  .bitwiseAnd(Variable<int>(groupId))
                  .isBiggerThan(const Constant(0)),
        ))
        .get();
  }

  Future<void> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) {
    return (update(books)..where((t) => t.bookUrl.equals(bookUrl))).write(
      BooksCompanion(
        chapterIndex: Value(chapterIndex),
        durChapterTitle: Value(chapterTitle),
        charOffset: Value(pos),
        visualOffsetPx: Value(_normalizeVisualOffsetPx(visualOffsetPx)),
        readerAnchorJson: Value(readerAnchorJson),
        durChapterTime: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// 只改「是否參與書架更新」；其他欄位（閱讀進度等）不跟著被舊資料覆寫。
  Future<void> updateCanUpdate(String bookUrl, bool canUpdate) {
    return (update(books)..where((t) => t.bookUrl.equals(bookUrl))).write(
      BooksCompanion(canUpdate: Value(canUpdate)),
    );
  }

  /// 只記下檢查時間；書已不在資料庫時不會再寫回一筆。
  Future<void> updateLastCheckTime(String bookUrl, int lastCheckTime) {
    return (update(books)..where((t) => t.bookUrl.equals(bookUrl))).write(
      BooksCompanion(lastCheckTime: Value(lastCheckTime)),
    );
  }

  double _normalizeVisualOffsetPx(double value) {
    if (!value.isFinite || value.isNaN) return 0.0;
    return value.clamp(-120.0, 120.0).toDouble();
  }
}

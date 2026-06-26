import 'package:drift/drift.dart';
import '../../models/book.dart';
import '../../models/book_group.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'book_dao.g.dart';

@DriftAccessor(tables: [Books])
class BookDao extends DatabaseAccessor<AppDatabase> with _$BookDaoMixin {
  BookDao(super.db);

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

  Future<Book?> getByUrl(String url) {
    return (select(books)
      ..where((t) => t.bookUrl.equals(url))).getSingleOrNull();
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
      return (select(books)
        ..where((t) => t.isInBookshelf.equals(true) & t.group.equals(0))).get();
    }
    return (select(books)..where(
      (t) =>
          t.isInBookshelf.equals(true) &
          t.group
              .bitwiseAnd(Variable<int>(groupId))
              .isBiggerThan(const Constant(0)),
    )).get();
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

  double _normalizeVisualOffsetPx(double value) {
    if (!value.isFinite || value.isNaN) return 0.0;
    return value.clamp(-120.0, 120.0).toDouble();
  }
}

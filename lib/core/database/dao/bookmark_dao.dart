import 'package:drift/drift.dart';
import '../../models/bookmark.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'bookmark_dao.g.dart';

@DriftAccessor(tables: [Bookmarks])
class BookmarkDao extends DatabaseAccessor<AppDatabase>
    with _$BookmarkDaoMixin {
  BookmarkDao(super.db);

  Future<List<Bookmark>> getAll() => select(bookmarks).get();

  Stream<List<Bookmark>> watchByBook(String bookUrl) {
    return (select(bookmarks)..where((t) => t.bookUrl.equals(bookUrl))).watch();
  }

  Future<void> upsert(Bookmark bookmark) => into(
    bookmarks,
  ).insertOnConflictUpdate(BookmarkToInsertable(bookmark).toInsertable());

  Future<void> deleteById(int id) =>
      (delete(bookmarks)..where((t) => t.id.equals(id))).go();

  Future<void> deleteByBook(String bookUrl) =>
      (delete(bookmarks)..where((t) => t.bookUrl.equals(bookUrl))).go();

  Future<void> clearAll() => delete(bookmarks).go();

  Future<List<Bookmark>> search(String key) {
    return (select(bookmarks)..where(
      (t) =>
          t.bookName.like('%$key%') |
          t.chapterName.like('%$key%') |
          t.content.like('%$key%'),
    )).get();
  }

  Future<void> deleteBookmark(Bookmark bookmark) => deleteById(bookmark.id);
}

import 'package:drift/drift.dart';

import '../../models/search_book.dart';
import '../tables/app_tables.dart';
import '../app_database.dart';

part 'search_book_dao.g.dart';

@DriftAccessor(tables: [SearchBooks, BookSources])
class SearchBookDao extends DatabaseAccessor<AppDatabase>
    with _$SearchBookDaoMixin {
  SearchBookDao(super.db);

  /// 書名是 [names] 其中之一的結果，例如同一個書名的繁簡兩種寫法。
  Future<List<SearchBook>> getByNames(Iterable<String> names) {
    return (select(searchBooks)..where((t) => t.name.isIn(names))).get();
  }

  /// 書名是 [names] 其中之一、有封面、書源啟用中的結果，照書源順序。作者
  /// 不在這裡比：是不是同一本書由呼叫端照 `isSameBook` 判斷。
  Future<List<SearchBook>> getEnabledWithCoverByNames(Iterable<String> names) {
    final list = names.toSet().toList();
    if (list.isEmpty) return Future.value(const []);
    final placeholders = List.filled(list.length, '?').join(', ');
    return customSelect(
      '''
      SELECT t1.*, t2.customOrder as originOrder
      FROM search_books as t1 INNER JOIN book_sources as t2 ON t1.origin = t2.bookSourceUrl
      WHERE t1.name IN ($placeholders) AND t1.coverUrl IS NOT NULL AND t1.coverUrl <> '' AND t2.enabled = 1
      ORDER BY t2.customOrder
      ''',
      variables: [for (final name in list) Variable.withString(name)],
      readsFrom: {searchBooks, bookSources},
    ).map((row) => SearchBook.fromJson(row.data)).get();
  }

  Future<void> upsert(SearchBook book) =>
      into(searchBooks)
          .insertOnConflictUpdate(SearchBookToInsertable(book).toInsertable());

  Future<void> insertList(List<SearchBook> books) async {
    await batch(
      (b) => b.insertAllOnConflictUpdate(
        searchBooks,
        books.map((e) => SearchBookToInsertable(e).toInsertable()).toList(),
      ),
    );
  }

  Future<void> deleteByUrl(String url) =>
      (delete(searchBooks)..where((t) => t.bookUrl.equals(url))).go();

  Future<void> clearAll() => delete(searchBooks).go();

  Future<void> clear(String name, String author) {
    return (delete(
      searchBooks,
    )..where((t) => t.name.equals(name) & t.author.equals(author))).go();
  }
}

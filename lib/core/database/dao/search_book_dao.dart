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

  Future<List<SearchBook>> getEnabledHasCover(String name, String author) {
    return customSelect(
      '''
      SELECT t1.*, t2.customOrder as originOrder
      FROM search_books as t1 INNER JOIN book_sources as t2 ON t1.origin = t2.bookSourceUrl
      WHERE t1.name = ? AND t1.author = ? AND t1.coverUrl IS NOT NULL AND t1.coverUrl <> '' AND t2.enabled = 1
      ORDER BY t2.customOrder
      ''',
      variables: [Variable.withString(name), Variable.withString(author)],
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

  /// 書源換了網址（[from] → [to]）：之前的搜尋結果改指新網址，換封面與換源
  /// 讀本地紀錄時還找得到它們的書源。
  Future<void> moveOrigin(String from, String to, {required String toName}) {
    return (update(searchBooks)..where((t) => t.origin.equals(from))).write(
      SearchBooksCompanion(origin: Value(to), originName: Value(toName)),
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

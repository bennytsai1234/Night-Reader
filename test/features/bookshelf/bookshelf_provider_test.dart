import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fake DAOs
// ---------------------------------------------------------------------------

class _FakeBookDao extends Fake implements BookDao {
  List<Book> shelf = [];

  @override
  Future<List<Book>> getInBookshelf() async => shelf;

  @override
  Future<List<Book>> getInGroup(int groupId) async =>
      shelf.where((b) => (b.group & groupId) != 0).toList();

  @override
  Future<Book?> getByUrl(String url) async => shelf.cast<Book?>().firstWhere(
    (b) => b?.bookUrl == url,
    orElse: () => null,
  );

  @override
  Future<void> upsert(Book book) async {
    shelf.removeWhere((b) => b.bookUrl == book.bookUrl);
    shelf.add(book);
  }

  @override
  Future<void> deleteByUrl(String url) async =>
      shelf.removeWhere((b) => b.bookUrl == url);
}

class _FakeSourceDao extends Fake implements BookSourceDao {
  @override
  Future<List<BookSource>> getEnabled() async => [];
}

class _FakeChapterDao extends Fake implements ChapterDao {
  @override
  Future<void> deleteByBook(String bookUrl) async {}
}

// ---------------------------------------------------------------------------
// 測試
// ---------------------------------------------------------------------------

BookshelfProvider _makeProvider() => BookshelfProvider();

void main() {
  late _FakeBookDao fakeBookDao;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    fakeBookDao = _FakeBookDao();

    final getIt = GetIt.instance;
    getIt.registerLazySingleton<BookDao>(() => fakeBookDao);
    getIt.registerLazySingleton<BookSourceDao>(() => _FakeSourceDao());
    getIt.registerLazySingleton<ChapterDao>(() => _FakeChapterDao());
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
  });

  tearDown(() async => GetIt.instance.reset());

  group('BookshelfProvider - 書架書籍載入', () {
    test('loadBooks 從 DAO 取得書籍', () async {
      fakeBookDao.shelf = [
        Book(
          bookUrl: 'http://a.com',
          name: 'A',
          author: 'Au',
          origin: 'o',
          originName: 'on',
        ),
      ];
      final p = _makeProvider();
      await Future.delayed(Duration.zero); // 等 constructor async 完成
      expect(p.books, hasLength(1));
    });

    test('loadBooks 不再依 group 欄位過濾', () async {
      fakeBookDao.shelf = [
        Book(
          bookUrl: 'http://a.com',
          name: 'A',
          author: 'Au',
          origin: 'o',
          originName: 'on',
          group: 0,
        ),
        Book(
          bookUrl: 'http://b.com',
          name: 'B',
          author: 'Au',
          origin: 'o',
          originName: 'on',
          group: 2,
        ),
      ];
      final p = _makeProvider();
      await Future.delayed(Duration.zero);
      expect(
        p.books.map((book) => book.bookUrl),
        containsAll(['http://a.com', 'http://b.com']),
      );
    });

    test('removeFromBookshelf 刪除書籍並重新載入', () async {
      fakeBookDao.shelf = [
        Book(
          bookUrl: 'http://a.com',
          name: 'A',
          author: 'Au',
          origin: 'o',
          originName: 'on',
        ),
      ];
      final p = _makeProvider();
      await Future.delayed(Duration.zero);
      await p.removeFromBookshelf('http://a.com');
      expect(p.books, isEmpty);
    });
  });
}

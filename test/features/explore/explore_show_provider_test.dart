import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:reader/core/database/dao/book_dao.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/engine/app_event_bus.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/features/explore/explore_show_provider.dart';

class _FakeBookDao extends Fake implements BookDao {
  List<Book> shelf = [];

  @override
  Future<List<Book>> getInBookshelf() async => shelf;
}

class _FakeSourceDao extends Fake implements BookSourceDao {
  BookSource? source = BookSource(
    bookSourceUrl: 'source://main',
    bookSourceName: '主書源',
  );

  @override
  Future<BookSource?> getByUrl(String url) async => source;
}

Book _makeBook({
  required String bookUrl,
  required String name,
  required String author,
  String origin = 'source://main',
}) {
  return Book(
    bookUrl: bookUrl,
    name: name,
    author: author,
    origin: origin,
    originName: '主書源',
    isInBookshelf: true,
  );
}

SearchBook _makeSearchBook({
  required String bookUrl,
  required String name,
  required String author,
  String origin = 'source://main',
}) {
  return SearchBook(
    bookUrl: bookUrl,
    name: name,
    author: author,
    origin: origin,
    originName: '主書源',
  );
}

Future<void> _settleAsync() async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

void main() {
  late _FakeBookDao fakeBookDao;
  late _FakeSourceDao fakeSourceDao;

  setUp(() {
    fakeBookDao = _FakeBookDao();
    fakeSourceDao = _FakeSourceDao();

    final getIt = GetIt.instance;
    getIt.registerLazySingleton<BookDao>(() => fakeBookDao);
    getIt.registerLazySingleton<BookSourceDao>(() => fakeSourceDao);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  ExploreShowProvider makeProvider() {
    return ExploreShowProvider(
      sourceUrl: 'source://main',
      exploreUrl: 'https://example.com/explore',
      exploreName: '精選',
      exploreLoader: (_, __, {page, cancelToken}) async => [],
    );
  }

  group('ExploreShowProvider - 書架狀態', () {
    test('初始載入只同步相同書源與 bookUrl', () async {
      fakeBookDao.shelf = [
        _makeBook(
          bookUrl: 'https://example.com/books/1',
          name: '測試書',
          author: '作者甲',
        ),
      ];

      final provider = makeProvider();
      await _settleAsync();

      expect(
        provider.isInBookshelf(
          _makeSearchBook(
            bookUrl: 'https://example.com/books/1',
            name: '測試書',
            author: '作者甲',
          ),
        ),
        isTrue,
      );

      expect(
        provider.isInBookshelf(
          _makeSearchBook(
            bookUrl: 'https://example.com/books/1',
            name: '測試書',
            author: '作者甲',
            origin: 'source://other',
          ),
        ),
        isFalse,
      );

      expect(
        provider.isInBookshelf(
          _makeSearchBook(
            bookUrl: 'https://example.com/books/redirected',
            name: '測試書',
            author: '作者甲',
          ),
        ),
        isFalse,
      );

      expect(
        provider.isInBookshelf(
          _makeSearchBook(
            bookUrl: 'https://example.com/books/other',
            name: '其他書',
            author: '作者乙',
          ),
        ),
        isFalse,
      );

      provider.dispose();
    });

    test('收到 upBookshelf 事件後會重新同步書架狀態', () async {
      final provider = makeProvider();
      final targetBook = _makeBook(
        bookUrl: 'https://example.com/books/2',
        name: '事件同步書',
        author: '作者乙',
      );
      final targetSearchBook = _makeSearchBook(
        bookUrl: targetBook.bookUrl,
        name: targetBook.name,
        author: targetBook.author,
      );

      await _settleAsync();
      expect(provider.isInBookshelf(targetSearchBook), isFalse);

      fakeBookDao.shelf = [targetBook];
      AppEventBus().fire(AppEventBus.upBookshelf);
      await _settleAsync();
      expect(provider.isInBookshelf(targetSearchBook), isTrue);

      fakeBookDao.shelf = [];
      AppEventBus().fire(AppEventBus.upBookshelf);
      await _settleAsync();
      expect(provider.isInBookshelf(targetSearchBook), isFalse);

      provider.dispose();
    });
  });

  test('refresh ignores stale in-flight results after cancellation', () async {
    final firstCall = Completer<List<SearchBook>>();
    final secondCall = Completer<List<SearchBook>>();
    var callCount = 0;

    final provider = ExploreShowProvider(
      sourceUrl: 'source://main',
      exploreUrl: 'https://example.com/explore',
      exploreName: '精選',
      exploreLoader: (_, __, {page, cancelToken}) async {
        callCount++;
        if (callCount == 1) {
          cancelToken?.whenCancel.then((_) {
            if (!firstCall.isCompleted) {
              firstCall.complete(<SearchBook>[
                _makeSearchBook(
                  bookUrl: 'https://example.com/books/stale',
                  name: '舊資料',
                  author: '作者甲',
                ),
              ]);
            }
          });
          return firstCall.future;
        }
        return secondCall.future;
      },
    );
    addTearDown(provider.dispose);

    await _settleAsync();
    expect(callCount, 1);

    final refreshFuture = provider.refresh();
    expect(callCount, 2);

    secondCall.complete(<SearchBook>[
      _makeSearchBook(
        bookUrl: 'https://example.com/books/fresh',
        name: '新資料',
        author: '作者乙',
      ),
    ]);

    await refreshFuture;
    await _settleAsync();

    expect(provider.books, hasLength(1));
    expect(provider.books.single.name, '新資料');
  });
}

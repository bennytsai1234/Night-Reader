import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';

class _FakeBookDao extends Fake implements BookDao {
  _FakeBookDao(this.shelfBooks);

  final List<Book> shelfBooks;

  @override
  Future<List<Book>> getInBookshelf() async => List<Book>.from(shelfBooks);

  @override
  Future<Book?> getByUrl(String url) async {
    return shelfBooks.where((book) => book.bookUrl == url).firstOrNull;
  }

  @override
  Future<void> upsert(Book book) async {
    final index = shelfBooks.indexWhere((item) => item.bookUrl == book.bookUrl);
    if (index >= 0) shelfBooks[index] = book;
  }
}

class _ControllableSourceDao extends Fake implements BookSourceDao {
  final Completer<BookSource?> lookup = Completer<BookSource?>();
  int getByUrlCallCount = 0;

  @override
  Future<BookSource?> getByUrl(String url) {
    getByUrlCallCount++;
    return lookup.future;
  }
}

class _FakeChapterDao extends Fake implements ChapterDao {
  @override
  Future<List<BookChapter>> getByBook(String bookUrl) async => const [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  test('BookshelfPage can be constructed', () {
    expect(() => const BookshelfPage(), returnsNormally);
  });

  testWidgets('批次檢查更新期間會鎖定重複操作並顯示進度', (tester) async {
    final book = Book(
      bookUrl: 'https://example.com/book',
      name: '批次測試書',
      author: '作者',
      origin: 'source://batch',
      originName: '批次測試書源',
      isInBookshelf: true,
    );
    final sourceDao = _ControllableSourceDao();
    final preferences = await SharedPreferences.getInstance();
    GetIt.instance.registerSingleton<SharedPreferences>(preferences);
    GetIt.instance.registerLazySingleton<BookDao>(() => _FakeBookDao([book]));
    GetIt.instance.registerLazySingleton<BookSourceDao>(() => sourceDao);
    GetIt.instance.registerLazySingleton<ChapterDao>(() => _FakeChapterDao());

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => BookshelfProvider(),
        child: const MaterialApp(home: BookshelfPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('書架管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批次測試書'));
    await tester.pump();

    await tester.tap(find.byTooltip('批次檢查更新'));
    await tester.pump();

    expect(sourceDao.getByUrlCallCount, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('正在檢查更新（剩 1 本）'), findsOneWidget);

    await tester.tap(find.byTooltip('批次檢查更新'));
    await tester.pump();
    expect(sourceDao.getByUrlCallCount, 1);

    sourceDao.lookup.complete(null);
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('書架'), findsOneWidget);
    expect(find.textContaining('檢查完成'), findsOneWidget);
  });
}

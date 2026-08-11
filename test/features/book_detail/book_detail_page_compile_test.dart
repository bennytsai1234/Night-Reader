import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';

class _FakeBookDao extends Fake implements BookDao {
  _FakeBookDao(this.book);

  Book book;

  @override
  Future<Book?> getByUrl(String url) async => url == book.bookUrl ? book : null;

  @override
  Future<void> upsert(Book value) async {
    book = value.copyWith();
  }
}

class _FakeChapterDao extends Fake implements ChapterDao {
  _FakeChapterDao([this.bookChapters = const <BookChapter>[]]);

  final List<BookChapter> bookChapters;

  @override
  Future<List<BookChapter>> getByBook(String bookUrl) async =>
      List<BookChapter>.from(bookChapters);
}

class _FakeSourceDao extends Fake implements BookSourceDao {
  @override
  Future<BookSource?> getByUrl(String url) async => null;
}

void main() {
  tearDown(() async {
    await GetIt.instance.reset();
  });

  test('BookDetailPage can be constructed', () {
    expect(
      () => BookDetailPage(
        book: Book(
          bookUrl: 'https://example.com/book',
          name: '示例書籍',
          author: '作者',
          origin: 'source://demo',
          originName: '測試書源',
        ),
      ),
      returnsNormally,
    );
  });

  testWidgets('移出書架提示會自動逾時並保留撤銷操作', (tester) async {
    final book = Book(
      bookUrl: 'https://example.com/book',
      name: '示例書籍',
      author: '作者',
      origin: 'source://demo',
      originName: '測試書源',
      isInBookshelf: true,
    );
    GetIt.instance.registerLazySingleton<BookDao>(() => _FakeBookDao(book));
    GetIt.instance.registerLazySingleton<ChapterDao>(() => _FakeChapterDao());
    GetIt.instance.registerLazySingleton<BookSourceDao>(() => _FakeSourceDao());

    await tester.pumpWidget(MaterialApp(home: BookDetailPage(book: book)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('移出書架'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '移出'));
    await tester.pumpAndSettle();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.content, isA<Text>());
    expect((snackBar.content as Text).data, '已移出書架');
    expect(snackBar.action?.label, '撤銷');
    expect(snackBar.persist, isFalse);
    expect(snackBar.duration, const Duration(seconds: 4));

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('目錄搜尋預填 query，零結果可清除並恢復目錄', (tester) async {
    final book = Book(
      bookUrl: 'https://example.com/book-with-toc',
      name: '目錄測試書',
      author: '作者',
      origin: 'source://demo',
      originName: '測試書源',
    );
    final chapters = [
      BookChapter(
        url: 'chapter://1',
        title: '第一章',
        bookUrl: book.bookUrl,
        index: 0,
      ),
      BookChapter(
        url: 'chapter://2',
        title: '第二章',
        bookUrl: book.bookUrl,
        index: 1,
      ),
    ];
    GetIt.instance.registerLazySingleton<BookDao>(() => _FakeBookDao(book));
    GetIt.instance.registerLazySingleton<ChapterDao>(
      () => _FakeChapterDao(chapters),
    );
    GetIt.instance.registerLazySingleton<BookSourceDao>(() => _FakeSourceDao());

    await tester.pumpWidget(MaterialApp(home: BookDetailPage(book: book)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜尋目錄'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '不存在');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.widgetWithText(TextButton, '關閉'));
    await tester.pumpAndSettle();

    expect(find.text('找不到相符章節'), findsOneWidget);
    expect(find.text('搜尋結果 (0/2 章)'), findsOneWidget);

    await tester.tap(find.byTooltip('搜尋目錄'));
    await tester.pumpAndSettle();
    final input = tester.widget<EditableText>(find.byType(EditableText));
    expect(input.controller.text, '不存在');
    await tester.tap(find.widgetWithText(TextButton, '關閉'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '清除搜尋'));
    await tester.pumpAndSettle();
    expect(find.text('找不到相符章節'), findsNothing);
    expect(find.text('目錄 (共 2 章)'), findsOneWidget);
    expect(find.text('第一章'), findsOneWidget);
    expect(find.text('第二章'), findsOneWidget);
  });
}

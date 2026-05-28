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
  @override
  Future<List<BookChapter>> getByBook(String bookUrl) async =>
      const <BookChapter>[];
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
}

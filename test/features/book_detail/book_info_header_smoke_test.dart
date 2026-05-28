import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:reader/core/database/dao/book_dao.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/database/dao/chapter_dao.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/core/models/search_book.dart';
import 'package:reader/features/book_detail/book_detail_provider.dart';
import 'package:reader/features/book_detail/widgets/book_info_header.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_location.dart';
import 'package:reader/features/reader_v2/runtime/reader_v2_open_target.dart';

class _FakeBookDao extends Fake implements BookDao {
  @override
  Future<Book?> getByUrl(String url) async => null;

  @override
  Future<void> upsert(Book book) async {}
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
  setUp(() {
    GetIt.instance.registerLazySingleton<BookDao>(() => _FakeBookDao());
    GetIt.instance.registerLazySingleton<ChapterDao>(() => _FakeChapterDao());
    GetIt.instance.registerLazySingleton<BookSourceDao>(() => _FakeSourceDao());
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets(
    'BookInfoHeader renders consistent primary and secondary actions',
    (tester) async {
      final provider = BookDetailProvider(
        AggregatedSearchBook(
          book: SearchBook(
            bookUrl: 'https://example.com/book/1',
            name: '測試書',
            author: '作者甲',
            origin: 'https://example.com',
            originName: '測試書源',
          ),
          sources: const <String>['測試書源'],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookInfoHeader(
              book: provider.book,
              provider: provider,
              showPhotoView: (_, __) {},
              onEdit: () {},
              showSourceOptions: (_, __) {},
              navigateToReader: (_, __, ___, ____) {},
              showChangeSource: (_, __) {},
              toggleBookshelf: (_, __) async {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.widgetWithText(FilledButton, '開始閱讀'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '放入書架'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '背景下載'), findsNothing);
      expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
      expect(find.byIcon(Icons.library_add), findsOneWidget);
    },
  );

  testWidgets(
    'BookInfoHeader hides background download action for local books',
    (tester) async {
      final provider = BookDetailProvider(
        AggregatedSearchBook(
          book: SearchBook(
            bookUrl: 'file:///books/demo.txt',
            name: '本地書',
            author: '作者乙',
            origin: 'local',
            originName: '本地',
          ),
          sources: const <String>['本地'],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookInfoHeader(
              book: provider.book,
              provider: provider,
              showPhotoView: (_, __) {},
              onEdit: () {},
              showSourceOptions: (_, __) {},
              navigateToReader: (_, __, ___, ____) {},
              showChangeSource: (_, __) {},
              toggleBookshelf: (_, __) async {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('背景下載'), findsNothing);
    },
  );

  testWidgets('BookInfoHeader continue reading 會帶入 charOffset', (tester) async {
    final provider = BookDetailProvider(
      AggregatedSearchBook(
        book: SearchBook(
          bookUrl: 'https://example.com/book/2',
          name: '續讀書',
          author: '作者丙',
          origin: 'https://example.com',
          originName: '測試書源',
        ),
        sources: const <String>['測試書源'],
      ),
    );
    provider.book.chapterIndex = 3;
    provider.book.charOffset = 1200;
    ReaderV2OpenTarget? receivedTarget;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookInfoHeader(
            book: provider.book,
            provider: provider,
            showPhotoView: (_, __) {},
            onEdit: () {},
            showSourceOptions: (_, __) {},
            navigateToReader: (_, __, target, ____) {
              receivedTarget = target;
            },
            showChangeSource: (_, __) {},
            toggleBookshelf: (_, __) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, '繼續閱讀'));

    expect(receivedTarget?.intent, ReaderV2OpenIntent.resume);
    expect(
      receivedTarget?.location,
      const ReaderV2Location(chapterIndex: 3, charOffset: 1200),
    );
  });
}

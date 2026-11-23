import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_switch/source_switch_service.dart';
import 'package:night_reader/features/book_detail/widgets/borrow_chapter_toc.dart';
import 'package:night_reader/features/book_detail/widgets/change_source_sheet.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

/// 借源清單一打開就搜尋；這裡不給結果，讀書源一直等著，清單留在搜尋中。
class _PendingSourceDao extends Fake implements BookSourceDao {
  @override
  Future<List<BookSource>> getEnabled() => Completer<List<BookSource>>().future;
}

class _FakeSearchBookDao extends Fake implements SearchBookDao {}

void main() {
  final book = Book(
    bookUrl: 'https://main.example/book',
    origin: 'https://main.example',
    name: '夜雨聽書',
    author: '沈知秋',
  );
  final chapter = BookChapter(
    url: 'https://main.example/c/2.html',
    title: '第二章',
    index: 1,
    bookUrl: book.bookUrl,
  );
  final source = BookSource(
    bookSourceUrl: 'https://lender.example',
    bookSourceName: '借的書源',
  );
  final lenderBook = Book(
    bookUrl: 'https://lender.example/book',
    origin: source.bookSourceUrl,
    name: book.name,
    author: book.author,
  );
  final toc = SourceToc(lenderBook, [
    BookChapter(title: '第一章', url: '/1', bookUrl: lenderBook.bookUrl),
    BookChapter(title: '第二章', url: '/2', index: 1, bookUrl: lenderBook.bookUrl),
  ]);

  Widget app(Widget home) => MaterialApp(
    theme: buildAppTheme(AppStyle.paper, Brightness.light),
    home: home,
  );

  group('借源面板', () {
    setUp(() {
      GetIt.instance
        ..registerSingleton<BookSourceDao>(_PendingSourceDao())
        ..registerSingleton<SearchBookDao>(_FakeSearchBookDao());
    });
    tearDown(() => GetIt.instance.reset());

    Future<Future<BookSource?>> open(
      WidgetTester tester,
      BorrowFromSource borrowFrom,
    ) async {
      late Future<BookSource?> shown;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => shown = ChangeSourceSheet.showForBorrow(
                context: context,
                book: book,
                chapter: chapter,
                borrowFrom: borrowFrom,
              ),
              child: const Text('借源'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('借源'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('單章借源'), findsOneWidget);
      return shown;
    }

    Future<void> borrow(WidgetTester tester, CancelToken cancelToken) {
      final sheet = tester.widget<ChangeSourceSheet>(
        find.byType(ChangeSourceSheet),
      );
      return sheet.borrow!.borrowFrom(source, toc, 1, cancelToken);
    }

    Future<void> dismiss(WidgetTester tester) async {
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ChangeSourceSheet), findsNothing);
    }

    testWidgets('借好了交回借的書源', (tester) async {
      final shown = await open(tester, (_, _, _, _) async {});
      await borrow(tester, CancelToken());
      await dismiss(tester);
      expect(await shown, same(source));
    });

    testWidgets('借不成、沒借就關掉，交回 null', (tester) async {
      final shown = await open(
        tester,
        (_, _, _, _) async => throw StateError('抓不到'),
      );
      await expectLater(borrow(tester, CancelToken()), throwsStateError);
      await dismiss(tester);
      expect(await shown, isNull);
    });
  });

  group('借的書源的目錄', () {
    Future<List<int>> pump(
      WidgetTester tester,
      List<BookChapter> chapters, {
      required int estimated,
      VoidCallback? onLocked,
    }) async {
      final picked = <int>[];
      await tester.pumpWidget(
        app(
          Scaffold(
            body: BorrowChapterToc(
              chapters: chapters,
              estimated: estimated,
              onPick: picked.add,
              onLocked: onLocked ?? () {},
            ),
          ),
        ),
      );
      return picked;
    }

    testWidgets('一打開就捲到估計的那一章並標出來，點了才借', (tester) async {
      final chapters = [
        for (var i = 0; i < 200; i++)
          BookChapter(title: '第${i + 1}章', url: '/$i', index: i),
      ];
      final picked = await pump(tester, chapters, estimated: 150);

      expect(find.text('第151章'), findsOneWidget);
      expect(find.text('目前'), findsOneWidget);
      expect(find.text('第1章'), findsNothing);

      await tester.tap(find.text('第151章'));
      expect(picked, [150]);
    });

    testWidgets('分卷標題點不了，付費章節只提示', (tester) async {
      var locked = 0;
      final picked = await pump(
        tester,
        [
          BookChapter(title: '第一卷', isVolume: true),
          BookChapter(title: '第一章', url: '/1', index: 1),
          BookChapter(title: '第二章', url: '/2', index: 2, isVip: true),
        ],
        estimated: 1,
        onLocked: () => locked++,
      );

      await tester.tap(find.text('第一卷'));
      await tester.tap(find.text('第二章'));
      expect(picked, isEmpty);
      expect(locked, 1);
    });
  });
}

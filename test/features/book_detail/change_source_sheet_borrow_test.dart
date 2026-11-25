import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/source_switch/source_switch_service.dart';
import 'package:night_reader/features/book_detail/source/book_detail_change_source_provider.dart';
import 'package:night_reader/features/book_detail/widgets/book_toc_chapter_row.dart';
import 'package:night_reader/features/book_detail/widgets/borrow_chapter_toc.dart';
import 'package:night_reader/features/book_detail/widgets/change_source_sheet.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/book/locked_chapter_icon.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';

/// 借的書源：書源管理裡只有它。
class _SourceDao extends Fake implements BookSourceDao {
  _SourceDao(this.source);

  final BookSource source;

  @override
  Future<BookSource?> getByUrl(String url) async =>
      url == source.bookSourceUrl ? source : null;
}

class _FakeSearchBookDao extends Fake implements SearchBookDao {}

/// 借的書源的詳情與目錄。
class _LenderSite extends BookSourceService {
  _LenderSite(this.book, this.chapters);

  final Book book;
  final List<BookChapter> chapters;

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async => this.book;

  @override
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
    bool requireComplete = false,
  }) async => chapters;
}

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
    loginUrl: 'https://lender.example/login',
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
    final candidate = SearchBook(
      bookUrl: lenderBook.bookUrl,
      name: '夜雨听书',
      author: book.author,
      origin: source.bookSourceUrl,
      originName: source.bookSourceName,
    );

    setUp(() {
      ChangeSourceSheet.createProvider = (book) =>
          BookDetailChangeSourceProvider(
              book,
              service: _LenderSite(lenderBook, toc.chapters),
              sourceDao: _SourceDao(source),
              searchBookDao: _FakeSearchBookDao(),
              autoStart: false,
            )
            // 主書源寫繁體、借的書源寫簡體：搜尋照同一本書篩過，照樣列出。
            ..allResults = [candidate]
            ..filteredResults = [candidate]
            ..status = '搜尋完成';
    });
    tearDown(() => ChangeSourceSheet.createProvider = null);

    /// 打開借源面板、點借的書源、點它目錄的第二章。
    Future<Future<BookSource?>> pickChapter(
      WidgetTester tester,
      BorrowFromSource borrowFrom,
    ) async {
      // 手機的直式畫面：面板佔四分之三高。
      tester.view
        ..physicalSize = const Size(1080, 2400)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
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
      await tester.pumpAndSettle();
      expect(find.text('單章借源'), findsOneWidget);

      await tester.tap(find.text('借的書源'));
      await tester.pumpAndSettle();
      // 估計的那一章照目錄的「目前」標出來。
      expect(find.text('目前'), findsOneWidget);
      await tester.tap(find.text('第二章'));
      await tester.pump();
      return shown;
    }

    Future<void> dismiss(WidgetTester tester) async {
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(ChangeSourceSheet), findsNothing);
    }

    testWidgets('點一章就借，借好了面板收起、交回借的書源', (tester) async {
      final picks = <int>[];
      final shown = await pickChapter(tester, (from, toc, index, _) async {
        expect(from, same(source));
        picks.add(index);
      });
      await tester.pump(const Duration(seconds: 1));

      expect(picks, [1]);
      expect(find.byType(ChangeSourceSheet), findsNothing);
      expect(await shown, same(source));
    });

    testWidgets('借的書源要登入：原因與「登入」寫在面板裡、點得到', (tester) async {
      final shown = await pickChapter(
        tester,
        (_, _, _, _) async => throw LoginCheckException('正文需要登入後閱讀'),
      );
      await tester.pump();

      expect(find.textContaining('需要登入'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, '登入').hitTestable(),
        findsOneWidget,
      );
      await dismiss(tester);
      expect(await shown, isNull);
    });

    testWidgets('借的途中按返回：當下就取消，晚到的結果不會再關一次', (tester) async {
      final borrowing = Completer<void>();
      late CancelToken token;
      final shown = await pickChapter(tester, (_, _, _, cancelToken) {
        token = cancelToken;
        return borrowing.future;
      });

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      expect(token.isCancelled, isTrue);
      borrowing.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ChangeSourceSheet), findsNothing);
      // 底下那一頁還在。
      expect(find.text('借源'), findsOneWidget);
      expect(await shown, same(source));
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

    testWidgets('估計的那一章是付費章節：只畫鎖頭，章名照樣是強調色加粗', (tester) async {
      await pump(tester, [
        BookChapter(title: '第一章', url: '/1', index: 0),
        BookChapter(title: '第二章', url: '/2', index: 1, isVip: true),
      ], estimated: 1);

      final row = find.ancestor(
        of: find.text('第二章'),
        matching: find.byType(BookTocChapterRow),
      );
      expect(find.text('目前'), findsNothing);
      expect(
        find.descendant(of: row, matching: find.byType(LockedChapterIcon)),
        findsOneWidget,
      );
      final title = tester.widget<UiText>(
        find.descendant(of: row, matching: find.byType(UiText)),
      );
      final scheme = Theme.of(tester.element(row)).colorScheme;
      expect(title.style?.color, scheme.primary);
      expect(title.style?.fontWeight, FontWeight.w600);
    });
  });
}

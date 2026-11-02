import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/features/bookmarks/bookmarks_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

void main() {
  late AppDatabase db;
  late BookmarkDao dao;
  late HighlightDao highlightDao;

  setUp(() async {
    await GetIt.instance.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = BookmarkDao(db);
    GetIt.instance.registerSingleton<BookmarkDao>(dao);
    highlightDao = HighlightDao(db);
    GetIt.instance.registerSingleton<HighlightDao>(highlightDao);
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Bookmark mark(
    int id,
    String book, {
    int chapter = 0,
    int offset = 0,
    String excerpt = '',
  }) => Bookmark(
    id: id,
    bookName: book,
    bookAuthor: '作者',
    chapterIndex: chapter,
    chapterTitle: '第${chapter + 1}章',
    charOffset: offset,
    excerpt: excerpt,
  );

  /// 資料庫在真的非同步裡回覆，一段一段推進（提示列與資料庫的監看讓
  /// `pumpAndSettle` 等不完）。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 拆掉頁面；取消資料庫監看留下的計時器、提示列都跑完。
  Future<void> closePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  }

  Highlight highlight(
    int id,
    String book, {
    int chapter = 0,
    int offset = 0,
    String quote = '',
  }) => Highlight(
    id: id,
    bookName: book,
    bookAuthor: '作者',
    chapterIndex: chapter,
    chapterTitle: '第${chapter + 1}章',
    charOffset: offset,
    quote: quote,
  );

  Future<void> pumpPage(
    WidgetTester tester,
    List<Bookmark> items, {
    List<Highlight> highlights = const [],
  }) async {
    await tester.runAsync(() async {
      await dao.upsertAll(items);
      await highlightDao.upsertAll(highlights);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: BookmarksPage(initial: items, initialHighlights: highlights),
      ),
    );
    await settle(tester);
  }

  testWidgets('one group per book, the book bookmarked most recently first; '
      'bookmarks in reading order within a book', (tester) async {
    await pumpPage(tester, [
      mark(1, '夜雨聽書', chapter: 3, excerpt: '後面的一句'),
      mark(2, '夜雨聽書', chapter: 1, excerpt: '前面的一句'),
      mark(3, '松煙墨', excerpt: '另一本書'),
    ]);

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('松煙墨'), lessThan(top('夜雨聽書')));
    expect(top('前面的一句'), lessThan(top('後面的一句')));
    expect(find.text('第2章'), findsOneWidget);
    await closePage(tester);
  });

  testWidgets('swiping deletes a bookmark and「復原」brings it back', (
    tester,
  ) async {
    await pumpPage(tester, [mark(1, '夜雨聽書', excerpt: '燈下的字句')]);

    await tester.drag(find.text('燈下的字句'), const Offset(-500, 0));
    await settle(tester);
    expect(await tester.runAsync(dao.getAll), isEmpty);
    expect(find.text('沒有書籤'), findsOneWidget);

    await tester.tap(find.text('復原'));
    await settle(tester);
    expect((await tester.runAsync(dao.getAll))!.single.id, 1);
    expect(find.text('燈下的字句'), findsOneWidget);
    await closePage(tester);
  });

  testWidgets('the 標註 tab lists highlights per book in reading order', (
    tester,
  ) async {
    await pumpPage(
      tester,
      [mark(1, '夜雨聽書', excerpt: '書籤那一句')],
      highlights: [
        highlight(10, '夜雨聽書', chapter: 2, quote: '後面畫的字'),
        highlight(11, '夜雨聽書', chapter: 0, quote: '前面畫的字'),
      ],
    );
    expect(find.text('書籤與標註'), findsOneWidget);
    expect(find.text('書籤那一句'), findsOneWidget);
    expect(find.text('前面畫的字'), findsNothing);

    await tester.tap(find.text('標註'));
    await settle(tester);
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(find.text('書籤那一句'), findsNothing);
    expect(top('前面畫的字'), lessThan(top('後面畫的字')));
    expect(find.byTooltip('匯出標註'), findsOneWidget);
    await closePage(tester);
  });

  testWidgets('swiping deletes a highlight and「復原」brings it back', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const [],
      highlights: [highlight(10, '夜雨聽書', quote: '燈下畫的字')],
    );
    await tester.tap(find.text('標註'));
    await settle(tester);

    await tester.drag(find.text('燈下畫的字'), const Offset(-500, 0));
    await settle(tester);
    expect(await tester.runAsync(highlightDao.getAll), isEmpty);
    expect(find.text('沒有標註'), findsOneWidget);

    await tester.tap(find.text('復原'));
    await settle(tester);
    expect((await tester.runAsync(highlightDao.getAll))!.single.id, 10);
    expect(find.text('燈下畫的字'), findsOneWidget);
    await closePage(tester);
  });
}

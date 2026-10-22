// 書架重讀（書架檢查更新做完、下載完成）時，只有畫面上看得到的內容變了
// 的書卡重建，其他書卡與整頁不動（ADR 0029）。整個 App（記憶體資料庫）
// 跑一次。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';
import 'package:provider/provider.dart';

import '../../support/app_harness.dart';

void main() {
  testWidgets('reloading the shelf rebuilds only the cards whose book looks '
      'different', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary(withContent: false);
    });
    await pumpApp(tester);
    // 開 App 之後的背景工作（書架補下載、檢查更新）跑完。
    await settle(tester, const Duration(seconds: 3));
    expect(find.byType(BookshelfGridTile), findsWidgets);

    final provider = tester
        .element(find.byType(BookshelfPage))
        .read<BookshelfProvider>();
    // 記下重建從哪裡開始：整頁，或某一張書卡自己聽的那本書。
    final rebuilt = <String>[];
    debugOnRebuildDirtyWidget = (element, _) {
      final widget = element.widget;
      if (widget is ValueListenableBuilder<Book>) {
        rebuilt.add(widget.valueListenable.value.name);
      }
      if (widget is BookshelfPage) rebuilt.add('整頁');
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    // 檢查更新做完、什麼都沒變：資料庫裡的書只多了檢查時間。
    await tester.runAsync(() async {
      final dao = getIt<BookDao>();
      for (final book in await dao.getInBookshelf()) {
        await dao.upsert(book.copyWith(lastCheckTime: 1));
      }
      await provider.loadBooks();
    });
    await settle(tester, const Duration(milliseconds: 300));
    expect(rebuilt, isEmpty, reason: '書架沒變，書卡與整頁都不重建');

    // 其中一本讀到下一章（進度線變了）。
    await tester.runAsync(() async {
      final dao = getIt<BookDao>();
      final book = (await dao.getInBookshelf()).firstWhere(
        (book) => book.name == '山海經異聞錄',
      );
      await dao.upsert(book.copyWith(chapterIndex: book.chapterIndex + 30));
      await provider.loadBooks();
    });
    await settle(tester, const Duration(milliseconds: 300));
    expect(rebuilt, ['山海經異聞錄'], reason: '只有那一張書卡重建');
    debugOnRebuildDirtyWidget = null;

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, const Duration(seconds: 3));
    await tester.pump(const Duration(minutes: 1));
  });

  /// 開 App、等開 App 之後的背景工作跑完，回傳書架。
  Future<BookshelfProvider> launch(
    WidgetTester tester, {
    Future<void> Function()? seed,
    bool withContent = false,
  }) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary(withContent: withContent);
      await seed?.call();
    });
    await pumpApp(tester);
    await settle(tester, const Duration(seconds: 3));
    return tester.element(find.byType(BookshelfPage)).read<BookshelfProvider>();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, const Duration(seconds: 3));
    await tester.pump(const Duration(minutes: 1));
  }

  Finder tileOf(String name) => find.ancestor(
    of: find.text(name),
    matching: find.byType(BookshelfGridTile),
  );

  Future<Book> stored(String name) async =>
      (await getIt<BookDao>().getInBookshelf()).firstWhere(
        (book) => book.name == name,
      );

  testWidgets('the progress line follows a book the reader changed in place', (
    tester,
  ) async {
    final provider = await launch(tester);
    // 閱讀器直接改它拿到的那本書（就是書卡手上那個物件），再寫進資料庫。
    // 夜雨聽書本來就是最近讀的那本，讀到後面順序不變。
    final stale = await tester.runAsync(() => stored('夜雨聽書'));
    final book = provider.bookListenable(stale!).value;
    book
      ..chapterIndex = 60
      ..durChapterTime = DateTime.now().millisecondsSinceEpoch;
    await tester.runAsync(() async {
      await getIt<BookDao>().upsert(book);
      await provider.loadBooks();
    });
    await settle(tester, const Duration(milliseconds: 300));
    final line = tester.widget<FractionallySizedBox>(
      find.descendant(
        of: tileOf('夜雨聽書'),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(
      line.widthFactor,
      closeTo(61 / book.totalChapterNum, 1e-9),
      reason: '進度線畫到第 61 章',
    );
    await close(tester);
  });

  testWidgets('tapping a card opens the book where it is now, even if only '
      'things the card does not show changed', (tester) async {
    final provider = await launch(tester, withContent: true);
    // 例如在書籍詳情裡讀了幾頁：閱讀位置變了，書卡上看得到的都沒變。
    await tester.runAsync(() async {
      final book = await stored('夜雨聽書');
      await getIt<BookDao>().upsert(book.copyWith(charOffset: 120));
      await provider.loadBooks();
    });
    await settle(tester, const Duration(milliseconds: 300));

    await tester.tap(tileOf('夜雨聽書'));
    for (
      var i = 0;
      i < 30 && find.byType(ReaderV2Page).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final reader = tester.widget<ReaderV2Page>(find.byType(ReaderV2Page));
    expect(reader.book.charOffset, 120, reason: '從新的位置打開');
    await settle(tester, const Duration(seconds: 1));
    await close(tester);
  });

  testWidgets('the long-press menu shows and flips the book as it is now', (
    tester,
  ) async {
    final provider = await launch(tester);
    // 例如在書籍詳情關掉「自動檢查更新」。
    await tester.runAsync(() async {
      final book = await stored('星河彼岸');
      await getIt<BookDao>().upsert(book.copyWith(canUpdate: false));
      await provider.loadBooks();
    });
    await settle(tester, const Duration(milliseconds: 300));

    await tester.longPress(tileOf('星河彼岸'));
    await settle(tester, const Duration(milliseconds: 600));
    await tester.tap(find.text('自動檢查更新').last);
    await settle(tester, const Duration(milliseconds: 600));
    final book = await tester.runAsync(() => stored('星河彼岸'));
    expect(book!.canUpdate, isTrue, reason: '關著的打開，不是把關著寫回去');
    await close(tester);
  });

  testWidgets('switching the sort mode switches dragging even when the order '
      'stays the same', (tester) async {
    final provider = await launch(
      tester,
      seed: () async {
        // 只留一本：換哪一種排序，順序都一樣。
        final dao = getIt<BookDao>();
        for (final book in await dao.getInBookshelf()) {
          if (book.name != '夜雨聽書') await dao.deleteByUrl(book.bookUrl);
        }
      },
    );
    provider.setGridView(false);
    await settle(tester, const Duration(milliseconds: 600));

    await tester.runAsync(() => provider.setSortMode(BookshelfSortMode.custom));
    await settle(tester, const Duration(milliseconds: 600));
    expect(
      find.byType(ReorderableListView),
      findsOneWidget,
      reason: '自訂排序可以拖曳',
    );

    await tester.runAsync(
      () => provider.setSortMode(BookshelfSortMode.recentRead),
    );
    await settle(tester, const Duration(milliseconds: 600));
    expect(find.byType(ReorderableListView), findsNothing);
    await tester.longPress(find.text('夜雨聽書').last);
    await settle(tester, const Duration(milliseconds: 600));
    expect(find.text('書籍詳情'), findsOneWidget, reason: '長按打開選單，不是拖曳');
    await close(tester);
  });
}

// 書架重讀（書架檢查更新做完、下載完成）時，只有畫面上看得到的內容變了
// 的書卡重建，其他書卡與整頁不動（ADR 0029）。整個 App（記憶體資料庫）
// 跑一次。

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
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
}

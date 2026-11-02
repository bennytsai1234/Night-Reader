// 從分頁推入別的頁面再返回：被蓋住的分頁（書架、「我的」）與主頁都不重建
// （ADR 0018）。整個 App（記憶體資料庫）跑一次。
//
// 等換頁播完用的是量測工具的 `pageSettled`（`test/support/navigation_budget.dart`），
// 和 `test/frame_budget/` 的情境一樣每一幀都看一次：量測工具若讓頁面依賴
// 路由狀態，量過「返回書架」之後的下一趟推入就會多出書架的重建，這裡也會
// 抓到。原本量到的「從我的推入時書架與我的在第 0 格各重建一次」就是這樣來的。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/explore/explore_page.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/settings/backup_sync_page.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/features/welcome/main_page.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';

const _tabPages = {BookshelfPage, ExplorePage, SettingsPage, MainPage};

void main() {
  /// 做 [action]，一幀一幀推進到 [page] 的換頁播完，再停一下。
  Future<void> navigate(
    WidgetTester tester,
    Future<void> Function() action,
    Finder page,
  ) async {
    await action();
    for (var i = 0; i < 200 && !pageSettled(page); i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pageSettled(page), isTrue);
    await settle(tester, const Duration(milliseconds: 500));
  }

  testWidgets('pushing a page over a tab and coming back rebuilds none of the '
      'tab pages', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    await pumpApp(tester);
    // 開 App 之後的背景工作（書架補下載、檢查更新）跑完。
    await settle(tester, const Duration(seconds: 3));

    final rebuilt = <String>[];
    var step = '';
    // 分頁在這之前都已經建好（「我的」在切過去時第一次建，那一段不算）。
    debugOnRebuildDirtyWidget = (element, _) {
      if (_tabPages.contains(element.widget.runtimeType)) {
        rebuilt.add('$step：${element.widget.runtimeType}');
      }
    };
    try {
      for (final round in ['第一趟', '第二趟']) {
        step = '$round 書架→搜尋';
        await navigate(
          tester,
          () => tester.tap(find.byIcon(Icons.search_rounded).last),
          find.byType(SearchPage),
        );
        step = '$round 搜尋返回書架';
        await navigate(
          tester,
          () => goBack(tester),
          find.byType(BookshelfPage),
        );
      }

      step = '切到我的';
      await tester.tap(
        find.descendant(
          of: find.byType(FloatingTabBar),
          matching: find.text('我的'),
        ),
      );
      await settle(tester);
      rebuilt.removeWhere((entry) => entry.startsWith(step));

      for (final round in ['第一趟', '第二趟']) {
        step = '$round 我的→備份與同步';
        await navigate(
          tester,
          () => tester.tap(find.text('備份與同步')),
          find.byType(BackupSyncPage),
        );
        step = '$round 備份與同步返回我的';
        await navigate(tester, () => goBack(tester), find.byType(SettingsPage));
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
    }

    expect(rebuilt, isEmpty);
    await tearDownApp(tester);
  });
}

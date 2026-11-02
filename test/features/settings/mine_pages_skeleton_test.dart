// 從「我的」點進去的設定頁，第一次進去的骨架就和換上的內容一樣（ADR
// 0029）：每一行字、圖示、開關、風格卡與卡片都在內容的位置、一樣大。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/app_version.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import '../../support/app_harness.dart';
import '../../support/skeleton_match.dart';

/// 「我的」本身是分頁，點分頁時直接建；從閱讀器的「更多 → 全域系統設定」
/// 進來時是推入的頁面，同樣先畫骨架。
const _mine = '「我的」（從閱讀器推入）';

const _pages = [_mine, '閱讀偏好', '外觀與主題', '朗讀與語音', '備份與同步', '關於夜讀'];

void main() {
  // App 的單例服務綁在第一個測試的非同步環境（見 app_screens_test），每一頁
  // 在同一個測試裡依序開，之間重建整個 App。
  testWidgets('第一次進去的骨架就和換上的內容一樣', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      // App 啟動時就讀好版號（configureDependencies）。
      await AppVersion.current();
    });
    final problems = <String, List<String>>{};
    for (final page in _pages) {
      await tester.runAsync(() => resetPrefs(const {}));
      await pumpApp(tester);
      if (page == _mine) {
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            );
      } else {
        await tester.tap(find.text('我的').first);
        await settle(tester, const Duration(milliseconds: 900));
        await tester.tap(find.text(page).first);
      }
      await tester.pump();
      final list = find.byType(GroupedListView, skipOffstage: false).last;
      final route = ModalRoute.of(tester.element(list))!;
      expect(route.isFirst, isFalse, reason: page);
      while (!route.animation!.isCompleted) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final skeleton = skeletonLayoutOf(
        tester,
        find.descendant(of: list, matching: find.byType(SkeletonShapes)),
      );
      expect(skeleton.marks, isNotEmpty, reason: page);
      for (var i = 0; i < 100; i++) {
        if (find.byType(SkeletonShapes).evaluate().isEmpty) break;
        await settle(tester, const Duration(milliseconds: 100));
      }
      problems[page] = skeletonMismatches(
        skeleton,
        contentLayoutOf(tester, list),
        visible: tester.getRect(list),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, const Duration(milliseconds: 300));
    }
    expect(problems, {for (final page in _pages) page: isEmpty});
    // 讓 App 留下的計時器跑完，測試才能正常結束。
    await tester.pump(const Duration(minutes: 1));
  });
}

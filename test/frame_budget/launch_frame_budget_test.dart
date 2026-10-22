// 開 App 到書架換場播完、之後一秒的每一幀成本（ADR 0018、0025）。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試
// 跳過。
@Tags(['frame_budget'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/app_providers.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/main.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:provider/provider.dart';

import '../support/app_harness.dart';
import '../support/frame_budget.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('launch until the shelf has turned into content', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    // 第一次開含 debug 模式第一次執行程式的編譯成本（手機上的正式版沒有），
    // 開兩次，看第二次。
    for (final label in ['開 App（第一次，含編譯）', '開 App']) {
      await tester.pumpWidget(
        MultiProvider(
          providers: AppProviders.providers,
          child: const ReaderApp(),
        ),
      );
      var sawSkeleton = false;
      LaunchEntranceMotion? entrance;
      final costs = await recordFrames(
        tester,
        realAsync: true,
        // 書架換場（兩張定格畫面，ADR 0031）在哪一段：拍圖那幾格要多畫一次
        // 換好的畫面，混合那幾格只貼兩張圖。
        note: () {
          final shelf = find.byType(BookshelfPage).evaluate();
          if (shelf.isNotEmpty) {
            entrance ??= LaunchEntrance.maybeOf(shelf.first);
          }
          final screen = entrance?.screen;
          if (screen == null || !screen.isPlaying) return null;
          return screen.progress == null ? '換場前拍圖' : '換場中';
        },
        // 骨架出現過、又全部換成內容，就是整段進場播完；之後再看一秒，開
        // App 的背景工作從這時開始。
        until: () {
          final skeletons = find.byType(SkeletonBox).evaluate().isNotEmpty;
          sawSkeleton |= skeletons;
          return sawSkeleton && !skeletons;
        },
        tailFrames: 60,
      );
      // ignore: avoid_print
      print(describeFrames(label, costs));
      // 拍圖兩格：拍下骨架畫面（記為「換場前拍圖」的那一格，拍在它畫完之後）
      // 與下一格（底下換成內容、畫好後拍下來；螢幕上蓋著骨架那張）。之後
      // 才是只貼兩張圖的換場。
      String ms(int us) => (us / 1000).toStringAsFixed(1);
      final first = costs.indexWhere((cost) => cost.note == '換場前拍圖');
      if (first >= 0 && first + 1 < costs.length) {
        final mixing = [
          for (final cost in costs.skip(first + 2))
            if (cost.note == '換場中') cost.total,
        ]..sort();
        // ignore: avoid_print
        print(
          '  拍圖兩格 ${ms(costs[first].total)}、${ms(costs[first + 1].total)}ms；'
          '換場中 ${mixing.length} 格，中位數 ${ms(mixing[mixing.length ~/ 2])}ms，'
          '最大 ${ms(mixing.last)}ms',
        );
      }
      expect(sawSkeleton, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      // 下載服務是單例，跨兩次開 App；等上一次開 App 排的下載跑完（測試
      // 沒有網路，立刻失敗），它結束時通知書架重新載入，不然會算進下一次。
      await settle(tester, const Duration(seconds: 5));
    }

    // 讓 App 留下的計時器（下載排程、重試）跑完，測試才能正常結束。
    await tester.pump(const Duration(minutes: 1));
  });
}

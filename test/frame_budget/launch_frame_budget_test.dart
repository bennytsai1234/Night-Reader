// 開 App 到書架換場播完、之後一秒的每一幀成本（ADR 0018、0025）。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試
// 跳過。
@Tags(['frame_budget'])
library;

import 'package:flutter/rendering.dart';
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
    // 書架上 30 本書，超過一個畫面，都帶手機裡已有的封面：骨架呼吸時底下
    // 建書卡、解碼封面，換場前等它們畫得出來（ADR 0031）。
    final covers = coverDirectory();
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      await seedMoreBooks(24);
      await seedCovers(covers);
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
      final costs = await recordFrames(
        tester,
        realAsync: true,
        // 書架換場（兩張定格畫面，ADR 0031）只貼兩張圖的那幾格：骨架已經
        // 換掉，頁面上有玻璃，但畫面上沒有在畫的背景模糊。
        // 骨架還在時分成長出與呼吸：骨架長完、等換場的那段，底下在建書卡、
        // 解碼封面。
        note: () {
          if (find.byType(SkeletonBox).evaluate().isNotEmpty) {
            final shelf = find.byType(BookshelfPage).evaluate();
            final entrance = shelf.isEmpty
                ? null
                : LaunchEntrance.maybeOf(shelf.first);
            return entrance?.skeleton.isCompleted ?? false ? '骨架呼吸' : '骨架長出';
          }
          if (find.byType(BackdropFilter).evaluate().isEmpty) return null;
          return _paintsBlur(tester) ? null : '換場中';
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
      // 拍圖兩格在只貼兩張圖的換場之前：拍下骨架畫面的那一格（拍在它畫完
      // 之後），與下一格（底下換成內容、畫好後拍下來；螢幕上蓋著骨架那張）。
      String ms(int us) => (us / 1000).toStringAsFixed(1);
      final first = costs.indexWhere((cost) => cost.note == '換場中');
      // 骨架呼吸的每一格（不含拍下骨架畫面的那一格）單獨列一行，對照表
      // 才看得到這一段。
      final breathing = [
        for (final cost in costs)
          if (cost.note == '骨架呼吸' && (first < 2 || cost.index < first - 2))
            cost,
      ];
      if (breathing.isNotEmpty) {
        // ignore: avoid_print
        print(describeFrames('$label：骨架呼吸', breathing));
      }
      if (first >= 2) {
        final mixing = [
          for (final cost in costs.skip(first))
            if (cost.note == '換場中') cost.total,
        ]..sort();
        // ignore: avoid_print
        print(
          '  拍圖兩格 ${ms(costs[first - 2].total)}、'
          '${ms(costs[first - 1].total)}ms；換場中 ${mixing.length} 格，'
          '中位數 ${ms(mixing[mixing.length ~/ 2])}ms，最大 ${ms(mixing.last)}ms',
        );
      }
      expect(sawSkeleton, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      // 下載服務是單例，跨兩次開 App；等上一次開 App 排的下載跑完（測試
      // 沒有網路，立刻失敗），它結束時通知書架重新載入，不然會算進下一次。
      // 30 本書時 5 秒不夠：第二次開 App 的骨架呼吸裡會多出兩格各約 3ms
      // 的上一次剩下的工作（書架檢查與補下載沒有網路，一直重試；2026-10-23
      // 量到，等 40 秒就沒有）。一次推 1 秒：等的是同樣的 40 秒，不用一格
      // 一格推 800 次。
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump(const Duration(seconds: 1));
      }
    }

    // 讓 App 留下的計時器（下載排程、重試）跑完，測試才能正常結束。
    await tester.pump(const Duration(minutes: 1));
  });
}

/// 這一格畫面上有在畫的背景模糊。
bool _paintsBlur(WidgetTester tester) {
  bool visit(Layer? layer) {
    for (; layer != null; layer = layer.nextSibling) {
      if (layer is BackdropFilterLayer) return true;
      if (layer is ContainerLayer && visit(layer.firstChild)) return true;
    }
    return false;
  }

  return visit(tester.binding.renderViews.first.debugLayer);
}

// 開 App 到書架換場播完、之後一秒的每一幀成本（ADR 0018、0025）。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試
// 跳過。預設是手機；`FRAME_SIZE=1280x880`（寬x高，邏輯像素）改量平板這類
// 其他尺寸。
@Tags(['frame_budget'])
library;

import 'dart:io';

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
    setUpPhone(
      tester,
      size: switch (Platform.environment['FRAME_SIZE']?.split('x')) {
        [final w, final h] => Size(double.parse(w), double.parse(h)),
        _ => null,
      },
    );
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
        // 骨架長完、還沒呼吸的那段（長完停）在底下建書卡、解碼封面、拍兩張
        // 定格畫面（ADR 0035）。書架換場（ADR 0031）只貼兩張圖的那幾格：
        // 頁首與分頁列已經換成真的，但畫面上沒有在畫的背景模糊。
        note: () {
          final shelf = find.byType(BookshelfPage).evaluate();
          final entrance = shelf.isEmpty
              ? null
              : LaunchEntrance.maybeOf(shelf.first);
          if (entrance != null &&
              entrance.revealed.value &&
              !entrance.isFinished) {
            return _paintsBlur(tester) ? null : '換場中';
          }
          if (find.byType(SkeletonBox).evaluate().isEmpty) return null;
          if (!(entrance?.skeleton.isCompleted ?? false)) return '骨架長出';
          return entrance!.breathing.value ? '骨架呼吸' : '長完停';
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
      // 長完停（建書架、拍圖）與骨架呼吸的每一格各列一段，對照表才看得到
      // 這兩段；換場中只列中位數與最大。
      String ms(int us) => (us / 1000).toStringAsFixed(1);
      for (final segment in ['長完停', '骨架呼吸']) {
        final frames = [
          for (final cost in costs)
            if (cost.note == segment) cost,
        ];
        if (frames.isEmpty) continue;
        // ignore: avoid_print
        print(describeFrames('$label：$segment', frames));
      }
      final mixing = [
        for (final cost in costs)
          if (cost.note == '換場中') cost.total,
      ]..sort();
      if (mixing.isNotEmpty) {
        // ignore: avoid_print
        print(
          '  換場中 ${mixing.length} 格，中位數 ${ms(mixing[mixing.length ~/ 2])}ms，'
          '最大 ${ms(mixing.last)}ms',
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

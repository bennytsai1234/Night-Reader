import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_sheet.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_sleep_timer.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import '../../support/app_harness.dart';
import '../../support/glass_motion.dart';
import '../../support/navigation_budget.dart';
import '../../support/screenshot.dart';

/// 閱讀器的三個面板（外觀與排版、朗讀、替換規則）滑入時先只畫骨架，滑到位
/// 才在骨架底下逐列建立內容（ADR 0029）。骨架照真的內容的高度畫：從滑入
/// 第一幀到換成內容，面板的高度一格都不變。
///
/// 換成內容時記下的樣子（`GroupedListLayouts`）留在記憶體裡：先跑的深色是
/// 第一次打開、照估的畫，後跑的淺色照記下的畫，兩種都要一樣高。
void main() {
  setUpAll(loadScreenshotFonts);

  final sheet = find.byType(BottomSheet);
  final skeleton = find.descendant(
    of: sheet,
    matching: find.byType(SkeletonShapes),
  );

  for (final brightness in Brightness.values) {
    testWidgets('三種面板滑入第一幀只畫骨架，換成內容前後高度不變（$brightness）', (tester) async {
      setUpPhone(tester);
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.runAsync(() async {
        await setUpApp();
        await seedLibrary();
      });
      await pumpApp(tester);
      await openReader(tester);
      await showReaderMenu(tester);

      for (final label in ['排版', '朗讀', '替換規則']) {
        // 各面板裡最重的元件：步進列、定時的分段控制、即時測試的輸入框。
        final heavy = switch (label) {
          '排版' => find.byType(NumberStepperRow),
          '朗讀' => find.byType(GlassSegmented<ReaderV2TtsSleepOption>),
          _ => find.byType(TextField),
        };
        await tester.tap(
          label == '替換規則' ? find.byTooltip(label) : find.text(label),
        );
        await tester.pump();
        expect(heavy, findsNothing, reason: '$label 滑入第一幀就建了內容');
        expect(skeleton, findsOneWidget, reason: '$label 滑入第一幀沒有骨架');
        final first = tester.getSize(sheet);

        // 一幀一幀推進到骨架換完再多半秒，每一幀的面板高度都和第一幀一樣。
        var frames = 0;
        var tail = 0;
        while (tail < 30) {
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump(const Duration(milliseconds: 16));
          frames++;
          if (frames == 8) expectNoGlassUnderFade(tester);
          expect(
            tester.getSize(sheet),
            first,
            reason: '$label 第 $frames 幀的高度和滑入第一幀不同',
          );
          if (skeleton.evaluate().isEmpty) tail++;
          expect(frames, lessThan(600), reason: '$label 骨架一直沒換完');
        }
        expect(heavy, findsWidgets, reason: '$label 換場後沒有內容');

        // 骨架墊的底色就是面板本身的底色，關閉鈕維持原樣。
        final contentContext = tester.element(find.byType(GroupedSheetContent));
        final background = label == '替換規則'
            ? AppChrome.of(contentContext).groupedBackground
            : Theme.of(contentContext).colorScheme.surface;
        expect(
          tester
              .widget<GroupedSheetContent>(find.byType(GroupedSheetContent))
              .background,
          background,
        );
        expect(
          tester.widget<BottomSheet>(sheet).backgroundColor,
          label == '替換規則' ? background : Colors.transparent,
        );
        final closeGlass = find.descendant(
          of: find.byTooltip('關閉'),
          matching: find.byType(GlassSurface),
        );
        expect(closeGlass, label == '替換規則' ? findsOneWidget : findsNothing);

        if (label == '替換規則') {
          // 鍵盤出現時面板照舊墊高，輸入框捲得到鍵盤上方。
          tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
          await tester.pump();
          await settle(tester, const Duration(milliseconds: 400));
          final body = find
              .descendant(
                of: find.byType(AppBottomSheet),
                matching: find.byType(SafeArea),
              )
              .first;
          expect(tester.getRect(body).bottom, lessThanOrEqualTo(852 - 300));
          await tester.ensureVisible(heavy);
          await tester.pump();
          expect(tester.getRect(heavy).bottom, lessThanOrEqualTo(852 - 300));
          tester.view.resetViewInsets();
          await tester.pump();
          await settle(tester, const Duration(milliseconds: 400));
        } else {
          expect(
            tester
                .widget<ReaderV2SheetScaffold>(
                  find.byType(ReaderV2SheetScaffold),
                )
                .maxHeightFactor,
            label == '排版' ? 0.6 : 0.9,
          );
        }

        await goBack(tester);
        await rest(tester);
      }
      await tearDownApp(tester);
      await tester.runAsync(() => getIt<AppDatabase>().close());
    });
  }
}

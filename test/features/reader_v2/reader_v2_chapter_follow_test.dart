import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_top_menu.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page_shell.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/shared/widgets/glass.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';

// 整個 App 一個檔案只開一次（setUpApp）。
void main() {
  testWidgets('慢慢拖過章界、自動翻頁捲過章界後，頁尾與選單的章名、上一章／下一章都是新的一章', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    await pumpApp(tester);
    await openReader(tester);
    await rest(tester);

    const centre = Offset(196, 420);
    final screen = tester.widget<HybridReaderScreen>(
      find.byType(HybridReaderScreen),
    );
    final ReaderV2Runtime runtime = screen.runtime;
    int chapter() => runtime.state.visibleLocation.chapterIndex;
    double chapterPercent() =>
        screen.progressListenable?.value?.chapterPercent ?? 0;
    bool menuShown() => find
        .byType(GlassSlide)
        .evaluate()
        .every((e) => (e.widget as GlassSlide).shown == 1);

    /// 頁尾（不在選單裡）的這段字。
    Finder footerText(String text) => find.byElementPredicate(
      (element) =>
          element.widget is Text &&
          (element.widget as Text).data == text &&
          element.findAncestorWidgetOfExactType<ReaderV2TopMenu>() == null &&
          element.findAncestorWidgetOfExactType<ReaderV2PageShell>() != null,
    );

    /// 上方選單章節卡上的章名。
    Finder menuTitle(String text) => find.descendant(
      of: find.byType(ReaderV2TopMenu),
      matching: find.text(text),
    );

    TextButton jumpButton(String label) => tester.widget<TextButton>(
      find.descendant(
        of: find.byType(ReaderV2BottomMenu),
        matching: find.ancestor(
          of: find.text(label),
          matching: find.byType(TextButton),
        ),
      ),
    );

    /// 手指慢慢往上推（不甩），直到 [done]；停住一會兒才放開，不留慣性。
    Future<void> dragSlowlyUntil(bool Function() done) async {
      final gesture = await tester.startGesture(const Offset(196, 600));
      var time = Duration.zero;
      for (var step = 0; step < 400 && !done(); step++) {
        time += const Duration(milliseconds: 16);
        await gesture.moveBy(const Offset(0, -24), timeStamp: time);
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up(timeStamp: time + const Duration(milliseconds: 300));
      await rest(tester);
    }

    Future<void> expectChapterShown(int index, String reason) async {
      final title = kChapterTitles[index];
      final previous = kChapterTitles[index - 1];
      expect(footerText(title), findsOneWidget, reason: '$reason：頁尾章名');
      expect(footerText(previous), findsNothing, reason: '$reason：頁尾章名');
      await tester.tapAt(centre);
      await rest(tester);
      expect(menuShown(), isTrue);
      expect(menuTitle(title), findsOneWidget, reason: '$reason：選單章名');
      expect(menuTitle(previous), findsNothing, reason: '$reason：選單章名');
      expect(jumpButton('上一章').onPressed, isNotNull);
      expect(
        jumpButton('下一章').onPressed != null,
        index < kChapterTitles.length - 1,
        reason: '$reason：下一章能不能按照新的一章',
      );
    }

    expect(chapter(), 2);
    expect(footerText(kChapterTitles[2]), findsOneWidget);

    // 慢慢拖進下一章，停下來。
    await dragSlowlyUntil(() => chapter() == 3);
    expect(chapter(), 3, reason: '拖過章界');
    await expectChapterShown(3, '慢慢拖過章界');
    // 目錄打勾的也是新的一章。
    await tester.tap(find.text('目錄'));
    await rest(tester);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.descendant(
            of: find.byType(ReaderV2ChaptersDrawer),
            matching: find.text(kChapterTitles[3]),
          ),
          matching: find.byType(Row),
        ),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
      reason: '慢慢拖過章界：目錄的目前章',
    );
    await goBack(tester);
    await rest(tester);
    if (menuShown()) {
      await tester.tapAt(centre);
      await rest(tester);
    }

    // 拖到這一章快結束，再讓自動翻頁捲過章界。
    await dragSlowlyUntil(() => chapterPercent() >= 85);
    expect(chapter(), 3);
    await tester.tapAt(centre);
    await rest(tester);
    await tester.tap(find.byTooltip('開始自動翻頁'));
    for (var i = 0; i < 600 && chapter() == 3; i++) {
      await settle(tester, const Duration(milliseconds: 100));
    }
    expect(chapter(), 4, reason: '自動翻頁捲過章界');
    await settle(tester, const Duration(milliseconds: 300));
    await expectChapterShown(4, '自動翻頁捲過章界');

    await tester.tap(find.byTooltip('停止自動翻頁'));
    await rest(tester);
    await tearDownApp(tester);
  });
}

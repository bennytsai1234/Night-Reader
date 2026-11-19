import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader/features/brightness/reader_brightness_bar.dart';
import 'package:night_reader/features/reader/features/menu/reader_bottom_menu.dart';
import 'package:night_reader/features/reader/features/menu/reader_tap_action.dart';
import 'package:night_reader/features/reader/features/menu/reader_top_menu.dart';
import 'package:night_reader/features/reader/text_view/reader_text_view.dart';
import 'package:night_reader/features/reader/screen/reader_page.dart';
import 'package:night_reader/features/reader/screen/reader_page_shell.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';

import '../../support/app_harness.dart';
import '../../support/glass_motion.dart';
import '../../support/navigation_budget.dart';

// 整個 App 一個檔案只開一次（setUpApp），所以和拖動進度條的測試分開放。
void main() {
  testWidgets('叫出、收起選單與從選單開面板時只有選單在滑，閱讀頁、正文與選單裡的按鈕不重建', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp(
        prefs: {
          // 右邊一欄點了翻下一頁，其餘叫出選單。
          PreferKey.readerClickActions: [
            for (var row = 0; row < 3; row++) ...[
              ReaderTapAction.menu.code,
              ReaderTapAction.menu.code,
              ReaderTapAction.nextPage.code,
            ],
          ].join(','),
        },
      );
      await seedLibrary();
    });
    await pumpApp(tester);
    await openReader(tester);
    await rest(tester);

    const centre = Offset(196, 420);
    const rightColumn = Offset(340, 420);
    final runtime = tester
        .widget<ReaderTextView>(find.byType(ReaderTextView))
        .runtime;
    bool menuAt(double shown) => find
        .byType(GlassSlide)
        .evaluate()
        .every((e) => (e.widget as GlassSlide).shown == shown);

    // 先開關一次：開書時目錄才讀好，收著的「上一章／下一章」從停用變成
    // 可按的漸變停在畫面外，第一次滑出來時才播完（ADR 0022），和開關無關。
    await tester.tapAt(centre);
    await rest(tester);
    await tester.tapAt(centre);
    await rest(tester);

    // 數重建。按鈕、文字與圖示只算選單裡的：面板裡也有同樣的元件。
    const menuParts = {GlassIconButton, TextButton, Slider, Text, Icon};
    final rebuilds = <Type, int>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      final type = element.widget.runtimeType;
      if (menuParts.contains(type) &&
          element.findAncestorWidgetOfExactType<ReaderTopMenu>() == null &&
          element.findAncestorWidgetOfExactType<ReaderBottomMenu>() == null) {
        return;
      }
      rebuilds[type] = (rebuilds[type] ?? 0) + 1;
    };
    try {
      await tester.tapAt(centre);
      await rest(tester);
      expect(menuAt(1), isTrue, reason: '點正文叫出選單');
      await tester.tapAt(centre);
      await rest(tester);
      expect(menuAt(0), isTrue, reason: '再點正文收起選單');

      await tester.tapAt(centre);
      await rest(tester);
      await tester.tap(find.text('排版'));
      await tester.pump();
      // 面板建骨架的第一格裡選單還沒開始滑，下一格才出發。
      expect(menuAt(1), isTrue, reason: '選單和面板的第一格錯開');
      await tester.pump(const Duration(milliseconds: 100));
      expectNoGlassUnderFade(tester);
      await rest(tester);
      expect(menuAt(0), isTrue, reason: '開面板時選單收起');
      await goBack(tester);
      await rest(tester);
      expect(menuAt(1), isTrue, reason: '關面板後選單滑回');
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }

    expect(rebuilds[GlassSlide] ?? 0, greaterThan(0), reason: '選單要真的滑動');
    for (final type in [
      ReaderPage,
      ReaderPageShell,
      ReaderTextView,
      ReaderTopMenu,
      ReaderBottomMenu,
      ReaderBrightnessBar,
      ...menuParts,
    ]) {
      expect(rebuilds[type] ?? 0, 0, reason: '選單開關不應重建 $type');
    }

    // 選單開著時長按不選字、點翻頁區不翻頁，都只收起選單。
    final location = runtime.state.visibleLocation;
    await tester.longPressAt(centre);
    await rest(tester);
    expect(find.text('複製'), findsNothing, reason: '選單開著時不能選字');
    expect(menuAt(0), isTrue, reason: '長按正文也收起選單');
    await tester.tapAt(centre);
    await rest(tester);
    expect(menuAt(1), isTrue);
    await tester.tapAt(rightColumn);
    await rest(tester);
    expect(menuAt(0), isTrue, reason: '點翻頁區收起選單');
    expect(runtime.state.visibleLocation, location, reason: '收起選單的那一下不翻頁');

    await tearDownApp(tester);
  });
}

// 點分頁換頁（書架、發現、我的）的每一幀成本，從點下去到換頁播完、骨架
// 換成內容後再一秒（ADR 0018）。用法見 `test/support/frame_budget.dart`；帶
// `frame_budget` 標籤，平常的全套測試跳過。
@Tags(['frame_budget'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('switching tabs', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      await seedSiteSource();
      await installFakeSite();
    });
    await pumpApp(tester);
    await rest(tester);

    Future<void> tapTab(String label) => tester.tap(
      find.descendant(
        of: find.byType(FloatingTabBar),
        matching: find.text(label),
      ),
    );
    bool switched() =>
        tester
            .widget<AppTransitionSwitch>(find.byType(AppTransitionSwitch))
            .outgoing ==
        null;

    // 第一次到發現與我的時分頁才建起來；來回兩輪，第二輪是建好之後的樣子。
    for (final round in ['第一輪', '第二輪']) {
      for (final (from, to) in [
        ('書架', '發現'),
        ('發現', '書架'),
        ('書架', '我的'),
        ('我的', '發現'),
        ('發現', '書架'),
      ]) {
        await measureNavigation(
          tester,
          '$round $from→$to',
          action: () => tapTab(to),
          settled: switched,
        );
        await rest(tester);
      }
    }

    // 發現剛建起來就馬上點回書架（換頁還沒播完、書源還在讀）。
    await measureNavigation(
      tester,
      '我的→發現後立刻→書架',
      action: () async {
        await tapTab('我的');
        await rest(tester);
        await tapTab('發現');
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tapTab('書架');
      },
      settled: switched,
    );

    await tearDownApp(tester);
  });
}

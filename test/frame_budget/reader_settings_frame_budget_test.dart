// 從閱讀器推入「閱讀偏好」再返回：下方選單的「進階」與外觀與排版面板的
// 「更多排版設定」兩個入口，每一幀的成本從點下去到換頁播完後再一秒
// （ADR 0029）。從「我的」推入在 `mine_frame_budget_test.dart`。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試
// 跳過。
@Tags(['frame_budget'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('reading preferences pushed from the reader', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    await pumpApp(tester);
    await rest(tester);
    await openReader(tester);

    final page = find.byType(ReadingSettingsPage);
    final reader = find.byType(ReaderV2Page);
    for (final round in ['第一輪', '第二輪']) {
      await showReaderMenu(tester);
      await measureNavigation(
        tester,
        '$round 閱讀器「進階」→閱讀偏好',
        action: () => tester.tap(find.text('進階')),
        page: page,
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '$round 閱讀偏好返回閱讀器',
        action: () => goBack(tester),
        page: reader,
      );
      await rest(tester);

      await tester.tap(find.text('排版'));
      await rest(tester);
      // 面板只有六成高，「更多排版設定」在捲動範圍的最下面。
      await tester.ensureVisible(find.text('更多排版設定'));
      await rest(tester);
      await measureNavigation(
        tester,
        '$round 外觀與排版「更多排版設定」→閱讀偏好',
        action: () => tester.tap(find.text('更多排版設定')),
        page: page,
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '$round 閱讀偏好返回外觀與排版',
        action: () => goBack(tester),
        settled: () => page.evaluate().isEmpty,
      );
      await rest(tester);
      // 收起面板與選單，下一輪從正文重新叫出選單。
      await goBack(tester);
      await rest(tester);
      await goBack(tester);
      await rest(tester);
    }

    await tearDownApp(tester);
  });
}

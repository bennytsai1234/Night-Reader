// 發現的換頁：點分類進書單、書單點書進書籍詳情、再一路返回，每一幀的成本
// 從點下去到換頁播完、骨架換成內容後再一秒（ADR 0018）。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試
// 跳過。網頁從記憶體晚 0.3 秒回應（`installFakeSite`）。
@Tags(['frame_budget'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/explore/explore_page.dart';
import 'package:night_reader/features/explore/explore_show_page.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('explore categories and books', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      await seedSiteSource();
      await installFakeSite();
    });
    await pumpApp(tester);
    await rest(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingTabBar),
        matching: find.text('發現'),
      ),
    );
    await rest(tester);
    await tester.tap(find.text(kSiteName));
    await rest(tester);

    // 第一次含程式第一次執行的成本；三個分類各走一趟，看後兩趟。
    for (final kind in ['最新', '熱門', '完本']) {
      await measureNavigation(
        tester,
        '點「$kind」進書單',
        action: () => tester.tap(find.text(kind)),
        page: find.byType(ExploreShowPage),
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '「$kind」書單點書進詳情',
        action: () => tester.tap(find.text('夜讀第0卷').first),
        page: find.byType(BookDetailPage),
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '詳情返回「$kind」書單',
        action: () => goBack(tester),
        page: find.byType(ExploreShowPage),
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '「$kind」書單返回發現',
        action: () => goBack(tester),
        page: find.byType(ExplorePage),
      );
      await rest(tester);
    }

    await tearDownApp(tester);
  });
}

// 開書的換頁：書架進書籍詳情、詳情按「繼續閱讀」進閱讀器、閱讀器退回詳情與
// 書架，以及書架直接開閱讀器再退回，每一幀的成本從點下去到換頁播完、骨架
// 換成內容（閱讀器是正文排好、紙掀開）後再一秒（ADR 0018）。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試
// 跳過。
@Tags(['frame_budget'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/loading_veil.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

bool _veilCovering() => find
    .byType(LoadingVeil)
    .evaluate()
    .any((e) => (e.widget as LoadingVeil).controller.isVisible);

/// 閱讀器進場播完、載入的紙掀開（掀完後紙從元件樹拿掉）。
bool _readerShown() =>
    pageSettled(find.byType(ReaderV2Page)) && !_veilCovering();

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('opening books', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      await installFakeSite();
    });
    await pumpApp(tester);
    await rest(tester);

    for (final round in ['第一輪', '第二輪']) {
      await tester.longPress(find.text('夜雨聽書').first);
      await rest(tester);
      await measureNavigation(
        tester,
        '$round 書架長按選單→書籍詳情',
        action: () => tester.tap(find.text('書籍詳情')),
        page: find.byType(BookDetailPage),
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '$round 詳情「繼續閱讀」→閱讀器',
        action: () => tester.tap(find.text('繼續閱讀')),
        settled: _readerShown,
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '$round 閱讀器返回詳情',
        action: () => goBack(tester),
        page: find.byType(BookDetailPage),
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '$round 詳情返回書架',
        action: () => goBack(tester),
        page: find.byType(BookshelfPage),
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '$round 書架點書→閱讀器',
        action: () => tester.tap(find.text('夜雨聽書').first),
        settled: _readerShown,
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '$round 閱讀器返回書架',
        action: () => goBack(tester),
        page: find.byType(BookshelfPage),
      );
      await rest(tester);
    }

    await tearDownApp(tester);
  });
}

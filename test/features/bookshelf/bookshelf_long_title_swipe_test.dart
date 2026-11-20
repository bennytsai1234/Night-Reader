// 書架列表檢視的書卡上橫拖是主畫面換分頁（bookshelf_card_swipe_test）。
// 書名放不下時收在「…」、不能拖，在書名上橫拖一樣是換分頁。

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book.dart';

import '../../support/app_harness.dart';

void main() {
  const longTitle = '三體之後：一部很長很長很長的書名測試，還有更多更多更多更多更多的字';

  /// 手機上清單與 PageView 用裝置的觸控門檻（Android 約 8）。
  void useDeviceTouchSlop(WidgetTester tester) {
    tester.view.gestureSettings = ui.GestureSettings(
      physicalTouchSlop: 8 * tester.view.devicePixelRatio,
    );
  }

  double page(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView).first).controller!.page!;

  testWidgets('在放不下的書名上往左拖：書名不動，直接換分頁', (tester) async {
    setUpPhone(tester);
    useDeviceTouchSlop(tester);
    await tester.runAsync(() async {
      await setUpApp(prefs: {'bookshelf_is_grid': false});
      await seedLibrary(withContent: false);
      await getIt<BookDao>().upsertAll([
        Book(
          bookUrl: '${kBookUrl}long-title/',
          origin: kOrigin,
          originName: '筆趣閣',
          name: longTitle,
          author: '測試',
          latestChapterTitle: '第1章',
          totalChapterNum: 10,
          durChapterTitle: '第1章',
          durChapterTime: DateTime.now().millisecondsSinceEpoch,
          isInBookshelf: true,
        ),
      ]);
    });
    await pumpApp(tester);

    final title = find.text(longTitle);
    expect(title, findsOneWidget);
    expect(
      find.ancestor(of: title, matching: find.byType(SingleChildScrollView)),
      findsNothing,
      reason: '書架的書名放不下時收在「…」，不能拖',
    );

    final gesture = await tester.startGesture(tester.getCenter(title));
    for (var i = 0; i < 2; i++) {
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(page(tester), greaterThan(0), reason: '分頁跟著手指');
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await settle(tester, const Duration(seconds: 1));
    expect(page(tester), 1, reason: '放開後停到下一頁');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  });
}

// 書架列表檢視的書卡上橫拖是主畫面換分頁（bookshelf_card_swipe_test）。
// 書名放不下時那一行可以左右拖；同一手勢拖到字尾後，剩下的位移接著換分頁。

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';

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

  testWidgets('在放不下的書名上往左拖到字尾：同一手勢接著換分頁', (tester) async {
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
    final line = find.ancestor(
      of: title,
      matching: find.byType(SingleChildScrollView),
    );
    expect(line, findsOneWidget, reason: '這本書的書名放不下，那一行可以拖');
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: line, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.maxScrollExtent, greaterThan(0));

    final gesture = await tester.startGesture(tester.getCenter(title));
    var finger = 0.0;
    for (var i = 0; i < 2; i++) {
      await gesture.moveBy(const Offset(-40, 0));
      finger += 40;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, greaterThan(0), reason: '字跟著手指');
    expect(page(tester), 0, reason: '字還沒到字尾，分頁不動');

    // 同一手勢拖過字尾半頁：字停在字尾，剩下的位移換分頁。
    while (finger < position.maxScrollExtent + 260) {
      await gesture.moveBy(const Offset(-40, 0));
      finger += 40;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, position.maxScrollExtent, reason: '字停在字尾');
    expect(page(tester), greaterThan(0), reason: '剩下的位移換分頁');
    await gesture.up();
    await settle(tester, const Duration(seconds: 1));
    expect(page(tester), 1, reason: '放開後停到下一頁');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  });
}

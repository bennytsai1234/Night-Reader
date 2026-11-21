import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/text/drag_overflow_text.dart';

void main() {
  const longLabel = '這是一個非常非常長的書籍名稱，需要讓讀者手動拖動查看';

  Widget testPage(String label, {int maxLines = 1, double width = 112}) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: DragOverflowText(
              child: Text(
                label,
                style: const TextStyle(fontSize: 18),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 在 `PageView` 的一頁放一條放不下的長文字；回傳分頁、那一行與捲動位置。
  Future<(PageController, Finder, ScrollPosition)> pumpPagedLine(
    WidgetTester tester, {
    ScrollPhysics? physics,
    double viewportFraction = 1,
    int pages = 2,
    int textPage = 0,
  }) async {
    final controller = PageController(viewportFraction: viewportFraction);
    final linePage = ListView(
      children: const [
        SizedBox(
          width: 112,
          child: DragOverflowText(child: Text(longLabel, maxLines: 1)),
        ),
        SizedBox(height: 600),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PageView(
          controller: controller,
          physics: physics,
          children: [
            for (var i = 0; i < pages; i++)
              if (i == textPage)
                linePage
              else
                Center(child: Text('第${i + 1}頁')),
          ],
        ),
      ),
    );
    if (textPage != 0) {
      controller.jumpToPage(textPage);
      await tester.pump();
    }
    final line = find.byType(SingleChildScrollView);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: line, matching: find.byType(Scrollable)),
        )
        .position;
    return (controller, line, position);
  }

  testWidgets('unlimited long text still wraps and never becomes a marquee', (
    tester,
  ) async {
    const label = '可換行的長篇說明應保留原本的自然段落，不應因為寬度不足被誤判成單行拖動';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            child: DragOverflowText(child: Text(label)),
          ),
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(DragOverflowText),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(find.text(label), findsOneWidget);
  });

  testWidgets('long labels have no ellipsis and scroll only when dragged', (
    tester,
  ) async {
    const label = '這是一個非常非常長的書籍名稱，需要讓讀者手動拖動查看';
    await tester.pumpWidget(testPage(label));

    final view = find.descendant(
      of: find.byType(DragOverflowText),
      matching: find.byType(SingleChildScrollView),
    );
    expect(view, findsOneWidget);
    final scrollable = find.descendant(
      of: view,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, 0);

    final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
    expect(paragraph.didExceedMaxLines, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(position.pixels, 0, reason: '文字不會自動滾動');

    await tester.drag(view, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
  });

  testWidgets('two-line labels stay two lines until they genuinely overflow', (
    tester,
  ) async {
    await tester.pumpWidget(testPage('兩行以內的文字內容', maxLines: 2));
    expect(
      find.descendant(
        of: find.byType(DragOverflowText),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );

    await tester.pumpWidget(testPage('兩行也放不下的特別特別長的書名與作者資訊', maxLines: 2));
    expect(
      find.descendant(
        of: find.byType(DragOverflowText),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an overflowing two-line label keeps its first line wrapped and '
      'drags only the last line', (tester) async {
    const label = '兩行也放不下的特別特別長的書名與作者資訊';
    await tester.pumpWidget(testPage(label, maxLines: 2));
    final texts = tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byType(DragOverflowText),
            matching: find.byType(RichText),
          ),
        )
        .map((text) => text.text.toPlainText())
        .toList();
    expect(texts, hasLength(2));
    expect(texts.join(), label, reason: '兩段字接起來就是整段');
    final head = tester.renderObject<RenderParagraph>(find.text(texts.first));
    expect(
      head
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: texts.first.length),
          )
          .map((box) => box.top)
          .toSet(),
      hasLength(1),
      reason: '第一行照常換行',
    );
    final view = find.descendant(
      of: find.byType(DragOverflowText),
      matching: find.byType(SingleChildScrollView),
    );
    expect(
      tester.getTopLeft(view).dy,
      greaterThan(tester.getTopLeft(find.text(texts.first)).dy),
      reason: '可拖的是第二行',
    );
    // 高度和原本兩行的字一樣，書卡上下不移位。
    final height = tester.getSize(find.byType(DragOverflowText)).height;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 112,
              child: Text(
                label,
                style: const TextStyle(fontSize: 18),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
    expect(height, tester.getSize(find.text(label)).height);
  });

  testWidgets('line breaks in the dragged line become spaces', (tester) async {
    await tester.pumpWidget(testPage('第一行\n第二行\n第三行', maxLines: 2));
    final texts = tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byType(DragOverflowText),
            matching: find.byType(RichText),
          ),
        )
        .map((text) => text.text.toPlainText())
        .toList();
    expect(texts, ['第一行', '第二行 第三行']);
  });

  testWidgets('dragging a label does not accidentally tap its card', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GestureDetector(
              onTap: () => taps++,
              child: const SizedBox(
                width: 100,
                child: DragOverflowText(
                  child: Text(
                    '很長很長很長很長的選單項目文字',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(DragOverflowText), const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(taps, 0);
    await tester.tap(find.byType(DragOverflowText));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('at its edge a dragged line hands the drag to the row', (
    tester,
  ) async {
    var outer = 0.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: GestureDetector(
              onHorizontalDragUpdate: (details) => outer += details.delta.dx,
              child: const SizedBox(
                width: 112,
                child: DragOverflowText(
                  child: Text('這是一個非常非常長的書籍名稱，需要讓讀者手動拖動查看', maxLines: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    // 在左邊往右拖：文字拖不動，交給外層。
    await tester.drag(find.byType(DragOverflowText), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(outer, greaterThan(0));
    expect(position.pixels, 0);
    // 往左拖：拖的是文字。
    outer = 0;
    await tester.drag(find.byType(DragOverflowText), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(outer, 0);
    expect(position.pixels, greaterThan(0));
  });

  testWidgets('dragging past the end of a line keeps dragging the pager', (
    tester,
  ) async {
    final (controller, line, position) = await pumpPagedLine(tester);

    final gesture = await tester.startGesture(tester.getCenter(line));
    var stamp = const Duration(milliseconds: 16);
    for (var i = 0; i < 40 && position.pixels < position.maxScrollExtent; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-40, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, position.maxScrollExtent);
    expect(controller.page, lessThan(0.1), reason: '字拖到邊界前分頁幾乎不動');

    // 同一手勢再拖過半頁：字停在字尾，位移改拖分頁。
    for (var i = 0; i < 7; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-40, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, position.maxScrollExtent, reason: '字留在字尾');
    expect(controller.page, greaterThan(0), reason: '分頁跟著手指');

    await gesture.up(timeStamp: stamp + const Duration(milliseconds: 16));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(controller.page, 1, reason: '放開後停到下一頁');
  });

  testWidgets('holding still after the handoff does not snap the page', (
    tester,
  ) async {
    final (controller, line, position) = await pumpPagedLine(tester);

    final gesture = await tester.startGesture(tester.getCenter(line));
    var stamp = const Duration(milliseconds: 16);
    for (var i = 0; i < 40 && position.pixels < position.maxScrollExtent; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-40, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (var i = 0; i < 4; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-40, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    final held = controller.page!;
    expect(held, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.page, closeTo(held, 0.001), reason: '手指還按著，分頁不會自己吸附');

    await gesture.up(timeStamp: stamp + const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(controller.page, 0, reason: '拖不到半頁，放開回原頁');
  });

  testWidgets('a slow start with the device touch slop drags the line first', (
    tester,
  ) async {
    tester.view.gestureSettings = const ui.GestureSettings(
      physicalTouchSlop: 8,
    );
    final (controller, line, position) = await pumpPagedLine(tester);

    final gesture = await tester.startGesture(tester.getCenter(line));
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(-4, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, greaterThan(0), reason: '書名先動');
    expect(controller.page, 0, reason: '分頁還沒被拖走');
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('at the last page the line still drags back', (tester) async {
    final (controller, line, position) = await pumpPagedLine(
      tester,
      textPage: 1,
    );

    await tester.drag(line, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);

    final gesture = await tester.startGesture(tester.getCenter(line));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.page, 1, reason: '分頁留在末頁');
    expect(
      position.pixels,
      lessThan(position.maxScrollExtent),
      reason: '反向拉回字',
    );
    await gesture.up();
  });

  testWidgets('a single-page pager does not steal the reverse drag', (
    tester,
  ) async {
    final (controller, line, position) = await pumpPagedLine(tester, pages: 1);

    await tester.drag(line, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);

    final gesture = await tester.startGesture(tester.getCenter(line));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.page, 0);
    expect(
      position.pixels,
      lessThan(position.maxScrollExtent),
      reason: '分頁只有一頁，反向仍然拉回字',
    );
    await gesture.up();
  });

  testWidgets('a cancelled drag does not fling to the next page', (
    tester,
  ) async {
    final (controller, line, position) = await pumpPagedLine(tester);

    final gesture = await tester.startGesture(tester.getCenter(line));
    var stamp = const Duration(milliseconds: 16);
    for (var i = 0; i < 40 && position.pixels < position.maxScrollExtent; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-40, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (var i = 0; i < 4; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-40, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.page, greaterThan(0));

    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(controller.page, 0, reason: '取消後回原頁，不甩到下一頁');
  });

  testWidgets('starting at the line edge hands the drag to the pager', (
    tester,
  ) async {
    final (controller, line, position) = await pumpPagedLine(tester);

    await tester.drag(line, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
    expect(controller.page, 0);

    final gesture = await tester.startGesture(tester.getCenter(line));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.page, greaterThan(0), reason: '字已在邊界，外層接手');
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a narrow page still settles to the right page', (tester) async {
    final (controller, line, position) = await pumpPagedLine(
      tester,
      viewportFraction: 0.8,
    );

    final gesture = await tester.startGesture(tester.getCenter(line));
    var stamp = const Duration(milliseconds: 16);
    for (var i = 0; i < 40 && position.pixels < position.maxScrollExtent; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-40, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (var i = 0; i < 10; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-40, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up(timeStamp: stamp + const Duration(milliseconds: 16));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(controller.page, 1, reason: '非滿寬頁也停在整個分頁');
  });

  testWidgets('locking the pager mid-gesture does not use the old position', (
    tester,
  ) async {
    final (controller, line, position) = await pumpPagedLine(tester);

    final gesture = await tester.startGesture(tester.getCenter(line));
    var stamp = const Duration(milliseconds: 16);
    for (var i = 0; i < 40 && position.pixels < position.maxScrollExtent; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-40, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (var i = 0; i < 2; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-40, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(controller.page, greaterThan(0));

    // 手勢途中把分頁鎖住：Flutter 會換掉 ScrollPosition。
    await tester.pumpWidget(
      MaterialApp(
        home: PageView(
          controller: controller,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            ListView(
              children: const [
                SizedBox(
                  width: 112,
                  child: DragOverflowText(child: Text(longLabel, maxLines: 1)),
                ),
                SizedBox(height: 600),
              ],
            ),
            const Center(child: Text('第二頁')),
          ],
        ),
      ),
    );
    stamp += const Duration(milliseconds: 16);
    await gesture.moveBy(const Offset(-40, 0), timeStamp: stamp);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);

    await gesture.up(timeStamp: stamp + const Duration(milliseconds: 16));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a locked pager does not take the drag past the line edge', (
    tester,
  ) async {
    final (controller, line, position) = await pumpPagedLine(
      tester,
      physics: const NeverScrollableScrollPhysics(),
    );

    final gesture = await tester.startGesture(tester.getCenter(line));
    for (var i = 0; i < 40 && position.pixels < position.maxScrollExtent; i++) {
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, position.maxScrollExtent);
    expect(controller.page, 0, reason: '分頁鎖住時留在原頁');
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.page, 0);
  });

  testWidgets('the system letter spacing counts when measuring', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(letterSpacingOverride: 4),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 100,
                child: DragOverflowText(
                  child: Text(
                    '12345678',
                    maxLines: 1,
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('line breaks in mixed-style text become spaces too', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 112,
              child: DragOverflowText(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '第一段很長很長很長\n'),
                      TextSpan(text: '第二段', style: TextStyle(fontSize: 20)),
                    ],
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final shown = tester
        .widget<RichText>(
          find.descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(RichText),
          ),
        )
        .text
        .toPlainText();
    expect(shown, '第一段很長很長很長 第二段');
  });
}

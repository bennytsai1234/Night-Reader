import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/drag_overflow_text.dart';

void main() {
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

  testWidgets('short labels retain their original layout', (tester) async {
    await tester.pumpWidget(testPage('短文字', maxLines: 2));
    expect(
      find.descendant(
        of: find.byType(DragOverflowText),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(find.text('短文字'), findsOneWidget);
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

    await tester.pumpWidget(
      testPage('兩行也放不下的特別特別長的書名與作者資訊', maxLines: 2),
    );
    expect(
      find.descendant(
        of: find.byType(DragOverflowText),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
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
}

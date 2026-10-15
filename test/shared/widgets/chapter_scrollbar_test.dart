import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/chapter_scrollbar.dart';

void main() {
  const extent = 50.0;

  Future<ScrollController> pumpList(WidgetTester tester, int count) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    (int, int)? visibleRange() {
      if (!controller.hasClients) return null;
      final p = controller.position;
      final first = (p.pixels / extent).floor();
      final last = ((p.pixels + p.viewportDimension) / extent).ceil() - 1;
      return (first, last.clamp(0, count - 1));
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterScrollbar(
            itemCount: count,
            visibleRange: visibleRange,
            onJumpTo: (index) => controller.jumpTo(
              (index * extent).clamp(0.0, controller.position.maxScrollExtent),
            ),
            labelFor: (index) => '第 $index 章',
            child: ListView.builder(
              controller: controller,
              itemExtent: extent,
              itemCount: count,
              itemBuilder: (_, index) => Text('row $index'),
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  Finder thumb() => find.bySemanticsLabel('快速捲動目錄');

  testWidgets('a long list shows a thumb that jumps to the end', (
    tester,
  ) async {
    final controller = await pumpList(tester, 1000);
    expect(thumb(), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(thumb(), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(thumb()));
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(const Offset(0, 2000));
    await tester.pump();
    expect(find.textContaining('章'), findsOneWidget);
    expect(controller.offset, controller.position.maxScrollExtent);

    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('章'), findsNothing);
  });

  testWidgets('a short list never shows the thumb', (tester) async {
    await pumpList(tester, 30);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(thumb(), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/chapter_scrollbar.dart';
import 'package:night_reader/shared/widgets/glass.dart';

import '../../support/glass_motion.dart';

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

  testWidgets('dragging while the thumb fades in keeps the bubble out of it', (
    tester,
  ) async {
    await pumpList(tester, 1000);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final gesture = await tester.startGesture(tester.getCenter(thumb()));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    expect(find.textContaining('章'), findsOneWidget);
    // 章名泡泡是玻璃，拖曳鈕還在淡入也不能包在淡入裡（ADR 0022）。
    expectNoGlassUnderFade(tester);
    await gesture.up();
  });

  testWidgets('the name bubble grows from the thumb side and shrinks back', (
    tester,
  ) async {
    await pumpList(tester, 1000);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final gesture = await tester.startGesture(tester.getCenter(thumb()));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    Rect bubble() => tester.getRect(find.byType(GlassSurface));
    // 第一幀從 0 開始，不整塊冒出來。
    expect(bubble().width, lessThan(1));

    await tester.pump(const Duration(milliseconds: 60));
    final growing = bubble();
    expectNoGlassUnderFade(tester);
    await tester.pump(const Duration(milliseconds: 300));
    final rest = bubble();
    expect(growing.width, inExclusiveRange(0, rest.width));
    // 靠拖曳鈕的右緣不動。
    expect(growing.right, closeTo(rest.right, 0.5));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(bubble().width, inExclusiveRange(0, rest.width));
    expect(bubble().right, closeTo(rest.right, 0.5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(GlassSurface), findsNothing);
  });

  testWidgets('a short list never shows the thumb', (tester) async {
    await pumpList(tester, 30);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(thumb(), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';

void main() {
  const segments = [
    GlassSegment(0, '不轉換'),
    GlassSegment(1, '簡轉繁'),
    GlassSegment(2, '繁轉簡', icon: Icons.translate),
  ];

  /// 受控用法：外層保存選取值，回傳每次 onChanged 的值。
  Future<List<int>> pump(WidgetTester tester, {int initial = 0}) async {
    final changes = <int>[];
    var selected = initial;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: StatefulBuilder(
                builder: (context, setState) => GlassSegmented<int>(
                  segments: segments,
                  selected: selected,
                  onChanged: (value) {
                    changes.add(value);
                    setState(() => selected = value);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return changes;
  }

  SemanticsNode node(WidgetTester tester, String label) =>
      tester.getSemantics(find.text(label));

  bool isSelected(WidgetTester tester, String label) =>
      isSemantics(isSelected: true).matches(node(tester, label), {});

  testWidgets('點擊分段回報新值並更新選取狀態', (tester) async {
    final handle = tester.ensureSemantics();
    final changes = await pump(tester);
    expect(isSelected(tester, '不轉換'), isTrue);

    await tester.tap(find.text('簡轉繁'));
    await tester.pumpAndSettle();

    expect(changes, [1]);
    expect(isSelected(tester, '簡轉繁'), isTrue);
    expect(isSelected(tester, '不轉換'), isFalse);
    handle.dispose();
  });

  testWidgets('點擊已選分段不重複回報', (tester) async {
    final changes = await pump(tester, initial: 1);
    await tester.tap(find.text('簡轉繁'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
  });

  testWidgets('從選取塊拖到最後一段，放開後選取該段', (tester) async {
    final changes = await pump(tester);
    final start = tester.getCenter(find.text('不轉換'));
    final end = tester.getCenter(find.text('繁轉簡'));
    await tester.dragFrom(start, end - start);
    await tester.pumpAndSettle();
    expect(changes, [2]);
  });

  testWidgets('從未選取的分段開始拖動不移動選取', (tester) async {
    final changes = await pump(tester);
    final start = tester.getCenter(find.text('簡轉繁'));
    await tester.dragFrom(start, const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
  });

  testWidgets('選取值不在分段中時不選取任何分段，點擊仍可選取', (tester) async {
    final handle = tester.ensureSemantics();
    final changes = await pump(tester, initial: 7);
    for (final s in segments) {
      expect(isSelected(tester, s.label), isFalse);
    }
    await tester.tap(find.text('繁轉簡'));
    await tester.pumpAndSettle();
    expect(changes, [2]);
    expect(isSelected(tester, '繁轉簡'), isTrue);
    handle.dispose();
  });

  testWidgets('每個分段是可由無障礙點擊的按鈕', (tester) async {
    final handle = tester.ensureSemantics();
    final changes = await pump(tester);
    final semantics = node(tester, '繁轉簡');
    expect(semantics, isSemantics(isButton: true, hasTapAction: true));
    semantics.owner!.performAction(semantics.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(changes, [2]);
    handle.dispose();
  });
}

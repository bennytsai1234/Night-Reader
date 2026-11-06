import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/group_filter_bar.dart';

void main() {
  Future<List<String?>> pumpBar(
    WidgetTester tester, {
    String? selected,
    List<String> groups = const ['精品', '男頻', '女頻'],
  }) async {
    final changes = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: GroupFilterBar<String?>(
              all: const GroupFilterOption<String?>(null, '全部', count: 12),
              groups: [
                for (var i = 0; i < groups.length; i++)
                  GroupFilterOption<String?>(
                    groups[i],
                    groups[i],
                    count: i + 1,
                  ),
              ],
              selected: selected,
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return changes;
  }

  testWidgets('shows every group with its source count', (tester) async {
    await pumpBar(tester);

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('精品'), findsOneWidget);
    expect(find.text('女頻'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('reports a different group and ignores the selected one', (
    tester,
  ) async {
    final changes = await pumpBar(tester, selected: '男頻');

    await tester.tap(find.text('男頻'));
    await tester.tap(find.text('精品'));
    await tester.tap(find.text('全部'));

    expect(changes, ['精品', null]);
  });

  testWidgets('picker sheet lists, filters and applies groups', (tester) async {
    final changes = await pumpBar(
      tester,
      selected: '精品',
      groups: [for (var i = 0; i < 20; i++) '分組$i'],
    );

    await tester.tap(find.bySemanticsLabel('全部分組'));
    await tester.pumpAndSettle();
    expect(find.text('選擇分組'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '分組1');
    await tester.pump();
    final sheet = find.byType(BottomSheet);
    // 分組1 與 分組10–19 符合，「全部」在篩選時隱藏。
    expect(
      find.descendant(of: sheet, matching: find.byType(GlassCapsule)),
      findsNWidgets(11),
    );
    expect(find.descendant(of: sheet, matching: find.text('全部')), findsNothing);

    await tester.tap(find.descendant(of: sheet, matching: find.text('分組15')));
    await tester.pumpAndSettle();

    expect(find.text('選擇分組'), findsNothing);
    expect(changes, ['分組15']);
  });

  testWidgets('choosing 全部 in the sheet reports the null value', (
    tester,
  ) async {
    final changes = await pumpBar(tester, selected: '精品');

    await tester.tap(find.bySemanticsLabel('全部分組'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('全部')),
    );
    await tester.pumpAndSettle();

    expect(changes, [null]);
  });

  testWidgets('closing the sheet changes nothing', (tester) async {
    final changes = await pumpBar(tester, selected: '精品');

    await tester.tap(find.bySemanticsLabel('全部分組'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('關閉'));
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
  });

  Future<void> pumpControlledBar(
    WidgetTester tester, {
    String? selected,
    int count = 20,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: _ControlledBar(selected: selected, count: count),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectSelectedChipVisible(WidgetTester tester, String label) {
    final capsule = find.ancestor(
      of: find.text(label),
      matching: find.byType(GlassCapsule),
    );
    expect(capsule, findsOneWidget);
    expect(tester.widget<GlassCapsule>(capsule).selected, isTrue);

    final viewport = tester.getRect(
      find.descendant(
        of: find.byWidgetPredicate((widget) => widget is GroupFilterBar),
        matching: find.byType(Scrollable),
      ),
    );
    final chip = tester.getRect(capsule);
    expect(chip.left, greaterThanOrEqualTo(viewport.left - 0.5));
    expect(chip.right, lessThanOrEqualTo(viewport.right + 0.5));
  }

  testWidgets('reveals the selected group when it starts out of view', (
    tester,
  ) async {
    await pumpControlledBar(tester, selected: '分組19');

    expectSelectedChipVisible(tester, '分組19');
  });

  testWidgets('reveals a group picked far away in the sheet', (tester) async {
    await pumpControlledBar(tester, selected: '分組0');
    expectSelectedChipVisible(tester, '分組0');

    await tester.tap(find.bySemanticsLabel('全部分組'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('分組19'),
      ),
    );
    await tester.pumpAndSettle();

    expectSelectedChipVisible(tester, '分組19');
  });
}

class _ControlledBar extends StatefulWidget {
  const _ControlledBar({required this.selected, required this.count});

  final String? selected;
  final int count;

  @override
  State<_ControlledBar> createState() => _ControlledBarState();
}

class _ControlledBarState extends State<_ControlledBar> {
  late String? _selected = widget.selected;

  @override
  Widget build(BuildContext context) {
    return GroupFilterBar<String?>(
      all: const GroupFilterOption<String?>(null, '全部', count: 20),
      groups: [
        for (var i = 0; i < widget.count; i++)
          GroupFilterOption<String?>('分組$i', '分組$i', count: i + 1),
      ],
      selected: _selected,
      onChanged: (value) => setState(() => _selected = value),
    );
  }
}

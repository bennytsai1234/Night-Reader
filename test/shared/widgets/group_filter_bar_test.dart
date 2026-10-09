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
}

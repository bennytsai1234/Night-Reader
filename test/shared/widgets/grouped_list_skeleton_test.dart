// 分組清單的進場骨架（ADR 0029）：換成內容時記下畫面上的樣子，下次照著畫，
// 也存進偏好設定，重開 App 照樣用。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 每次都建新的列：版面紀錄只認結構，不認元件本身。
List<Widget> _sections() => [
  GroupedSection(
    header: '一般',
    children: [
      GroupedRow(title: '第一列', value: '值', onTap: () {}),
      GroupedSwitchRow(title: '開關', value: true, onChanged: (_) {}),
    ],
  ),
  GroupedSection(
    header: '其他',
    footer: '附註',
    children: [GroupedRow(title: '帶副標', subtitle: '副標文字', onTap: () {})],
  ),
];

class _Page extends StatelessWidget {
  const _Page();

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: GroupedListView(children: _sections()));
}

Future<void> _pumpHost(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 852) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(AppStyle.paper, Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => const _Page())),
              child: const Text('開啟'),
            ),
          ),
        ),
      ),
    ),
  );
}

String _keyFor(WidgetTester tester) => GroupedListLayouts.keyOf(
  _sections(),
  tester.view.physicalSize.width / tester.view.devicePixelRatio,
  TextScaler.noScaling,
);

void main() {
  testWidgets('換成內容後記下卡片與每一行字的位置', (tester) async {
    await _pumpHost(tester);
    await tester.tap(find.text('開啟'));
    await tester.pump();
    // 推入的第一格頁面還在 offstage 排位置。
    expect(find.byType(SkeletonShapes, skipOffstage: false), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonShapes), findsNothing);

    final shapes = GroupedListLayouts.of(_keyFor(tester));
    expect(shapes, isNotNull);
    final first = shapes!.first!;
    final slot = tester.getTopLeft(
      find.ancestor(of: find.text('一般'), matching: find.byType(GroupedSection)),
    );
    // 卡片從第一列的上緣到最後一列的下緣。
    final firstRow = tester.getRect(
      find.ancestor(of: find.text('第一列'), matching: find.byType(GroupedRow)),
    );
    final lastRow = tester.getRect(find.byType(GroupedSwitchRow));
    expect(first.card, isNotNull);
    expect(first.card!.top + slot.dy, moreOrLessEquals(firstRow.top));
    expect(first.card!.bottom + slot.dy, moreOrLessEquals(lastRow.bottom));
    expect(first.rowHeights, [firstRow.height, lastRow.height]);
    // 每一行字一條，和字一樣寬、對著字的中線。
    final title = tester.getRect(find.text('第一列'));
    expect(
      first.marks.any(
        (mark) =>
            (mark.rect.left + slot.dx - title.left).abs() < 0.5 &&
            (mark.rect.center.dy + slot.dy - title.center.dy).abs() < 0.5 &&
            (mark.rect.width - title.width).abs() < 0.5,
      ),
      isTrue,
    );
    // 開關整塊畫。
    final track = tester.getRect(find.byType(GroupedSwitch));
    expect(
      first.marks.any(
        (mark) =>
            (mark.rect.shift(slot).center - track.center).distance < 0.5 &&
            (mark.rect.width - track.width).abs() < 0.5,
      ),
      isTrue,
    );
  });

  test('版面紀錄存進偏好設定，重新載入後一樣', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    GroupedListLayouts.load(prefs);
    const shape = GroupedItemShape(
      120.5,
      card: Rect.fromLTRB(16, 30, 377, 120.5),
      rowHeights: [44, 46.5],
      marks: [
        SkeletonShape(
          Rect.fromLTRB(32, 10, 60, 23),
          radius: BorderRadius.all(Radius.circular(3)),
        ),
      ],
    );
    GroupedListLayouts.remember('頁面', [shape, null]);
    await pumpEventQueue();

    final restored = GroupedItemShape.fromJson(shape.toJson())!;
    expect(restored.height, shape.height);
    expect(restored.card, shape.card);
    expect(restored.rowHeights, shape.rowHeights);
    expect(restored.marks.single.rect, shape.marks.single.rect);
    expect(restored.marks.single.radius, shape.marks.single.radius);

    // 另一次啟動：只有偏好設定裡的資料。
    SharedPreferences.setMockInitialValues({
      for (final key in prefs.getKeys()) key: prefs.get(key)!,
    });
    GroupedListLayouts.load(await SharedPreferences.getInstance());
    final loaded = GroupedListLayouts.of('頁面')!;
    expect(loaded.length, 2);
    expect(loaded.first!.card, shape.card);
    expect(loaded.last, isNull);
  });
}

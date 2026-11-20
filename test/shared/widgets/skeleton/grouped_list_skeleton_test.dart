// 分組清單的進場骨架（ADR 0029）：每一項照元件本身算，第一次進一頁、換了
// 字級，骨架就和換上的內容一樣。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/lists/number_stepper_row.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton.dart';

import '../../../support/skeleton_match.dart';

/// 各種一般的列：列首圖示、數值、箭頭、副標、開關、勾選、步進、自由
/// 內容、卡片第一列的粗字資料、說明列與說明文件的段落標題。
List<Widget> _sections() => [
  GroupedSection(
    header: '一般',
    children: [
      GroupedRow(
        leading: const GroupedIconTile(Icons.tune_rounded),
        title: '第一列',
        value: '目前的值',
        onTap: () {},
      ),
      GroupedSwitchRow(title: '開關', value: true, onChanged: (_) {}),
      GroupedCheckRow(title: '勾選', selected: true, onTap: () {}),
      GroupedCheckRow(title: '沒勾選', selected: false, onTap: () {}),
    ],
  ),
  // 卡片第一列的粗字資料（更新紀錄的版本號與發布日期）。
  GroupedSection(
    children: [
      GroupedRow(title: 'v1.0.0（目前版本）', heading: true, value: '2026-10-23'),
      GroupedRow(title: '內容'),
      const GroupedHelpRow(
        title: '說明回答的問題',
        sections: [
          (heading: null, items: ['一列一件事']),
        ],
      ),
    ],
  ),
  GroupedSection(
    children: [
      GroupedRow(title: '帶副標的列，標題長一點看會不會換行', subtitle: '副標文字', onTap: () {}),
      GroupedContent(
        child: NumberStepperRow(
          label: '字號',
          value: 18,
          min: 12,
          max: 40,
          step: 1,
          onChanged: (_) {},
        ),
      ),
      const GroupedContent(child: Text('卡片裡的一段自由內容，長到要換行才放得下的那種說明文字。')),
    ],
  ),
];

Future<void> _push(
  WidgetTester tester,
  Widget Function() page, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(393, 852) * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(AppStyle.paper, Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => page())),
              child: const Text('開啟'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('開啟'));
  await tester.pump();
}

/// 換頁播完時畫的骨架，和換上內容後量到的每一塊比。
Future<List<String>> _mismatches(WidgetTester tester) async {
  final list = find.byType(GroupedListView);
  final route = ModalRoute.of(
    tester.element(find.byType(GroupedListView, skipOffstage: false)),
  )!;
  while (!route.animation!.isCompleted) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  final skeleton = skeletonLayoutOf(
    tester,
    find.descendant(of: list, matching: find.byType(SkeletonShapes)),
  );
  expect(skeleton.marks, isNotEmpty);
  await tester.pumpAndSettle();
  expect(find.byType(SkeletonShapes), findsNothing);
  return skeletonMismatches(
    skeleton,
    contentLayoutOf(tester, list),
    visible: tester.getRect(list),
  );
}

void main() {
  for (final scale in [1.0, 1.6]) {
    testWidgets('第一次進去的骨架就和換上的內容一樣（字級 $scale 倍）', (tester) async {
      await _push(
        tester,
        () => Scaffold(body: GroupedListView(children: _sections())),
        textScale: scale,
      );
      // 推入的第一格頁面還在 offstage 排位置。
      expect(find.byType(SkeletonShapes, skipOffstage: false), findsOneWidget);
      expect(await _mismatches(tester), isEmpty);
    });
  }

  testWidgets('上百列的組不等畫面外的列，換頁播完不久就換成內容', (tester) async {
    await _push(
      tester,
      () => Scaffold(
        body: GroupedListView(
          children: [
            GroupedSection(
              header: '規則',
              children: [
                for (var i = 0; i < 200; i++)
                  GroupedRow(title: '規則 $i', onTap: () {}),
              ],
            ),
          ],
        ),
      ),
    );
    final route = ModalRoute.of(
      tester.element(find.byType(GroupedListView, skipOffstage: false)),
    )!;
    while (!route.animation!.isCompleted) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 第一個畫面約 17 列：一格一列加上換場，遠少於兩百格。
    var frames = 0;
    while (find.byType(SkeletonShapes).evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(++frames, lessThan(90), reason: '骨架等畫面外的列');
    }
    expect(find.text('規則 0'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('資料還沒到時保留骨架，到齊後照新增列的真實形狀揭開', (tester) async {
    final ready = ValueNotifier<bool>(false);
    addTearDown(ready.dispose);
    await _push(
      tester,
      () => ValueListenableBuilder<bool>(
        valueListenable: ready,
        builder: (context, loaded, _) => Scaffold(
          body: GroupedListView(
            ready: loaded,
            children: [
              GroupedSection(
                header: '資料',
                children: [
                  const GroupedRow(title: '第一列'),
                  if (loaded)
                    const GroupedRow(
                      title: '載入後才知道的第二列',
                      value: '已完成',
                      showChevron: false,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final list = find.byType(GroupedListView, skipOffstage: false);
    final route = ModalRoute.of(tester.element(list))!;
    while (!route.animation!.isCompleted) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 換頁已播完，但資料還沒回來，不能先把一列的骨架換成內容。
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SkeletonShapes), findsOneWidget);
    expect(find.text('第一列'), findsNothing);

    ready.value = true;
    await tester.pump();
    final skeleton = skeletonLayoutOf(
      tester,
      find.descendant(of: list, matching: find.byType(SkeletonShapes)),
    );
    await tester.pumpAndSettle();
    expect(find.text('載入後才知道的第二列'), findsOneWidget);
    expect(
      skeletonMismatches(
        skeleton,
        contentLayoutOf(tester, list),
        visible: tester.getRect(list),
      ),
      isEmpty,
    );
  });

  testWidgets('算不出骨架的元件會被抓出來', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(
              () => GroupedItemShape.of(
                const Placeholder(),
                context: context,
                width: 393,
              ),
              throwsAssertionError,
            );
            return const SizedBox();
          },
        ),
      ),
    );
  });
}

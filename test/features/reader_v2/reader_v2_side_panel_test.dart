import 'dart:io' show sleep;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_side_panel.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 閱讀器左側的面板：一直掛著、先建好再滑，其他照系統抽屜。
void main() {
  late ReaderV2SidePanelController panel;
  late int panelBuilds;
  late int bodyTaps;
  late List<bool> openChanges;
  late int closes;

  setUp(() {
    panelBuilds = 0;
    bodyTaps = 0;
    openChanges = [];
    closes = 0;
  });

  Future<StateSetter> pumpPanel(
    WidgetTester tester, {
    ValueNotifier<Brightness>? brightness,
  }) async {
    panel = ReaderV2SidePanelController();
    addTearDown(panel.dispose);
    late StateSetter rebuildPage;
    var pageBuilds = 0;
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: brightness ?? ValueNotifier(Brightness.light),
        builder: (context, value, _) => MaterialApp(
          theme: ThemeData(brightness: value),
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuildPage = setState;
              pageBuilds++;
              return ReaderV2SidePanel(
                controller: panel,
                onOpenChanged: openChanges.add,
                onClosed: () => closes++,
                // 每次閱讀頁重建都給一個新的面板元件。
                panel: _CountingPanel(
                  label: '第 $pageBuilds 次',
                  onBuild: () => panelBuilds++,
                ),
                child: GestureDetector(
                  onTap: () => bodyTaps++,
                  child: const ColoredBox(
                    color: Colors.white,
                    child: SizedBox.expand(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    return rebuildPage;
  }

  double panelLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byType(Drawer)).dx;

  // 準備面板的那一幀實際花多久不一定（測試環境常超過 16ms），超過就再停
  // 0.1 秒才滑；pumpAndSettle 不等這段計時器，先推進過去。
  Future<void> openPanel(WidgetTester tester) async {
    panel.open();
    await tester.pump();
    await tester.pump(AppMotion.stillGap);
    await tester.pumpAndSettle();
  }

  testWidgets('the panel is built on first open and kept afterwards; closed, '
      'it is off screen and page rebuilds do not reach it', (tester) async {
    final rebuildPage = await pumpPanel(tester);
    expect(panelBuilds, 0);
    expect(find.byType(Drawer, skipOffstage: false), findsNothing);

    await openPanel(tester);
    expect(panelLeft(tester), 0);
    expect(panelBuilds, 1);
    expect(openChanges, [true]);

    panel.close();
    await tester.pumpAndSettle();
    expect(openChanges, [true, false]);
    expect(closes, 1);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byType(Drawer, skipOffstage: false), findsOneWidget);

    // 收著時閱讀頁重建：面板不跟著重建。
    rebuildPage(() {});
    await tester.pump();
    rebuildPage(() {});
    await tester.pump();
    expect(panelBuilds, 1);

    // 打開時換上最新的面板元件，只重建一次。
    panel.open();
    await tester.pump();
    expect(panelBuilds, 2);
    expect(find.text('第 3 次'), findsOneWidget);
    await tester.pump(AppMotion.stillGap);
    await tester.pumpAndSettle();
    expect(panelLeft(tester), 0);
  });

  testWidgets('the frame that prepares the panel keeps it off screen; it '
      'slides out afterwards', (tester) async {
    await pumpPanel(tester);
    panel.open();
    await tester.pump();
    // 這一幀把面板建好、放在畫面左邊外面。
    expect(find.byType(Drawer), findsOneWidget);
    expect(tester.getTopRight(find.byType(Drawer)).dx, 0);
    await tester.pump(AppMotion.stillGap);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getTopRight(find.byType(Drawer)).dx, greaterThan(0));
  });

  testWidgets('a theme change while closed shows on the next open', (
    tester,
  ) async {
    final brightness = ValueNotifier(Brightness.light);
    addTearDown(brightness.dispose);
    await pumpPanel(tester, brightness: brightness);
    await openPanel(tester);
    final light = tester.widget<ColoredBox>(
      find.byKey(_CountingPanel.surfaceKey),
    );
    panel.close();
    await tester.pumpAndSettle();

    brightness.value = Brightness.dark;
    await tester.pumpAndSettle();
    await openPanel(tester);
    final dark = tester.widget<ColoredBox>(
      find.byKey(_CountingPanel.surfaceKey),
    );
    expect(dark.color, isNot(light.color));
    expect(
      dark.color,
      ThemeData(brightness: Brightness.dark).colorScheme.surface,
    );
  });

  testWidgets('dragging right from the left edge pulls the panel out with '
      'the finger; letting go past half opens it', (tester) async {
    await pumpPanel(tester);
    final gesture = await tester.startGesture(const Offset(5, 300));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final width = tester.getSize(find.byType(Drawer)).width;
    // 跟著手指：拖了 240，扣掉觸控門檻（18）那一段。
    expect(tester.getTopRight(find.byType(Drawer)).dx, closeTo(222, 3));
    expect(width, greaterThan(240 / 2));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(panelLeft(tester), 0);
    expect(panel.isOpen, isTrue);
    expect(openChanges, [true]);
  });

  testWidgets('a short drag from the edge springs back and counts as closed', (
    tester,
  ) async {
    await pumpPanel(tester);
    final gesture = await tester.startGesture(const Offset(5, 300));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(panel.isOpen, isFalse);
    expect(find.byType(Drawer), findsNothing);
    expect(openChanges, isEmpty);
    expect(closes, 0);
  });

  testWidgets('taps on the page pass through while closed, also at the edge', (
    tester,
  ) async {
    await pumpPanel(tester);
    await tester.tapAt(const Offset(200, 300));
    await tester.tapAt(const Offset(5, 300));
    await tester.pumpAndSettle();
    expect(bodyTaps, 2);
    expect(panel.isOpen, isFalse);
    expect(closes, 0);
  });

  testWidgets('a tap beside the open panel closes it and does not reach the '
      'page', (tester) async {
    await pumpPanel(tester);
    await openPanel(tester);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width - 10, 300));
    await tester.pumpAndSettle();
    expect(panel.isOpen, isFalse);
    expect(closes, 1);
    expect(bodyTaps, 0);
  });

  testWidgets('dragging the open panel left closes it', (tester) async {
    await pumpPanel(tester);
    await openPanel(tester);
    await tester.fling(find.byType(Drawer), const Offset(-200, 0), 1000);
    await tester.pumpAndSettle();
    expect(panel.isOpen, isFalse);
    expect(closes, 1);
  });

  testWidgets('scrolling up and down in the open panel leaves the panel in '
      'place: no slide runs', (tester) async {
    panel = ReaderV2SidePanelController();
    addTearDown(panel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderV2SidePanel(
          controller: panel,
          panel: Drawer(
            child: ListView(
              children: [
                for (var i = 0; i < 60; i++)
                  SizedBox(height: 56, child: Text('第$i章')),
              ],
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    await openPanel(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Drawer)),
    );
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 手指還按著、清單跟著捲：除了捲動本身，沒有動畫在跑。
    final list = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(list.position.pixels, greaterThan(100));
    expect(tester.binding.transientCallbackCount, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(panelLeft(tester), 0);
    expect(panel.isOpen, isTrue);
  });

  testWidgets('dragging the open panel all the way to the edge counts as '
      'closed: notices go out once and the page takes taps again', (
    tester,
  ) async {
    await pumpPanel(tester);
    await openPanel(tester);
    final drag = await tester.startGesture(const Offset(280, 300));
    await tester.pump(const Duration(milliseconds: 60));
    for (var i = 0; i < 8; i++) {
      await drag.moveBy(const Offset(-50, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(panel.isOpen, isFalse);
    expect(panel.shown.value, isFalse);
    expect(openChanges, [true, false]);
    expect(closes, 1);
    await tester.tapAt(const Offset(200, 300));
    expect(bodyTaps, 1);
  });

  testWidgets('a screen reader skips the covered page whenever the panel is '
      'on screen, also while the finger pulls it out', (tester) async {
    final semantics = tester.ensureSemantics();
    panel = ReaderV2SidePanelController();
    addTearDown(panel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderV2SidePanel(
          controller: panel,
          panel: const Drawer(child: Text('章節')),
          child: Center(
            child: TextButton(onPressed: () {}, child: const Text('閱讀正文')),
          ),
        ),
      ),
    );
    expect(_semanticsLabels(tester), contains('閱讀正文'));

    final drag = await tester.startGesture(const Offset(5, 300));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await drag.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(panel.isOpen, isFalse, reason: '手指還拉著');
    expect(_semanticsLabels(tester), isNot(contains('閱讀正文')));
    await drag.up();
    await tester.pumpAndSettle();
    expect(panel.isOpen, isTrue);
    expect(_semanticsLabels(tester), isNot(contains('閱讀正文')));

    panel.close();
    await tester.pumpAndSettle();
    expect(_semanticsLabels(tester), contains('閱讀正文'));
    expect(_semanticsLabels(tester), isNot(contains('章節')));
    semantics.dispose();
  });

  testWidgets('a drag that starts while the slide is held hands the panel '
      'to the finger: the held slide never runs', (tester) async {
    panel = ReaderV2SidePanelController();
    addTearDown(panel.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderV2SidePanel(
          controller: panel,
          // 準備那一幀很重：滑出要停 AppMotion.stillGap。
          panel: Builder(
            builder: (_) {
              sleep(const Duration(milliseconds: 25));
              return const Drawer(child: SizedBox.expand());
            },
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    panel.open();
    await tester.pump();
    final drag = await tester.startGesture(const Offset(5, 300));
    await drag.moveBy(const Offset(50, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await drag.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    final held = tester.getTopRight(find.byType(Drawer)).dx;
    await tester.pump(AppMotion.stillGap);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getTopRight(find.byType(Drawer)).dx, closeTo(held, 0.01));
    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('focus moves into the open panel, also one pulled out from the '
      'edge, and leaves the page underneath', (tester) async {
    panel = ReaderV2SidePanelController();
    addTearDown(panel.dispose);
    final bodyFocus = FocusNode();
    final panelFocus = FocusNode();
    addTearDown(bodyFocus.dispose);
    addTearDown(panelFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderV2SidePanel(
          controller: panel,
          panel: Drawer(
            child: Center(
              child: TextButton(
                focusNode: panelFocus,
                onPressed: () {},
                child: const Text('章節'),
              ),
            ),
          ),
          child: Center(
            child: TextButton(
              focusNode: bodyFocus,
              onPressed: () {},
              child: const Text('閱讀正文'),
            ),
          ),
        ),
      ),
    );
    bodyFocus.requestFocus();
    await tester.pump();
    await openPanel(tester);
    expect(bodyFocus.hasFocus, isFalse);

    panel.close();
    await tester.pumpAndSettle();
    expect(panelFocus.canRequestFocus, isFalse, reason: '收著時不能取得焦點');

    final drag = await tester.startGesture(const Offset(5, 300));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await drag.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(panel.isOpen, isTrue);
    panelFocus.requestFocus();
    await tester.pump();
    expect(panelFocus.hasFocus, isTrue);
  });

  testWidgets('closing before the slide starts never shows the panel', (
    tester,
  ) async {
    await pumpPanel(tester);
    panel.open();
    panel.close();
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(openChanges, [true, false]);
    expect(closes, 1);
  });
}

/// 讀屏實際拿到的每一段標籤（走一遍送出去的無障礙內容；`find.bySemanticsLabel`
/// 會找到被排除的元件身上留著的舊資料）。
List<String> _semanticsLabels(WidgetTester tester) {
  final labels = <String>[];
  bool visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren(visit);
    return true;
  }

  visit(
    tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return labels;
}

class _CountingPanel extends StatelessWidget {
  const _CountingPanel({required this.label, required this.onBuild});

  static const surfaceKey = Key('surface');

  final String label;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild();
    return Drawer(
      child: ColoredBox(
        key: surfaceKey,
        color: Theme.of(context).colorScheme.surface,
        child: Center(child: Text(label)),
      ),
    );
  }
}

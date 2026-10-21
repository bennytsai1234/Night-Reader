import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/widgets/swipe_actions.dart';

void main() {
  late List<String> log;

  setUp(() => log = []);

  Widget row(String id, {bool enabled = true}) => SwipeActions(
    key: ValueKey(id),
    enabled: enabled,
    trailing: [
      SwipeAction(
        label: '置頂',
        icon: Icons.push_pin_outlined,
        color: Colors.blue,
        onPressed: () => log.add('$id:pin'),
      ),
      SwipeAction(
        label: '刪除',
        icon: Icons.delete_outline,
        color: Colors.red,
        destructive: true,
        onPressed: () => log.add('$id:delete'),
      ),
    ],
    child: ListTile(title: Text(id), onTap: () => log.add('$id:tap')),
  );

  // 測試視窗寬 800：兩個動作露出 148，完整滑動門檻 480。
  Future<void> pumpList(WidgetTester tester, {int count = 2}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeActionsGroup(
            child: ListView(
              children: [for (var i = 0; i < count; i++) row('row$i')],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> swipe(WidgetTester tester, String id, double dx) async {
    await tester.drag(find.text(id), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('拖動不到一半露出寬度時放開收回', (tester) async {
    await pumpList(tester);
    await swipe(tester, 'row0', -50);
    expect(find.text('刪除'), findsNothing);
    expect(log, isEmpty);
  });

  testWidgets('拖過一半露出寬度停在展開，點動作執行並收合', (tester) async {
    await pumpList(tester);
    await swipe(tester, 'row0', -120);
    expect(find.text('置頂'), findsOneWidget);
    expect(find.text('刪除'), findsOneWidget);

    await tester.tap(find.text('置頂'));
    await tester.pumpAndSettle();
    expect(log, ['row0:pin']);
    expect(find.text('置頂'), findsNothing);
  });

  testWidgets('展開時點列本身只收合，不觸發列的點擊', (tester) async {
    await pumpList(tester);
    await swipe(tester, 'row0', -120);
    // 展開時列上蓋著收合用的點擊層，點擊不會落到列本身。
    await tester.tap(find.text('row0'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(log, isEmpty);
    expect(find.text('刪除'), findsNothing);

    await tester.tap(find.text('row0'));
    await tester.pumpAndSettle();
    expect(log, ['row0:tap']);
  });

  testWidgets('完整滑動觸發最外側動作', (tester) async {
    await pumpList(tester);
    await swipe(tester, 'row0', -600);
    expect(log, ['row0:delete']);
    // 列仍存在時彈回原位。
    expect(find.text('刪除'), findsNothing);
    expect(tester.getTopLeft(find.text('row0')).dx, lessThan(100));
  });

  testWidgets('同一組只會有一列展開', (tester) async {
    await pumpList(tester);
    await swipe(tester, 'row0', -120);
    await swipe(tester, 'row1', -120);
    expect(find.text('刪除'), findsOneWidget);
    final row1 = tester.getRect(find.byKey(const ValueKey('row1')));
    expect(row1.contains(tester.getCenter(find.text('刪除'))), isTrue);
  });

  testWidgets('不影響清單的垂直捲動，捲動時收合', (tester) async {
    await pumpList(tester, count: 40);
    await swipe(tester, 'row0', -120);
    expect(find.text('刪除'), findsOneWidget);

    final before = tester.getTopLeft(find.text('row3')).dy;
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('row3')).dy, lessThan(before));
    expect(find.text('刪除'), findsNothing);
  });

  testWidgets('停用時無法滑出動作', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: row('row0', enabled: false))),
    );
    await swipe(tester, 'row0', -300);
    expect(find.text('刪除'), findsNothing);
  });

  testWidgets('收合動畫期間再點一次不會重複執行動作', (tester) async {
    await pumpList(tester);
    await swipe(tester, 'row0', -120);

    await tester.tap(find.text('置頂'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('置頂'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(log, ['row0:pin']);
    // 第二次點擊沒有變成拖動，不會把收合中的列彈回展開。
    expect(find.text('置頂'), findsNothing);

    // 下一次滑開後照常可以再執行。
    await swipe(tester, 'row0', -120);
    await tester.tap(find.text('置頂'));
    await tester.pumpAndSettle();
    expect(log, ['row0:pin', 'row0:pin']);
  });

  // 測試環境的觸控門檻預設和 Flutter 的 kTouchSlop 一樣是 18；手機上清單捲動
  // 與 PageView 用的是裝置的（Android 約 8）。列的滑動要用同一個門檻，斜著拖
  // 時才由先越過門檻的方向勝出。
  group('照裝置的觸控門檻', () {
    void useDeviceTouchSlop(WidgetTester tester) {
      tester.view.gestureSettings = ui.GestureSettings(
        physicalTouchSlop: 8 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.reset);
    }

    /// 從 [start] 以每格 [step] 慢慢拖 [steps] 格（每格一個移動事件）。
    Future<void> slowDrag(
      WidgetTester tester,
      Offset start,
      Offset step,
      int steps,
    ) async {
      final gesture = await tester.startGesture(start);
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(step);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    // 快快拖時第一個移動事件就兩軸都越過門檻（橫 12、直 18），同時越過時列
    // 先處理；偏直向的拖動仍要交給清單。
    for (final (name, step, steps) in [
      ('慢慢拖', const Offset(-1, -2), 50),
      ('快快拖', const Offset(-12, -18), 6),
    ]) {
      testWidgets('$name：偏垂直的拖動捲動清單，不滑出動作', (tester) async {
        useDeviceTouchSlop(tester);
        await pumpList(tester, count: 40);
        final before = tester.getTopLeft(find.text('row3')).dy;
        await slowDrag(
          tester,
          tester.getCenter(find.text('row1')),
          step,
          steps,
        );
        expect(tester.getTopLeft(find.text('row3')).dy, lessThan(before - 50));
        expect(find.text('刪除'), findsNothing);
      });
    }

    testWidgets('偏水平的拖動滑出動作，清單不捲動', (tester) async {
      useDeviceTouchSlop(tester);
      await pumpList(tester, count: 40);
      final before = tester.getTopLeft(find.text('row3')).dy;
      // 每格橫 2、直 1.2：橫向先越過 8，直向這時才 6。
      await slowDrag(
        tester,
        tester.getCenter(find.text('row1')),
        const Offset(-2, -1.2),
        60,
      );
      expect(find.text('刪除'), findsOneWidget);
      expect(tester.getTopLeft(find.text('row3')).dy, before);
    });

    group('放在左右滑動的 PageView 裡', () {
      late PageController pages;

      Future<void> pumpPages(WidgetTester tester) async {
        pages = PageController();
        addTearDown(pages.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PageView(
                controller: pages,
                children: [
                  SwipeActionsGroup(
                    child: ListView(
                      children: [for (var i = 0; i < 3; i++) row('row$i')],
                    ),
                  ),
                  const Center(child: Text('第二頁')),
                ],
              ),
            ),
          ),
        );
      }

      // 原本列用 18、PageView 用 8：慢慢拖時 PageView 先越過門檻換頁，拖得快時
      // 第一個移動事件同時越過兩者、由列接走，結果看手速。
      for (final (name, step, steps) in [
        ('慢慢拖', const Offset(-3, 0), 40),
        ('快快拖', const Offset(-40, 0), 3),
      ]) {
        testWidgets('$name：在列上橫拖一律滑出動作，不換頁', (tester) async {
          useDeviceTouchSlop(tester);
          await pumpPages(tester);
          await slowDrag(
            tester,
            tester.getCenter(find.text('row0')),
            step,
            steps,
          );
          expect(find.text('刪除'), findsOneWidget);
          expect(pages.page, 0);
        });
      }

      testWidgets('在列以外的地方橫拖照常換頁', (tester) async {
        useDeviceTouchSlop(tester);
        await pumpPages(tester);
        await slowDrag(
          tester,
          const Offset(400, 500),
          const Offset(-20, 0),
          30,
        );
        expect(pages.page, 1);
        expect(find.text('第二頁'), findsOneWidget);
      });
    });
  });
}

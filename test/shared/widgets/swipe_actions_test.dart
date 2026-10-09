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

    // 下一次滑開後照常可以再執行。
    await swipe(tester, 'row0', -120);
    await tester.tap(find.text('置頂'));
    await tester.pumpAndSettle();
    expect(log, ['row0:pin', 'row0:pin']);
  });
}

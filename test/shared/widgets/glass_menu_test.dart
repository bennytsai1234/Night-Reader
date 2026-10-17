import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';

void main() {
  testWidgets('a tall preview in landscape leaves every menu item reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? picked;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showContextPreviewMenu<String>(
                  context: context,
                  sourceRect: const Rect.fromLTWH(40, 40, 100, 140),
                  preview: const ColoredBox(color: Colors.brown),
                  entries: [
                    for (var i = 0; i < 6; i++)
                      GlassMenuItem(value: '項目$i', label: '項目$i'),
                    const GlassMenuDivider(),
                    const GlassMenuItem(value: '移出書架', label: '移出書架'),
                  ],
                );
              },
              child: const Text('長按'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('長按'));
    await tester.pumpAndSettle();

    // 最後一項原本畫在螢幕外；現在選單可捲動，捲到後點得到。
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('移出書架')).bottom, lessThanOrEqualTo(360));
    await tester.tap(find.text('移出書架'));
    await tester.pumpAndSettle();
    expect(picked, '移出書架');
  });

  testWidgets('the lifted preview shadow grows and shrinks with the lift', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showContextPreviewMenu<String>(
                context: context,
                sourceRect: const Rect.fromLTWH(40, 200, 100, 140),
                preview: const ColoredBox(color: Colors.brown),
                entries: const [GlassMenuItem(value: '刪除', label: '刪除')],
              ),
              child: const Text('長按'),
            ),
          ),
        ),
      ),
    );
    BoxShadow shadow() {
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.byWidgetPredicate(
                (w) => w is ColoredBox && w.color == Colors.brown,
              ),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).boxShadow!.single;
    }

    await tester.tap(find.text('長按'));
    await tester.pump();
    // 第一幀還沒浮起：沒有陰影。
    expect(shadow().color.a, 0);
    expect(shadow().blurRadius, 0);

    await tester.pump(const Duration(milliseconds: 60));
    final mid = shadow();
    expect(mid.blurRadius, inExclusiveRange(0, 30));
    expect(mid.offset.dy, inExclusiveRange(0, 10));

    await tester.pumpAndSettle();
    final rest = shadow();
    expect(rest.blurRadius, 30);
    expect(rest.offset, const Offset(0, 10));
    final full = rest.color.a;
    expect(full, greaterThan(0));

    // 收起時陰影跟著退，最後一幀之前已經很淡，不會在結束那一刻才消失。
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(shadow().color.a, inExclusiveRange(0, full));
    await tester.pump(const Duration(milliseconds: 75));
    expect(shadow().color.a, lessThan(full * 0.1));
    await tester.pumpAndSettle();
    expect(find.text('刪除'), findsNothing);
  });
}

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
}

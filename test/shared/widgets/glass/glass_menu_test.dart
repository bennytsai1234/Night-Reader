import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass/glass_menu.dart';

void main() {
  testWidgets('labels stay put whether a toggle item is on or off', (
    tester,
  ) async {
    Future<double> labelLeft({required bool on}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showGlassMenu<String>(
                  context: context,
                  anchor: const Rect.fromLTWH(20, 20, 40, 40),
                  entries: [
                    const GlassMenuItem(value: '檢查更新', label: '檢查更新'),
                    GlassMenuItem(value: '自動', label: '自動檢查更新', checked: on),
                  ],
                ),
                child: const Text('開'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開'));
      await tester.pumpAndSettle();
      final left = tester.getTopLeft(find.text('檢查更新')).dx;
      await tester.tapAt(const Offset(5, 590));
      await tester.pumpAndSettle();
      return left;
    }

    expect(await labelLeft(on: false), await labelLeft(on: true));
  });

  testWidgets('a toggle reads as a checkbox and a plain action as a button', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showGlassMenu<String>(
                context: context,
                anchor: const Rect.fromLTWH(20, 20, 40, 40),
                entries: const [
                  GlassMenuItem(value: '網格', label: '網格', checked: true),
                  GlassMenuItem(value: '列表', label: '列表', checked: false),
                  GlassMenuItem(
                    value: '統一封面',
                    label: '統一封面',
                    checked: true,
                    toggle: true,
                  ),
                  GlassMenuItem(value: '選取', label: '選取'),
                ],
              ),
              child: const Text('開'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開'));
    await tester.pumpAndSettle();

    bool exclusive(String label) => tester
        .getSemantics(find.bySemanticsLabel(label))
        .flagsCollection
        .isInMutuallyExclusiveGroup;
    expect(exclusive('網格'), isTrue);
    expect(exclusive('列表'), isTrue);
    expect(exclusive('統一封面'), isFalse, reason: '可以和別項同時勾');
    final action = tester
        .getSemantics(find.bySemanticsLabel('選取'))
        .flagsCollection;
    expect(action.isInMutuallyExclusiveGroup, isFalse, reason: '一般動作照按鈕念');
    expect(action.isChecked, CheckedState.none);
    semantics.dispose();
  });

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

  testWidgets('字放大後選單比估的高：選單不超出畫面，最後一項捲得到', (tester) async {
    tester.view.physicalSize = const Size(900, 430);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? picked;
    var anchor = const Rect.fromLTWH(840, 31, 44, 44);
    const labels = [
      '檢查更新',
      '自動檢查更新',
      '預下載章節',
      '換封面',
      '匯出全書',
      '編輯資訊',
      '清除已下載的正文',
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            padding: const EdgeInsets.only(top: 24),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showGlassMenu<String>(
                  context: context,
                  anchor: anchor,
                  entries: [
                    for (final label in labels)
                      GlassMenuItem(
                        value: label,
                        label: label,
                        icon: Icons.refresh_rounded,
                        checked: label == '自動檢查更新' ? true : null,
                      ),
                  ],
                );
              },
              child: const Text('開'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開'));
    await tester.pumpAndSettle();

    final list = find.byType(ListView).last;
    expect(tester.getRect(list).bottom, lessThanOrEqualTo(430));
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
    final last = find.text(labels.last).last;
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(430));
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(picked, labels.last);

    // 開在錨點上方：往上長，不壓到錨點。
    anchor = const Rect.fromLTWH(840, 370, 44, 44);
    await tester.tap(find.text('開'));
    await tester.pumpAndSettle();
    final above = tester.getRect(find.byType(ListView).last);
    expect(above.top, greaterThanOrEqualTo(24));
    expect(above.bottom, lessThanOrEqualTo(370));
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

  testWidgets('the lifted preview keeps its size on whole device pixels', (
    tester,
  ) async {
    const ratio = 2.625;
    tester.view.devicePixelRatio = ratio;
    tester.view.physicalSize = const Size(393, 852) * ratio;
    addTearDown(tester.view.reset);
    // 靠近畫面底部：預覽要往上推才放得下選單，途中位置一直在變。
    const source = Rect.fromLTWH(40.3, 700.7, 100, 140);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showContextPreviewMenu<String>(
                context: context,
                sourceRect: source,
                preview: const Text('預覽'),
                entries: const [GlassMenuItem(value: '刪除', label: '刪除')],
              ),
              child: const Text('長按'),
            ),
          ),
        ),
      ),
    );
    // 預覽不縮放（字不必每一幀重建），位置落在整數個實體像素上；
    // getRect 經過所有的變形，量到的是畫面上的大小。回傳這一幀的上緣。
    double expectOnPixels() {
      final rect = tester.getRect(find.text('預覽'));
      expect(rect.width, moreOrLessEquals(source.width));
      expect(rect.height, moreOrLessEquals(source.height));
      for (final v in [rect.left, rect.top]) {
        expect(v * ratio, moreOrLessEquals((v * ratio).roundToDouble()));
      }
      return rect.top;
    }

    await tester.tap(find.text('長按'));
    await tester.pump();
    final tops = <double>{};
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      tops.add(expectOnPixels());
    }
    expect(tops.length, greaterThan(2), reason: '途中預覽要真的在移動');
    await tester.pumpAndSettle();

    // 收起時沿原路退回，途中一樣不縮放、對齊像素。
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    final back = <double>{};
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 30));
      back.add(expectOnPixels());
    }
    expect(back.length, greaterThan(2));
    await tester.pumpAndSettle();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass.dart';

const _screen = Size(390, 800);

Future<void> _pump(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(AppStyle.kraft, Brightness.light),
      home: Scaffold(body: body),
    ),
  );
  await tester.pumpAndSettle();
}

/// 按鈕看得到的那塊玻璃。
Rect _visual(WidgetTester tester, Finder button) => tester.getRect(
  find.descendant(of: button, matching: find.byType(GlassSurface)),
);

void main() {
  testWidgets('頁面上的圓鈕與文字鈕是 44', (tester) async {
    await _pump(
      tester,
      Row(
        children: [
          GlassIconButton(icon: Icons.close_rounded, onPressed: () {}),
          GlassTextButton(label: '儲存', onPressed: () {}),
        ],
      ),
    );
    expect(
      _visual(tester, find.byType(GlassIconButton)).size,
      const Size.square(AppGlass.buttonSize),
    );
    expect(
      _visual(tester, find.byType(GlassTextButton)).height,
      AppGlass.buttonSize,
    );
  });

  testWidgets('底部面板頁首的鈕看得到 32、觸控 44，左右和卡片切齊', (tester) async {
    await _pump(
      tester,
      AppBottomSheet(
        title: '編輯規則',
        trailing: GlassTextButton(label: '儲存', onPressed: () {}),
        children: const [SizedBox(height: 40)],
      ),
    );
    final close = find.byType(GlassIconButton);
    final save = find.byType(GlassTextButton);

    expect(_visual(tester, close).size, const Size.square(PanelButtons.size));
    expect(tester.getSize(close), const Size.square(AppGlass.buttonSize));
    expect(_visual(tester, save).height, PanelButtons.size);
    expect(tester.getSize(save).height, AppGlass.buttonSize);

    expect(_visual(tester, close).left, AppGrouped.margin);
    expect(_visual(tester, save).right, _screen.width - AppGrouped.margin);
    expect(_visual(tester, close).center.dy, _visual(tester, save).center.dy);
  });

  testWidgets('系統字級放大時，面板頁首的文字鈕跟著字長高，不裁字', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
      tester,
      AppBottomSheet(
        title: '編輯規則',
        trailing: GlassTextButton(label: '儲存', onPressed: () {}),
        children: const [SizedBox(height: 40)],
      ),
    );
    final save = find.byType(GlassTextButton);
    final glass = _visual(tester, save);
    final text = tester.getRect(
      find.descendant(of: save, matching: find.text('儲存')),
    );
    expect(text.height, greaterThan(PanelButtons.size));
    expect(glass.top, lessThanOrEqualTo(text.top));
    expect(glass.bottom, greaterThanOrEqualTo(text.bottom));
  });

  testWidgets('只有關閉的面板：關閉在右邊，右緣和卡片切齊', (tester) async {
    await _pump(
      tester,
      const AppBottomSheet(title: '選擇分組', children: [SizedBox(height: 40)]),
    );
    final close = find.byType(GlassIconButton);
    expect(_visual(tester, close).size, const Size.square(PanelButtons.size));
    expect(_visual(tester, close).right, _screen.width - AppGrouped.margin);
  });

  testWidgets('SheetHeader 兩側的鈕也是 32，左右和卡片切齊', (tester) async {
    await _pump(
      tester,
      SheetHeader(
        title: '更換來源',
        leading: GlassIconButton(
          icon: Icons.filter_list_rounded,
          onPressed: () {},
        ),
        trailing: GlassIconButton(
          icon: Icons.refresh_rounded,
          onPressed: () {},
        ),
      ),
    );
    final buttons = find.byType(GlassIconButton);
    final left = _visual(tester, buttons.first);
    final right = _visual(tester, buttons.last);
    expect(left.size, const Size.square(PanelButtons.size));
    expect(right.size, const Size.square(PanelButtons.size));
    expect(left.left, AppGrouped.margin);
    expect(right.right, _screen.width - AppGrouped.margin);
    expect(
      tester.getSize(buttons.first),
      const Size.square(AppGlass.buttonSize),
    );
  });
}

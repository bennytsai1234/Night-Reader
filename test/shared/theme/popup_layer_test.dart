import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_layers.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';

/// 畫面上每一塊玻璃底色的不透明度。
List<double> _glassAlphas(WidgetTester tester) => [
  for (final element in find.byType(GlassSurface).evaluate())
    ((element.widget as GlassSurface).tint ?? AppChrome.of(element).glassTint)
        .a,
];

Future<void> _pump(
  WidgetTester tester,
  Brightness brightness,
  GlassStrength strength,
  void Function(BuildContext context) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(
        AppStyle.kraft,
        brightness,
        glassStrength: strength,
        pureBlack: true,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              TextButton(
                onPressed: () => open(context),
                child: const Text('開'),
              ),
              const GlassCapsule(label: '全部', selected: true),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('開'));
  await tester.pumpAndSettle();
}

void _openMenu(BuildContext context) => showGlassMenu<String>(
  context: context,
  anchor: const Rect.fromLTWH(20, 20, 40, 40),
  entries: const [GlassMenuItem(value: '網格', label: '網格')],
);

void _openAlert(BuildContext context) =>
    showAppConfirm(context: context, title: '按標籤刪除');

void _openActionSheet(BuildContext context) => showAppActionSheet<String>(
  context: context,
  actions: const [AppSheetAction(label: '系統字型', value: 'system')],
);

void main() {
  for (final style in AppStyle.values) {
    for (final pureBlack in [true, false]) {
      final name = '${style.label}${pureBlack ? '純黑' : ''}';

      test('彈出層：淺色和卡片同色，深色是玻璃那一階（$name）', () {
        for (final brightness in Brightness.values) {
          final theme = buildAppTheme(style, brightness, pureBlack: pureBlack);
          final palette = theme.extension<StylePalette>()!;
          final chrome = theme.extension<AppChrome>()!;
          expect(
            chrome.popupSurface,
            brightness == Brightness.light ? palette.surface : palette.bar,
          );
          expect(chrome.menuBarrier.a, lessThan(chrome.barrier.a));
        }
      });

      test('底部面板：深色整組往上一階，淺色不變（$name）', () {
        final light = buildAppTheme(style, Brightness.light);
        expect(sheetThemeOf(light), same(light));

        final dark = buildAppTheme(
          style,
          Brightness.dark,
          pureBlack: pureBlack,
        );
        final palette = dark.extension<StylePalette>()!;
        final sheet = sheetThemeOf(dark);
        final chrome = sheet.extension<AppChrome>()!;
        expect(chrome.groupedBackground, palette.surface);
        expect(chrome.groupedSurface, palette.bar);
        expect(sheet.colorScheme.surface, palette.bar);
        expect(
          AppLayers.lightness(chrome.glassTint) -
              AppLayers.lightness(palette.bar),
          closeTo(AppLayers.floatGapDark, 0.6),
        );
        // 面板裡再開面板不會一路往上疊。
        expect(sheetThemeOf(sheet), same(sheet));
      });

      test('面板頁首的鈕和面板底分得開：明度至少差 10（$name）', () {
        for (final brightness in Brightness.values) {
          final sheet = sheetThemeOf(
            buildAppTheme(style, brightness, pureBlack: pureBlack),
          );
          final chrome = sheet.extension<AppChrome>()!;
          final button = chrome.glassTint.withValues(alpha: 1);
          expect(
            AppLayers.lightness(button) -
                AppLayers.lightness(chrome.groupedBackground),
            greaterThan(10),
            reason: brightness.name,
          );
        }
      });
    }
  }

  const openers = {
    '彈出選單': _openMenu,
    '提示框': _openAlert,
    '動作表': _openActionSheet,
  };

  for (final brightness in Brightness.values) {
    for (final MapEntry(key: name, value: open) in openers.entries) {
      testWidgets('實色沒有模糊，$name與選中的膠囊完全不透明（${brightness.name}）', (
        tester,
      ) async {
        await _pump(tester, brightness, GlassStrength.solid, open);
        final alphas = _glassAlphas(tester);
        expect(alphas.length, greaterThan(1), reason: '$name應該畫在玻璃上');
        expect(alphas, everyElement(1.0));
      });

      testWidgets('霧面有模糊，$name照舊半透明（${brightness.name}）', (tester) async {
        await _pump(tester, brightness, GlassStrength.frosted, open);
        expect(_glassAlphas(tester), everyElement(lessThan(1.0)));
      });
    }

    test('提示訊息沒有模糊，底色完全不透明（${brightness.name}）', () {
      for (final strength in GlassStrength.values) {
        final theme = buildAppTheme(
          AppStyle.kraft,
          brightness,
          glassStrength: strength,
        );
        expect(theme.extension<AppChrome>()!.toastBackground.a, 1.0);
      }
    });
  }
}

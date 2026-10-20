import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_palette.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_highlight_style.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_layers.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WCAG 2.x 對比度。
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('每個風格的淺色與深色', () {
    for (final style in AppStyle.values) {
      for (final brightness in Brightness.values) {
        final palette = style.of(brightness);
        final name = '${style.label}・${brightness.name}';

        test('$name：所有底色都和深淺一致', () {
          expect(palette.brightness, brightness);
          for (final background in [
            palette.background,
            palette.surface,
            palette.bar,
            palette.readerBackground,
          ]) {
            expect(
              ThemeData.estimateBrightnessForColor(background),
              brightness,
            );
          }
        });

        test('$name：頁面、卡片、玻璃列與閱讀選單照分層規則拉開', () {
          double l(Color c) => AppLayers.lightness(c);
          final gap = AppLayers.cardGap(brightness);
          // 寫死的色碼取整到 8 位元，允許半階的誤差。
          const tolerance = 0.6;
          expect(
            l(palette.surface) - l(palette.background),
            closeTo(gap, tolerance),
            reason: '卡片比頁面亮',
          );
          if (brightness == Brightness.light) {
            expect(palette.bar, palette.surface, reason: '淺色玻璃與卡片同色');
          } else {
            expect(
              l(palette.bar) - l(palette.surface),
              closeTo(AppLayers.floatGapDark, tolerance),
              reason: '深色玻璃比卡片再亮一階',
            );
          }
          expect(
            (l(palette.readerMenu) - l(palette.readerBackground)).abs(),
            closeTo(gap, tolerance),
            reason: '閱讀選單和紙分開',
          );
          // 次要文字和閱讀選單的距離不比和卡片的近：選單底色移動時跟著移。
          final menuMuted = AppLayers.keepGap(
            palette.textMuted,
            palette.text,
            from: palette.surface,
            to: palette.readerMenu,
          );
          expect(
            (l(menuMuted) - l(palette.readerMenu)).abs(),
            greaterThanOrEqualTo(
              (l(palette.textMuted) - l(palette.surface)).abs() - tolerance,
            ),
            reason: '閱讀選單上的次要文字',
          );
          final chrome = buildAppTheme(
            style,
            brightness,
          ).extension<AppChrome>()!;
          expect(
            (l(chrome.cardEdge) - l(palette.surface)).abs(),
            closeTo(AppLayers.edgeGap, tolerance),
            reason: '卡片框線',
          );
        });
      }
    }
  });

  test('滑動動作的紙白字在顏料色底上對比達標', () {
    // SwipeActions 的按鈕前景固定是 paper50，底色傳 AppTint 的顏料色。
    for (final tint in [AppTint.rust, AppTint.azurite, AppTint.tea]) {
      expect(
        _contrast(AppPalette.paper50, tint.color),
        greaterThanOrEqualTo(4.5),
        reason: tint.name,
      );
    }
  });

  test('列首圖示方塊的紙白圖示在每個顏料色上對比達標', () {
    // GroupedIconTile 一律在顏料色底上畫 paper50 圖示；圖形元件至少 3:1。
    for (final tint in AppTint.values) {
      expect(
        _contrast(AppPalette.paper50, tint.color),
        greaterThanOrEqualTo(3),
        reason: tint.name,
      );
    }
  });

  testWidgets('App、閱讀正文、閱讀選單與高亮取自同一個風格與深淺', (tester) async {
    late BuildContext context;
    Future<void> pump(AppStyle style, ThemeMode mode) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(style, Brightness.light),
          darkTheme: buildAppTheme(style, Brightness.dark),
          themeMode: mode,
          home: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final style in AppStyle.values) {
      for (final (mode, brightness) in const [
        (ThemeMode.light, Brightness.light),
        (ThemeMode.dark, Brightness.dark),
      ]) {
        await pump(style, mode);
        final expected = style.of(brightness);
        final theme = Theme.of(context);
        final palette = StylePalette.of(context);
        final menu = ReaderV2MenuStyle.of(context);

        expect(theme.brightness, brightness);
        expect(palette, same(expected));
        expect(theme.scaffoldBackgroundColor, expected.background);
        expect(theme.colorScheme.primary, expected.primary);
        expect(theme.colorScheme.onPrimary, expected.onPrimary);
        expect(menu.brightness, brightness);
        expect(menu.foreground, expected.text);
        expect(menu.accent, expected.primary);
        expect(menu.onAccent, expected.onPrimary);
        expect(
          ReaderV2HighlightColor.theme.resolve(palette),
          expected.highlight,
        );
      }
    }
  });

  testWidgets('閱讀選單的主題每次推導都一樣，上層重建時選單不跟著重建', (tester) async {
    var builds = 0;
    late StateSetter rebuild;
    // 同一個 widget：只有主題改變時才會重建。
    final menu = Builder(
      builder: (context) {
        builds++;
        return ColoredBox(color: AppChrome.of(context).glassTint);
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Theme(
              data: ReaderV2MenuStyle.of(context)
                  .toSheetTheme(Theme.of(context)),
              child: menu,
            );
          },
        ),
      ),
    );
    final first = builds;
    rebuild(() {});
    await tester.pump();
    // 原本每次推導出新的 AppChrome、ThemeData 不相等，用到主題的元件全部
    // 重建，按鈕的主題漸變也重播。
    expect(builds, first);
  });

  test('強調色只換主色，其餘配色照風格', () {
    for (final accent in AppAccent.values) {
      for (final style in AppStyle.values) {
        for (final brightness in Brightness.values) {
          final reason = '${accent.label}・${style.label}・${brightness.name}';
          final theme = buildAppTheme(style, brightness, accent: accent);
          final palette = theme.extension<StylePalette>()!;
          final base = style.of(brightness);
          expect(
            palette.primary,
            accent.colorFor(brightness) ?? base.primary,
            reason: reason,
          );
          expect(theme.colorScheme.primary, palette.primary, reason: reason);
          expect(palette.background, base.background, reason: reason);
          expect(palette.text, base.text, reason: reason);
          expect(palette.readerText, base.readerText, reason: reason);
        }
      }
    }
  });

  group('ThemeSettingsProvider', () {
    tearDown(() => GetIt.instance.reset());

    Future<SharedPreferences> register(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      final prefs = await SharedPreferences.getInstance();
      GetIt.instance.registerSingleton<SharedPreferences>(prefs);
      return prefs;
    }

    test('風格保存後重新開啟仍是同一個', () async {
      final prefs = await register(<String, Object>{});
      final provider = ThemeSettingsProvider();
      expect(provider.style, AppStyle.paper);

      provider.setStyle(AppStyle.tea);
      expect(prefs.getString(PreferKey.appStyle), AppStyle.tea.name);
      expect(ThemeSettingsProvider().style, AppStyle.tea);
    });

    test('無法辨識的保存值回到預設風格', () async {
      await register(<String, Object>{PreferKey.appStyle: 'rainbow'});
      expect(ThemeSettingsProvider().style, AppStyle.paper);
    });

    test('強調色預設跟隨主題，保存後重新開啟仍是同一個', () async {
      final prefs = await register(<String, Object>{});
      final provider = ThemeSettingsProvider();
      expect(provider.accent, AppAccent.theme);

      provider.setAccent(AppAccent.bamboo);
      expect(prefs.getString(PreferKey.appAccent), AppAccent.bamboo.name);
      expect(ThemeSettingsProvider().accent, AppAccent.bamboo);
    });

    test('無法辨識的強調色回到跟隨主題', () async {
      await register(<String, Object>{PreferKey.appAccent: 'rainbow'});
      expect(ThemeSettingsProvider().accent, AppAccent.theme);
    });
  });
}

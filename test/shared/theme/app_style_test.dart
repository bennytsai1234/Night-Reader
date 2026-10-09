import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_palette.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_highlight_style.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
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

        test('$name：文字對比達標', () {
          // 正文與主要文字 WCAG AAA（7:1）；次要文字 AA（4.5:1）；
          // 主色作為開關、選取等元件色 3:1。
          expect(
            _contrast(palette.readerText, palette.readerBackground),
            greaterThanOrEqualTo(7),
          );
          // 資訊列是紙張上的次要文字；主色上的勾勾與文字同為 AA。
          expect(
            _contrast(palette.readerInfo, palette.readerBackground),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            _contrast(palette.onPrimary, palette.primary),
            greaterThanOrEqualTo(4.5),
          );
          for (final background in [palette.background, palette.surface]) {
            expect(
              _contrast(palette.text, background),
              greaterThanOrEqualTo(7),
            );
            expect(
              _contrast(palette.textMuted, background),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              _contrast(palette.primary, background),
              greaterThanOrEqualTo(3),
            );
          }
        });

        test('$name：提示訊息的文字與動作字對比達標', () {
          final chrome = buildAppTheme(
            style,
            brightness,
          ).extension<AppChrome>()!;
          // 提示底色帶一點透明，疊在頁面底色上量。
          final toast = Color.alphaBlend(
            chrome.toastBackground,
            palette.background,
          );
          expect(
            _contrast(chrome.toastForeground, toast),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            _contrast(chrome.toastAction, toast),
            greaterThanOrEqualTo(4.5),
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
  });
}

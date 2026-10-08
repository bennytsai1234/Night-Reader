import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_palette.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_highlight_style.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_style.dart';
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
      }
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
        expect(menu.brightness, brightness);
        expect(menu.foreground, expected.text);
        expect(menu.accent, expected.primary);
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

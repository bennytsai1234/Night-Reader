import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/features/settings/launch_screen_theme_sync.dart';
import 'package:night_reader/features/settings/settings_provider.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _res = 'android/app/src/main/res';

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

String _capitalized(String name) => name[0].toUpperCase() + name.substring(1);

/// 深色書架可能的底色：純黑，加上底色不是純黑的深色風格。
Map<String, Color> _darkBackgrounds() => {
  'black': const Color(0xFF000000),
  for (final style in AppStyle.values)
    if (style.dark.background != const Color(0xFF000000))
      style.name: style.dark.background,
};

void main() {
  group('LaunchScreenThemeSync', () {
    const channel = MethodChannel('night_reader/launch_screen');
    late List<Object?> calls;

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.arguments);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('啟動時送一次，風格、純黑或深淺改了再送，其他設定改了不送', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      GetIt.instance.registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      );
      addTearDown(GetIt.instance.reset);
      final themeSettings = ThemeSettingsProvider();
      final settings = SettingsProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: themeSettings),
            ChangeNotifierProvider.value(value: settings),
          ],
          child: const LaunchScreenThemeSync(child: SizedBox()),
        ),
      );
      expect(calls, [
        {'light': 'paper', 'dark': 'black', 'mode': 'system'},
      ]);

      themeSettings.setStyle(Brightness.light, AppStyle.kraft);
      themeSettings.setStyle(Brightness.dark, AppStyle.tea);
      themeSettings.setPureBlack(false);
      settings.setThemeMode(ThemeMode.dark);
      themeSettings.setGlassStrength(GlassStrength.values.last);
      await tester.pump();
      expect(calls.skip(1), [
        {'light': 'kraft', 'dark': 'black', 'mode': 'system'},
        {'light': 'kraft', 'dark': 'tea', 'mode': 'system'},
        {'light': 'kraft', 'dark': 'tea', 'mode': 'dark'},
      ], reason: '純黑開著時換深色風格，深色底仍是純黑，不用再送');
    });

    test('深色底照實際的書架底色：純黑、或深色風格自己的底色', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      GetIt.instance.registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      );
      addTearDown(GetIt.instance.reset);
      final themeSettings = ThemeSettingsProvider()..setPureBlack(false);
      final backgrounds = _darkBackgrounds();
      for (final style in AppStyle.values) {
        themeSettings.setStyle(Brightness.dark, style);
        final key = LaunchScreenThemeSync.darkKey(themeSettings);
        expect(
          backgrounds[key],
          themeSettings.paletteFor(Brightness.dark).background,
          reason: style.name,
        );
      }
    });
  });

  group('Android 啟動畫面資源', () {
    String colorsOf(String folder) =>
        File('$_res/$folder/launch_colors.xml').readAsStringSync();
    String? valueOf(String xml, String name) =>
        RegExp('<color name="$name">([^<]+)</color>').firstMatch(xml)?.group(1);

    test('每個淺色風格 × 深色底的顏色與書架底色一致', () {
      final day = colorsOf('values');
      final night = colorsOf('values-night');
      for (final style in AppStyle.values) {
        expect(
          valueOf(day, 'launch_${style.name}_light'),
          _hex(style.light.background),
          reason: '${style.name} 淺色',
        );
      }
      for (final MapEntry(key: dark, value: color)
          in _darkBackgrounds().entries) {
        expect(valueOf(day, 'launch_${dark}_dark'), _hex(color), reason: dark);
        for (final light in AppStyle.values) {
          final name = 'launch_${light.name}_$dark';
          expect(
            valueOf(day, name),
            '@color/launch_${light.name}_light',
            reason: '$name 淺色',
          );
          expect(
            valueOf(night, name),
            '@color/launch_${dark}_dark',
            reason: '$name 深色',
          );
        }
      }
    });

    test('每個組合都有啟動畫面主題，原生端也認得', () {
      final themes = File('$_res/values-v31/launch_themes.xml')
          .readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/com/inkpage/reader/MainActivity.kt',
      ).readAsStringSync();
      void expectTheme(String name, String key) {
        expect(themes, contains('<style name="LaunchTheme.$name"'));
        expect(
          activity,
          contains(
            '"$key" to R.style.LaunchTheme_${name.replaceAll('.', '_')},',
          ),
        );
      }

      final darks = _darkBackgrounds().keys;
      for (final light in AppStyle.values) {
        expectTheme('Light.${_capitalized(light.name)}', light.name);
        for (final dark in darks) {
          expectTheme(
            'System.${_capitalized(light.name)}${_capitalized(dark)}',
            '${light.name}/$dark',
          );
        }
      }
      for (final dark in darks) {
        expectTheme('Dark.${_capitalized(dark)}', dark);
      }
    });
  });
}

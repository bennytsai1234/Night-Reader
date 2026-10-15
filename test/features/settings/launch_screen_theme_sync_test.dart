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

    testWidgets('啟動時送一次，風格或深淺改了再送，其他設定改了不送', (tester) async {
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
        {'style': 'paper', 'mode': 'system'},
      ]);

      themeSettings.setStyle(AppStyle.plain);
      settings.setThemeMode(ThemeMode.dark);
      themeSettings.setGlassStrength(GlassStrength.values.last);
      await tester.pump();
      expect(calls.skip(1), [
        {'style': 'plain', 'mode': 'system'},
        {'style': 'plain', 'mode': 'dark'},
      ]);
    });
  });

  group('Android 啟動畫面資源', () {
    test('每個風格的底色與書架底色一致', () {
      final xml = File('$_res/values/launch_colors.xml').readAsStringSync();
      String colorOf(String name) =>
          RegExp('<color name="$name">(#[0-9A-F]{6})</color>')
              .firstMatch(xml)
              ?.group(1) ??
          'missing';
      for (final style in AppStyle.values) {
        expect(
          colorOf('launch_${style.name}_light'),
          _hex(style.light.background),
          reason: '${style.name} 淺色',
        );
        expect(
          colorOf('launch_${style.name}_dark'),
          _hex(style.dark.background),
          reason: '${style.name} 深色',
        );
      }
    });

    test('每個風格都有啟動畫面主題，原生端也認得', () {
      final themes = File('$_res/values-v31/launch_themes.xml')
          .readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/com/inkpage/reader/MainActivity.kt',
      ).readAsStringSync();
      for (final style in AppStyle.values) {
        final theme = 'LaunchTheme.${_capitalized(style.name)}';
        for (final variant in [theme, '$theme.Light', '$theme.Dark']) {
          expect(themes, contains('<style name="$variant">'));
        }
        expect(activity, contains('"${style.name}" to LaunchThemes('));
      }
    });
  });
}

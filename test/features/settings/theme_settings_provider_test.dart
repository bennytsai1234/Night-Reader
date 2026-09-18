import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/theme_customization.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ThemeSettingsProvider? provider;

  Future<ThemeSettingsProvider> createProvider(
    Map<String, Object> initialValues,
  ) async {
    provider?.dispose();
    provider = null;
    await getIt.reset();
    SharedPreferences.setMockInitialValues(initialValues);
    final prefs = await SharedPreferences.getInstance();
    getIt.registerSingleton<SharedPreferences>(prefs);
    provider = ThemeSettingsProvider();
    return provider!;
  }

  tearDown(() async {
    provider?.dispose();
    provider = null;
    await getIt.reset();
  });

  test('reader and menu modes persist independently', () async {
    final settings = await createProvider(<String, Object>{});

    settings.setAreaMode(ThemeArea.reader, AreaThemeMode.dark);
    settings.setAreaMode(ThemeArea.menu, AreaThemeMode.light);

    settings.dispose();
    provider = ThemeSettingsProvider();

    expect(provider!.readerMode, AreaThemeMode.dark);
    expect(provider!.menuMode, AreaThemeMode.light);
  });

  testWidgets('follow system resolves current platform brightness', (
    tester,
  ) async {
    final settings = await createProvider(<String, Object>{});
    settings.setAreaMode(ThemeArea.reader, AreaThemeMode.followSystem);

    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    addTearDown(
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    expect(
      ThemeSettingsProvider.resolveAreaDarkMode(
        ThemeArea.reader,
        fallback: false,
      ),
      isTrue,
    );

    tester.binding.platformDispatcher.platformBrightnessTestValue =
        Brightness.light;
    expect(
      ThemeSettingsProvider.resolveAreaDarkMode(
        ThemeArea.reader,
        fallback: true,
      ),
      isFalse,
    );
  });

  test('custom colors and enable switches survive reconstruction', () async {
    const appLight = AppUiThemeColors(
      primary: Color(0xFF112233),
      secondary: Color(0xFF223344),
      background: Color(0xFF334455),
      surface: Color(0xFF445566),
      appBar: Color(0xFF556677),
      navigation: Color(0xFF667788),
      textPrimary: Color(0xFF778899),
      textSecondary: Color(0xFF8899AA),
      border: Color(0xFF99AABB),
    );
    const readerDark = ReaderAreaThemeColors(
      background: Color(0xFF101820),
      text: Color(0xFFE0E8F0),
      secondaryText: Color(0xFFA0A8B0),
      accent: Color(0xFF00AA88),
      highlight: Color(0xFF334422),
      border: Color(0xFF556677),
    );
    const menuLight = ReaderAreaThemeColors(
      background: Color(0xFFF8F4EC),
      text: Color(0xFF201810),
      secondaryText: Color(0xFF605850),
      accent: Color(0xFF884422),
      highlight: Color(0xFFE8DCC8),
      border: Color(0xFFC8BCA8),
    );

    final settings = await createProvider(<String, Object>{});
    settings.updateApp(false, appLight);
    settings.setUseCustom(ThemeArea.app, false, true);
    settings.updateArea(ThemeArea.reader, true, readerDark);
    settings.setUseCustom(ThemeArea.reader, true, true);
    settings.updateArea(ThemeArea.menu, false, menuLight);
    settings.setUseCustom(ThemeArea.menu, false, true);

    settings.dispose();
    provider = ThemeSettingsProvider();

    expect(provider!.appLightCustom, isTrue);
    expect(provider!.appLight.primary, appLight.primary);
    expect(provider!.appLight.border, appLight.border);
    expect(provider!.readerDarkCustom, isTrue);
    expect(provider!.readerDark.background, readerDark.background);
    expect(provider!.readerDark.accent, readerDark.accent);
    expect(provider!.menuLightCustom, isTrue);
    expect(provider!.menuLight.text, menuLight.text);
    expect(provider!.menuLight.highlight, menuLight.highlight);
  });

  test('legacy followApp storage migrates to followSystem behavior', () async {
    final settings = await createProvider(<String, Object>{
      'theme_reader_mode_v1': 'followApp',
      'theme_menu_mode_v1': 'system',
    });

    expect(settings.readerMode, AreaThemeMode.followSystem);
    expect(settings.menuMode, AreaThemeMode.followSystem);
  });

  test('malformed custom JSON falls back without disabling custom mode', () async {
    final settings = await createProvider(<String, Object>{
      'theme_reader_light_custom_v1': '{not-json',
      'theme_reader_light_use_custom': true,
    });

    expect(settings.readerLightCustom, isTrue);
    expect(
      settings.readerLight.background,
      ReaderAreaThemeColors.contentLightDefault.background,
    );
    expect(
      settings.readerLight.text,
      ReaderAreaThemeColors.contentLightDefault.text,
    );
  });
}

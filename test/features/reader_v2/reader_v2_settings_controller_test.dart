import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_constants.dart';
import 'package:night_reader/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('readStyleFor does not double-count externally reserved top inset', () {
    final controller = ReaderV2SettingsController();
    const padding = EdgeInsets.only(top: 24, bottom: 16);

    final internal = controller.readStyleFor(padding);
    final external = controller.readStyleFor(
      padding,
      topInfoReservedExternally: true,
    );

    expect(external.paddingTop, kReaderContentTopSpacing);
    expect(
      internal.paddingTop,
      kReaderContentTopSpacing + 24 * kReaderContentTopSafeAreaFactor,
    );
  });

  test(
    'menu theme defaults to reader theme and persists independently',
    () async {
      final previousThemes = AppTheme.readingThemes;
      addTearDown(() {
        AppTheme.readingThemes = previousThemes;
      });
      AppTheme.readingThemes = [
        ReadingTheme(
          name: 'light',
          backgroundColor: Colors.white,
          textColor: Colors.black,
        ),
        ReadingTheme(
          name: 'dark',
          backgroundColor: Colors.black,
          textColor: Colors.white,
        ),
        ReadingTheme(
          name: 'paper',
          backgroundColor: const Color(0xFFF4F1E8),
          textColor: const Color(0xFF244739),
        ),
      ];
      SharedPreferences.setMockInitialValues(<String, Object>{
        PreferKey.readerThemeIndex: 1,
      });

      final controller = ReaderV2SettingsController();
      await controller.loadSettings();

      expect(controller.themeIndex, 1);
      expect(controller.menuThemeIndex, 1);
      expect(controller.currentMenuTheme.name, 'dark');

      controller.setMenuTheme(2);
      final prefs = await SharedPreferences.getInstance();

      expect(controller.themeIndex, 1);
      expect(controller.menuThemeIndex, 2);
      expect(prefs.getInt(PreferKey.readerMenuThemeIndex), 2);
    },
  );

  test('auto page speed loads, clamps, and persists', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferKey.readerAutoPageSpeed: 0.2,
    });

    final controller = ReaderV2SettingsController();
    await controller.loadSettings();

    expect(controller.autoPageSpeed, 0.2);

    controller.setAutoPageSpeed(1.0);
    final prefs = await SharedPreferences.getInstance();

    expect(
      controller.autoPageSpeed,
      ReaderV2SettingsController.maxAutoPageSpeed,
    );
    expect(
      prefs.getDouble(PreferKey.readerAutoPageSpeed),
      ReaderV2SettingsController.maxAutoPageSpeed,
    );
  });
}

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

    controller.setAutoPageSpeed(0.001);
    // saveAutoPageSpeed 為 unawaited 非同步，讓 event queue 先跑完。
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.autoPageSpeed,
      ReaderV2SettingsController.minAutoPageSpeed,
    );
    expect(
      prefs.getDouble(PreferKey.readerAutoPageSpeed),
      ReaderV2SettingsController.minAutoPageSpeed,
    );
  });

  test('auto page speed floor allows slower than legacy 8%', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferKey.readerAutoPageSpeed: 0.02,
    });

    final controller = ReaderV2SettingsController();
    await controller.loadSettings();

    // 舊版載入時把速度硬 clamp 到 0.08；下限放寬後 0.02 必須原樣保留。
    expect(controller.autoPageSpeed, 0.02);
  });

  test('last line spacing compensation loads and persists', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferKey.readerLastLineSpacingCompensation: true,
    });

    final controller = ReaderV2SettingsController();
    await controller.loadSettings();

    expect(controller.lastLineSpacingCompensation, isTrue);

    controller.setLastLineSpacingCompensation(false);
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PreferKey.readerLastLineSpacingCompensation), isFalse);
  });

  test('typography batch persists four values with one notification', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = ReaderV2SettingsController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    controller.setTypography(
      fontSize: 20,
      lineHeight: 1.8,
      paragraphSpacing: 1.2,
      letterSpacing: 0.6,
    );
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    expect(notifications, 1);
    expect(controller.fontSize, 20);
    expect(controller.lineHeight, 1.8);
    expect(controller.paragraphSpacing, 1.2);
    expect(controller.letterSpacing, 0.6);
    expect(prefs.getDouble(PreferKey.readerFontSize), 20);
    expect(prefs.getDouble(PreferKey.readerLineHeight), 1.8);
    expect(prefs.getDouble(PreferKey.readerParagraphSpacing), 1.2);
    expect(prefs.getDouble(PreferKey.readerLetterSpacing), 0.6);

    await prefs.remove(PreferKey.readerFontSize);
    controller.setTypography(
      fontSize: 20,
      lineHeight: 1.8,
      paragraphSpacing: 1.2,
      letterSpacing: 0.6,
    );
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
    expect(prefs.getDouble(PreferKey.readerFontSize), 20);
  });
}

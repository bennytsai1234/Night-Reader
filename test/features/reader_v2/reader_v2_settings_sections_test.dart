import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_palette.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_prefs_repository.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_controller.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_settings_sections.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 與正式環境一致：啟動時已初始化，後續 fire-and-forget 寫入依序完成。
    await SharedPreferences.getInstance();
  });

  group('ReaderV2SettingsController resets', () {
    test('resetTypography restores and persists defaults', () async {
      final settings = ReaderV2SettingsController();
      settings.setTypography(
        fontSize: 30,
        lineHeight: 2.4,
        letterSpacing: 1.5,
        paragraphSpacing: 2.0,
        chapterSpacing: 3.5,
      );
      settings.setTextIndent(4);

      settings.resetTypography();
      await pumpEventQueue();

      final defaults = ReaderV2PrefsSnapshot.defaults();
      expect(settings.fontSize, defaults.fontSize);
      expect(settings.lineHeight, defaults.lineHeight);
      expect(settings.letterSpacing, defaults.letterSpacing);
      expect(settings.paragraphSpacing, defaults.paragraphSpacing);
      expect(settings.chapterSpacing, defaults.chapterSpacing);
      expect(settings.textIndent, defaults.textIndent);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(PreferKey.readerFontSize), defaults.fontSize);
      expect(prefs.getInt(PreferKey.readerTextIndent), defaults.textIndent);
      expect(
        prefs.getDouble(PreferKey.readerChapterSpacing),
        defaults.chapterSpacing,
      );
    });

    test('resetClickActions restores default grid', () async {
      final settings = ReaderV2SettingsController();
      settings.setClickAction(0, ReaderV2TapAction.values.last.code);

      settings.resetClickActions();
      await pumpEventQueue();

      expect(settings.clickActions, ReaderV2TapAction.defaultGrid());
    });
  });

  Future<ReaderV2SettingsController> pumpSection(
    WidgetTester tester, {
    bool collapsible = false,
  }) async {
    final settings = ReaderV2SettingsController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReaderV2TypographySection(
              settings: settings,
              collapsible: collapsible,
            ),
          ),
        ),
      ),
    );
    return settings;
  }

  testWidgets('typography steps are coalesced into one delayed commit', (
    tester,
  ) async {
    final settings = await pumpSection(tester);
    final initial = settings.fontSize;
    var notifications = 0;
    settings.addListener(() => notifications++);

    final plus = find.byIcon(Icons.add_rounded).first;
    await tester.tap(plus);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(plus);
    await tester.pump(const Duration(milliseconds: 50));
    expect(settings.fontSize, initial);

    await tester.pump(const Duration(milliseconds: 150));
    expect(settings.fontSize, initial + 2);
    expect(notifications, 1);
  });

  testWidgets('reset button is disabled at defaults and restores values', (
    tester,
  ) async {
    final settings = await pumpSection(tester);
    TextButton resetButton() => tester.widget<TextButton>(
      find.widgetWithText(TextButton, '恢復預設'),
    );
    expect(resetButton().onPressed, isNull);

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();
    expect(resetButton().onPressed, isNotNull);

    // 延遲提交尚未觸發前重設，待提交的步進必須被丟棄。
    await tester.tap(find.widgetWithText(TextButton, '恢復預設'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(settings.fontSize, ReaderV2PrefsSnapshot.defaults().fontSize);
    expect(resetButton().onPressed, isNull);
  });

  testWidgets('collapsible section hides secondary rows until expanded', (
    tester,
  ) async {
    await pumpSection(tester, collapsible: true);
    expect(find.text('字號'), findsOneWidget);
    expect(find.text('字距'), findsNothing);

    await tester.tap(find.text('更多排版'));
    await tester.pumpAndSettle();
    expect(find.text('字距'), findsOneWidget);
    expect(find.text('首行縮排'), findsOneWidget);
  });

  test('menu sheet theme follows menu palette colors', () {
    const foreground = Color(0xFFE0DACC);
    final style = ReaderV2MenuStyle(
      background: const Color(0xF5141210),
      backgroundElevated: const Color(0x14FFFFFF),
      foreground: foreground,
      mutedForeground: foreground.withValues(alpha: 0.68),
      outline: foreground.withValues(alpha: 0.12),
      accent: const Color(0xFFD67B6E),
      accentMuted: const Color(0x2ED67B6E),
      scrim: const Color(0x2E000000),
    );
    final theme = style.toSheetTheme(ThemeData.light());

    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.colorScheme.onSurface, foreground);
    expect(theme.colorScheme.surface, const Color(0xFF141210));
    expect(theme.textTheme.bodyMedium?.color, foreground);
  });
}

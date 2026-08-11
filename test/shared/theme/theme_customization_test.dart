import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/theme/theme_customization.dart';

void main() {
  group('AppUiThemeColors', () {
    test('JSON round trip preserves every color', () {
      const original = AppUiThemeColors(
        primary: Color(0xFF123456),
        secondary: Color(0xFF234567),
        background: Color(0xFF345678),
        surface: Color(0xFF456789),
        appBar: Color(0xFF56789A),
        navigation: Color(0xFF6789AB),
        textPrimary: Color(0xFF789ABC),
        textSecondary: Color(0xFF89ABCD),
        border: Color(0xFF9ABCDE),
      );

      final restored = AppUiThemeColors.fromJson(
        original.toJson(),
        fallback: AppUiThemeColors.lightDefault,
      );

      expect(restored.primary, original.primary);
      expect(restored.secondary, original.secondary);
      expect(restored.background, original.background);
      expect(restored.surface, original.surface);
      expect(restored.appBar, original.appBar);
      expect(restored.navigation, original.navigation);
      expect(restored.textPrimary, original.textPrimary);
      expect(restored.textSecondary, original.textSecondary);
      expect(restored.border, original.border);
    });

    test('buildAppTheme maps custom colors to Material theme', () {
      const colors = AppUiThemeColors(
        primary: Color(0xFF123456),
        secondary: Color(0xFF234567),
        background: Color(0xFF345678),
        surface: Color(0xFF456789),
        appBar: Color(0xFF56789A),
        navigation: Color(0xFF6789AB),
        textPrimary: Color(0xFF789ABC),
        textSecondary: Color(0xFF89ABCD),
        border: Color(0xFF9ABCDE),
      );

      final theme = buildAppTheme(colors, Brightness.light);

      expect(theme.colorScheme.primary, colors.primary);
      expect(theme.colorScheme.secondary, colors.secondary);
      expect(theme.colorScheme.onSurface, colors.textPrimary);
      expect(theme.colorScheme.onSurfaceVariant, colors.textSecondary);
      expect(theme.scaffoldBackgroundColor, colors.background);
      expect(theme.appBarTheme.backgroundColor, colors.appBar);
      expect(theme.navigationBarTheme.backgroundColor, colors.navigation);
      expect(theme.dividerTheme.color, colors.border);
    });
  });

  group('ReaderAreaThemeColors', () {
    test('JSON round trip preserves every color', () {
      const original = ReaderAreaThemeColors(
        background: Color(0xFF102030),
        text: Color(0xFFE0E0E0),
        secondaryText: Color(0xFFB0B0B0),
        accent: Color(0xFF00AA88),
        highlight: Color(0xFF554411),
        border: Color(0xFF667788),
      );

      final restored = ReaderAreaThemeColors.fromJson(
        original.toJson(),
        fallback: ReaderAreaThemeColors.contentDarkDefault,
      );

      expect(restored.background, original.background);
      expect(restored.text, original.text);
      expect(restored.secondaryText, original.secondaryText);
      expect(restored.accent, original.accent);
      expect(restored.highlight, original.highlight);
      expect(restored.border, original.border);
    });

    test('invalid values fall back without throwing', () {
      final restored = ReaderAreaThemeColors.fromJson(
        const {'background': 'not-a-color'},
        fallback: ReaderAreaThemeColors.contentLightDefault,
      );

      expect(
        restored.background,
        ReaderAreaThemeColors.contentLightDefault.background,
      );
      expect(restored.text, ReaderAreaThemeColors.contentLightDefault.text);
    });
  });
}

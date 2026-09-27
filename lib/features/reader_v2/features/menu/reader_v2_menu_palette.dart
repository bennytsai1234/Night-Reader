import 'package:flutter/material.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';

class ReaderV2MenuStyle {
  final Color background;
  final Color backgroundElevated;
  final Color foreground;
  final Color mutedForeground;
  final Color outline;
  final Color accent;
  final Color accentMuted;
  final Color scrim;

  const ReaderV2MenuStyle({
    required this.background,
    required this.backgroundElevated,
    required this.foreground,
    required this.mutedForeground,
    required this.outline,
    required this.accent,
    required this.accentMuted,
    required this.scrim,
  });

  factory ReaderV2MenuStyle.resolve({
    required BuildContext context,
    required Color backgroundColor,
    required Color textColor,
  }) {
    final dark = backgroundColor.computeLuminance() < 0.5;
    final custom = ThemeSettingsProvider.resolveReaderAreaColors(
      dark: dark,
      menu: true,
    );
    final background = (custom?.background ?? backgroundColor).withValues(
      alpha: 0.96,
    );
    final foreground = custom?.text ?? textColor;
    final accent = custom?.accent ?? Theme.of(context).colorScheme.primary;
    return ReaderV2MenuStyle(
      background: background,
      backgroundElevated:
          custom?.highlight ??
          Color.alphaBlend(
            foreground.withValues(alpha: 0.06),
            background,
          ),
      foreground: foreground,
      mutedForeground:
          custom?.secondaryText ?? foreground.withValues(alpha: 0.68),
      outline: custom?.border ?? foreground.withValues(alpha: 0.12),
      accent: accent,
      accentMuted: accent.withValues(alpha: 0.18),
      scrim: Colors.black.withValues(alpha: 0.18),
    );
  }

  /// 閱讀器內設定面板（排版、進階、朗讀）使用的主題：
  /// 以選單配色覆寫 App 主題，讓面板與上下選單屬於同一個視覺區域。
  ThemeData toSheetTheme(ThemeData base) {
    final surface = background.withValues(alpha: 1);
    final dark = surface.computeLuminance() < 0.5;
    final elevated = Color.alphaBlend(backgroundElevated, surface);
    final accentContainer = Color.alphaBlend(accentMuted, surface);
    final onAccent =
        ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : Colors.black;
    final strongOutline = Color.alphaBlend(
      foreground.withValues(alpha: 0.32),
      surface,
    );
    final colorScheme = base.colorScheme.copyWith(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: accentContainer,
      onPrimaryContainer: foreground,
      secondaryContainer: accentContainer,
      onSecondaryContainer: foreground,
      surface: surface,
      onSurface: foreground,
      onSurfaceVariant: mutedForeground,
      surfaceContainerLowest: surface,
      surfaceContainerLow: surface,
      surfaceContainer: elevated,
      surfaceContainerHigh: elevated,
      surfaceContainerHighest: elevated,
      outline: strongOutline,
      outlineVariant: outline,
    );
    return base.copyWith(
      colorScheme: colorScheme,
      canvasColor: surface,
      dividerColor: outline,
      iconTheme: base.iconTheme.copyWith(color: foreground),
      textTheme: base.textTheme.apply(
        bodyColor: foreground,
        displayColor: foreground,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: surface,
        modalBackgroundColor: surface,
      ),
      dialogTheme: base.dialogTheme.copyWith(backgroundColor: elevated),
    );
  }
}

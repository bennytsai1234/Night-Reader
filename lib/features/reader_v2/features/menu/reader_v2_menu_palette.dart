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
}

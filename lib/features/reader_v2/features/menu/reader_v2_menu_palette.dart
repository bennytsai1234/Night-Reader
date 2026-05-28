import 'package:flutter/material.dart';

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
    final accent = Theme.of(context).colorScheme.primary;
    final background = backgroundColor.withValues(alpha: 0.96);
    return ReaderV2MenuStyle(
      background: background,
      backgroundElevated: Color.alphaBlend(
        textColor.withValues(alpha: 0.06),
        background,
      ),
      foreground: textColor,
      mutedForeground: textColor.withValues(alpha: 0.68),
      outline: textColor.withValues(alpha: 0.12),
      accent: accent,
      accentMuted: accent.withValues(alpha: 0.18),
      scrim: Colors.black.withValues(alpha: 0.18),
    );
  }
}

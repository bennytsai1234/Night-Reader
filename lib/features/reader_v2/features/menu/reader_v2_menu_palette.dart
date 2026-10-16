import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_style.dart';

/// 閱讀選單（上下選單、目錄、閱讀器內面板）的配色，取自目前風格。
class ReaderV2MenuStyle {
  final Brightness brightness;
  final Color background;
  final Color backgroundElevated;
  final Color foreground;
  final Color mutedForeground;
  final Color outline;
  final Color accent;
  final Color onAccent;
  final Color accentMuted;
  final Color scrim;

  const ReaderV2MenuStyle({
    required this.brightness,
    required this.background,
    required this.backgroundElevated,
    required this.foreground,
    required this.mutedForeground,
    required this.outline,
    required this.accent,
    required this.onAccent,
    required this.accentMuted,
    required this.scrim,
  });

  factory ReaderV2MenuStyle.of(BuildContext context) {
    final palette = StylePalette.of(context);
    final background = palette.surface.withValues(alpha: 0.96);
    final foreground = palette.text;
    return ReaderV2MenuStyle(
      brightness: palette.brightness,
      background: background,
      backgroundElevated: Color.alphaBlend(
        foreground.withValues(alpha: 0.06),
        background,
      ),
      foreground: foreground,
      mutedForeground: palette.textMuted,
      outline: palette.border,
      accent: palette.primary,
      onAccent: palette.onPrimary,
      accentMuted: palette.primary.withValues(alpha: 0.18),
      scrim: Colors.black.withValues(alpha: 0.18),
    );
  }

  /// 浮動玻璃選單（上下膠囊、圓形按鈕）的色調：選單底色套上使用者所選
  /// 玻璃強度的不透明度，背後的正文經模糊後只透出色塊。
  Color glassTintOf(BuildContext context) {
    return background.withValues(
      alpha: AppChrome.of(context).glassStrength
          .opacity(dark: brightness == Brightness.dark),
    );
  }

  /// 閱讀器內設定面板（排版、進階、朗讀）使用的主題：
  /// 以選單配色覆寫 App 主題，讓面板與上下選單屬於同一個視覺區域。
  /// 玻璃與分組元件的衍生色（[AppChrome]）也改由選單配色推導，
  /// 不沿用 App 主題掛載的擴充。
  ThemeData toSheetTheme(ThemeData base) {
    final surface = background.withValues(alpha: 1);
    final elevated = Color.alphaBlend(backgroundElevated, surface);
    final accentContainer = Color.alphaBlend(accentMuted, surface);
    final strongOutline = Color.alphaBlend(
      foreground.withValues(alpha: 0.32),
      surface,
    );
    final colorScheme = base.colorScheme.copyWith(
      brightness: brightness,
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
      extensions: [
        for (final extension in base.extensions.values)
          if (extension is! AppChrome) extension,
        AppChrome.derive(
          brightness: brightness,
          primary: accent,
          background: surface,
          // 分組卡片用浮層色，才能與面板底色區隔。
          surface: elevated,
          bar: surface,
          textPrimary: foreground,
          textSecondary: mutedForeground,
          border: outline,
          inversePrimary: base.colorScheme.inversePrimary,
          glassStrength:
              base.extension<AppChrome>()?.glassStrength ??
              GlassStrength.frosted,
        ),
      ],
    );
  }
}

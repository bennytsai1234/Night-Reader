import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_layers.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/widgets/popups/popup_routes.dart';

/// 閱讀選單（上下選單、目錄、閱讀器內面板）的配色，取自目前風格。
class ReaderMenuStyle {
  final Brightness brightness;
  final Color background;
  final Color backgroundElevated;
  final Color foreground;
  final Color mutedForeground;
  final Color outline;

  /// 面板裡分組卡片上的分隔線；[outline] 是直接畫在選單底上的列（目錄）用的。
  /// 兩者和底色的深淺差都照 App 的分隔線和卡片的差距。
  final Color cardOutline;
  final Color accent;
  final Color onAccent;
  final Color accentMuted;

  /// 目錄面板背後的遮罩。比 App 的遮罩重：淺色的面板比紙暗，壓淺了面板和
  /// 露出的那一條正文分不開。
  final Color scrim;

  const ReaderMenuStyle({
    required this.brightness,
    required this.background,
    required this.backgroundElevated,
    required this.foreground,
    required this.mutedForeground,
    required this.outline,
    required this.cardOutline,
    required this.accent,
    required this.onAccent,
    required this.accentMuted,
    required this.scrim,
  });

  factory ReaderMenuStyle.of(BuildContext context) =>
      ReaderMenuStyle.fromPalette(StylePalette.of(context));

  /// 閱讀選單那一層的主題，照外層的主題 [base] 算（[toSheetTheme]）；給
  /// [DerivedTheme]，系統切換深淺時跟著換。
  static ThemeData menuThemeOf(ThemeData base) =>
      ReaderMenuStyle.fromPalette(StylePalette.ofTheme(base))
          .toSheetTheme(base);

  /// 裡面是分組卡片的閱讀器面板用的 [menuThemeOf]（`cards: true`）。
  static ThemeData cardsMenuThemeOf(ThemeData base) =>
      ReaderMenuStyle.fromPalette(StylePalette.ofTheme(base))
          .toSheetTheme(base, cards: true);

  factory ReaderMenuStyle.fromPalette(StylePalette palette) {
    final background = palette.readerMenu.withValues(alpha: 0.96);
    final foreground = palette.text;
    // 面板裡的卡片照分層：淺色的面板比紙暗，卡片往紙的顏色亮回一階（到
    // 紙色就停）；深色的面板比紙亮，卡片再亮一階。
    final card = palette.brightness == Brightness.light
        ? AppLayers.step(
            palette.readerMenu,
            palette.readerBackground,
            AppLayers.cardGapLight,
          )
        : AppLayers.step(
            palette.readerMenu,
            foreground,
            AppLayers.floatGapDark,
          );
    final lineGap =
        (AppLayers.lightness(palette.border) -
                AppLayers.lightness(palette.surface))
            .abs();
    return ReaderMenuStyle(
      brightness: palette.brightness,
      background: background,
      backgroundElevated: card,
      foreground: foreground,
      // 次要文字是照卡片調的；閱讀選單淺色比卡片暗，跟著加深。
      mutedForeground: AppLayers.keepGap(
        palette.textMuted,
        foreground,
        from: palette.surface,
        to: palette.readerMenu,
      ),
      outline: AppLayers.step(palette.readerMenu, foreground, lineGap),
      cardOutline: AppLayers.step(card, foreground, lineGap),
      accent: palette.primary,
      onAccent: palette.onPrimary,
      accentMuted: palette.primary.withValues(alpha: 0.18),
      scrim: Colors.black54,
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
  ///
  /// [cards]：裡面是分組卡片的面板給 true，分隔線照卡片算（[cardOutline]）；
  /// 列直接畫在面板底上的（目錄、上下選單）照 [outline]。
  ThemeData toSheetTheme(ThemeData base, {bool cards = false}) {
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
          border: cards ? cardOutline : outline,
          inversePrimary: base.colorScheme.inversePrimary,
          glassStrength:
              base.extension<AppChrome>()?.glassStrength ??
              GlassStrength.unspecified,
        ),
      ],
    );
  }
}

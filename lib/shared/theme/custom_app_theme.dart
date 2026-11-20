import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';

import 'app_chrome.dart';
import 'app_style.dart';
import 'app_text_styles.dart';
import 'app_tokens.dart';

/// [style] 是這個深淺用的風格；[pureBlack] 只影響深色（「深色用純黑」）。
ThemeData buildAppTheme(
  AppStyle style,
  Brightness brightness, {
  GlassStrength glassStrength = GlassStrength.unspecified,
  AppAccent accent = AppAccent.theme,
  AppPageTransition pageTransition = AppPageTransition.slide,
  bool pureBlack = false,
  String? fontFamily,
}) {
  final colors = style.paletteFor(brightness, accent, pureBlack: pureBlack);
  // 淺色模式的提示訊息是深底，動作字取深色配色的主色才看得清楚。
  final inversePrimary = style
      .paletteFor(
        brightness == Brightness.light ? Brightness.dark : Brightness.light,
        accent,
      )
      .primary;
  final primaryContainer = Color.alphaBlend(
    colors.primary.withValues(
      alpha: brightness == Brightness.light ? 0.14 : 0.24,
    ),
    colors.surface,
  );
  final secondaryContainer = Color.alphaBlend(
    colors.secondary.withValues(
      alpha: brightness == Brightness.light ? 0.13 : 0.22,
    ),
    colors.surface,
  );

  final scheme =
      ColorScheme.fromSeed(
        seedColor: colors.primary,
        brightness: brightness,
      ).copyWith(
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: colors.text,
        secondary: colors.secondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: colors.text,
        surface: colors.surface,
        onSurface: colors.text,
        onSurfaceVariant: colors.textMuted,
        outline: colors.border,
        outlineVariant: colors.border.withValues(alpha: 0.72),
        inversePrimary: inversePrimary,
        // 危險色用設計的赭石（同 context.danger），不用 Material 預設紅。
        error: brightness == Brightness.light
            ? AppPalette.rust
            : AppPalette.rustDark,
        onError: brightness == Brightness.light
            ? AppPalette.paper50
            : AppPalette.ink700,
      );

  final fonts = _uiFonts(fontFamily);
  final textTheme = ThemeData(brightness: brightness).textTheme
      .copyWith(
        titleLarge: AppTextStyles.titleLg,
        titleMedium: AppTextStyles.titleMd,
        titleSmall: AppTextStyles.uiMd,
        bodyLarge: AppTextStyles.bodyMd,
        bodyMedium: AppTextStyles.bodyBase,
        bodySmall: AppTextStyles.bodySm,
        labelLarge: AppTextStyles.uiSm,
        labelMedium: AppTextStyles.labelSm,
        labelSmall: AppTextStyles.labelXs,
      )
      .merge(fonts)
      .apply(bodyColor: colors.text, displayColor: colors.text);

  final chrome = AppChrome.derive(
    brightness: brightness,
    primary: colors.primary,
    background: colors.background,
    surface: colors.surface,
    bar: colors.bar,
    textPrimary: colors.text,
    textSecondary: colors.textMuted,
    border: colors.border,
    inversePrimary: inversePrimary,
    glassStrength: glassStrength,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.background,
    // 骨架的樣子與換場不給選，`SkeletonLook.of`、`SkeletonReveal.of` 沒有
    // 擴充時用預設。
    extensions: [chrome, colors],
    // 點擊回饋採 Telegram 式整列高亮，不畫水波紋。
    splashFactory: NoSplash.splashFactory,
    highlightColor: chrome.pressedHighlight,
    hoverColor: Colors.transparent,
    // 全 App 換頁用使用者選的轉場（含開書），支援左緣右滑與 Android 預測
    // 返回；閱讀器關掉右滑返回（見 BookOpenRoute）。
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        TargetPlatform.android: AppPageTransitionsBuilder(pageTransition),
        TargetPlatform.iOS: AppPageTransitionsBuilder(pageTransition),
      },
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: chrome.toastBackground,
      actionTextColor: chrome.toastAction,
      closeIconColor: chrome.toastForeground,
      contentTextStyle: AppTextStyles.uiMd
          .copyWith(color: chrome.toastForeground, fontWeight: FontWeight.w400)
          .merge(fonts.bodyMedium),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardLg),
      insetPadding: const EdgeInsets.fromLTRB(
        AppGrouped.margin,
        AppSpacing.sm,
        AppGrouped.margin,
        AppSpacing.md,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.bar,
      foregroundColor: colors.text,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: colors.text,
      ).merge(fonts.titleLarge),
    ),
    cardTheme: CardThemeData(
      elevation: brightness == Brightness.light ? 1 : 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardLg),
      color: colors.surface,
      shadowColor: brightness == Brightness.light
          ? const Color(0x0A241C10)
          : null,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.topSheetXl),
      backgroundColor: colors.surface,
      modalBackgroundColor: colors.surface,
    ),
    dividerTheme: DividerThemeData(
      thickness: 1,
      space: 1,
      color: colors.border,
    ),
    // outline 是髮絲分隔線色，當按鈕外框對頁面底只有約 1.3:1；外框按鈕
    // 改用主色框線。
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(side: BorderSide(color: colors.primary)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      border: const OutlineInputBorder(
        borderRadius: AppRadius.cardMd,
        borderSide: BorderSide.none,
      ),
    ),
    textTheme: textTheme,
    primaryTextTheme: fonts,
  );
}

/// 介面文字的字族，只有字族、不含字級與顏色：標點（，。、；：！？「」『』
/// …—）由夜讀的標點字型畫，和閱讀器一樣照臺灣的位置，不受手機系統字型
/// 影響（有些機型的系統字型沒有繁中標點字形，冒號、逗號偏下）；其餘字照
/// [uiFont]（介面字型，ADR 0045），null 時照平台預設的字族。
///
/// 自己指定字樣、不從 `textTheme` 繼承的元件（提示訊息、標題列）也要合併
/// 這裡對應的那一格。
TextTheme _uiFonts(String? uiFont) {
  final platform = Typography.material2021(platform: defaultTargetPlatform)
      .black;
  TextStyle font(TextStyle? style) => TextStyle(
    fontFamily: AppTextStyles.punctuationFontFamily,
    fontFamilyFallback: [?(uiFont ?? style?.fontFamily)],
  );
  return TextTheme(
    displayLarge: font(platform.displayLarge),
    displayMedium: font(platform.displayMedium),
    displaySmall: font(platform.displaySmall),
    headlineLarge: font(platform.headlineLarge),
    headlineMedium: font(platform.headlineMedium),
    headlineSmall: font(platform.headlineSmall),
    titleLarge: font(platform.titleLarge),
    titleMedium: font(platform.titleMedium),
    titleSmall: font(platform.titleSmall),
    bodyLarge: font(platform.bodyLarge),
    bodyMedium: font(platform.bodyMedium),
    bodySmall: font(platform.bodySmall),
    labelLarge: font(platform.labelLarge),
    labelMedium: font(platform.labelMedium),
    labelSmall: font(platform.labelSmall),
  );
}

/// 底部面板裡的主題：深色時介面底色整組往上一階
/// （[StylePalette.raisedForSheet]），面板疊在頁面上才看得到邊；淺色不變。
///
/// [base] 已經是面板裡的主題，或是閱讀器面板這類自己分層的主題（分組底色
/// 不是風格的頁面底色）時原樣回傳，面板裡再開面板不會一路往上疊。風格配色
/// 的擴充（[StylePalette]）不換：閱讀正文與閱讀選單照它取色，不跟著面板變。
ThemeData sheetThemeOf(ThemeData base) {
  final palette = base.extension<StylePalette>();
  final chrome = base.extension<AppChrome>();
  if (base.brightness == Brightness.light ||
      palette == null ||
      chrome == null ||
      chrome.groupedBackground != palette.background) {
    return base;
  }
  final colors = palette.raisedForSheet();
  final scheme = base.colorScheme;
  return base.copyWith(
    colorScheme: scheme.copyWith(
      primaryContainer: Color.alphaBlend(
        colors.primary.withValues(alpha: 0.24),
        colors.surface,
      ),
      secondaryContainer: Color.alphaBlend(
        colors.secondary.withValues(alpha: 0.22),
        colors.surface,
      ),
      surface: colors.surface,
      onSurfaceVariant: colors.textMuted,
      outline: colors.border,
      outlineVariant: colors.border.withValues(alpha: 0.72),
    ),
    scaffoldBackgroundColor: colors.background,
    cardTheme: base.cardTheme.copyWith(color: colors.surface),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: colors.surface,
      modalBackgroundColor: colors.surface,
    ),
    dividerTheme: base.dividerTheme.copyWith(color: colors.border),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: colors.surface,
    ),
    extensions: [
      for (final extension in base.extensions.values)
        if (extension is! AppChrome) extension,
      AppChrome.derive(
        brightness: base.brightness,
        primary: scheme.primary,
        background: colors.background,
        surface: colors.surface,
        bar: colors.bar,
        textPrimary: colors.text,
        textSecondary: colors.textMuted,
        border: colors.border,
        inversePrimary: scheme.inversePrimary,
        glassStrength: chrome.glassStrength,
      ),
    ],
  );
}

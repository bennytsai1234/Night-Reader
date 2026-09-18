import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// 全域 App UI 的可自訂顏色。
///
/// 使用者只需要調整會直接影響畫面的語意色；其餘 Material 色階由
/// [AppTheme] 依這些顏色產生，避免把 ColorScheme 的內部欄位全部暴露到 UI。
class AppUiThemeColors {
  const AppUiThemeColors({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.appBar,
    required this.navigation,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
  });

  final Color primary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color appBar;
  final Color navigation;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;

  static const lightDefault = AppUiThemeColors(
    primary: AppPalette.cinnabar,
    secondary: AppPalette.gold,
    background: AppPalette.paper200,
    surface: AppPalette.paper50,
    appBar: AppPalette.paper100,
    navigation: AppPalette.paper100,
    textPrimary: AppPalette.ink700,
    textSecondary: AppPalette.ink300,
    border: AppPalette.paper400,
  );

  static const darkDefault = AppUiThemeColors(
    primary: AppPalette.cinnabarDark,
    secondary: AppPalette.gold,
    background: AppPalette.ink600,
    surface: AppPalette.ink500,
    appBar: AppPalette.ink500,
    navigation: AppPalette.ink500,
    textPrimary: AppPalette.ink50,
    textSecondary: AppPalette.ink200,
    border: AppPalette.ink400,
  );

  AppUiThemeColors copyWith({
    Color? primary,
    Color? secondary,
    Color? background,
    Color? surface,
    Color? appBar,
    Color? navigation,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
  }) {
    return AppUiThemeColors(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      appBar: appBar ?? this.appBar,
      navigation: navigation ?? this.navigation,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
    );
  }

  Map<String, dynamic> toJson() => {
    'primary': primary.toARGB32(),
    'secondary': secondary.toARGB32(),
    'background': background.toARGB32(),
    'surface': surface.toARGB32(),
    'appBar': appBar.toARGB32(),
    'navigation': navigation.toARGB32(),
    'textPrimary': textPrimary.toARGB32(),
    'textSecondary': textSecondary.toARGB32(),
    'border': border.toARGB32(),
  };

  factory AppUiThemeColors.fromJson(
    Map<String, dynamic> json, {
    required AppUiThemeColors fallback,
  }) {
    return AppUiThemeColors(
      primary: _readColor(json['primary'], fallback.primary),
      secondary: _readColor(json['secondary'], fallback.secondary),
      background: _readColor(json['background'], fallback.background),
      surface: _readColor(json['surface'], fallback.surface),
      appBar: _readColor(json['appBar'], fallback.appBar),
      navigation: _readColor(json['navigation'], fallback.navigation),
      textPrimary: _readColor(json['textPrimary'], fallback.textPrimary),
      textSecondary: _readColor(json['textSecondary'], fallback.textSecondary),
      border: _readColor(json['border'], fallback.border),
    );
  }
}

/// 閱讀正文／閱讀選單共用的可自訂顏色模型。
///
/// 兩者資料實例完全分開；共用型別只是避免兩份相同的序列化程式碼。
class ReaderAreaThemeColors {
  const ReaderAreaThemeColors({
    required this.background,
    required this.text,
    required this.secondaryText,
    required this.accent,
    required this.highlight,
    required this.border,
  });

  final Color background;
  final Color text;
  final Color secondaryText;
  final Color accent;
  final Color highlight;
  final Color border;

  static const contentLightDefault = ReaderAreaThemeColors(
    background: Color(0xFFFFFFFF),
    text: Color(0xFF1A1A1A),
    secondaryText: Color(0xFF5F5A4D),
    accent: AppPalette.cinnabar,
    highlight: Color(0xFFFFE0A6),
    border: Color(0xFFDCD2BD),
  );

  static const contentDarkDefault = ReaderAreaThemeColors(
    background: Color(0xFF000000),
    text: Color(0xFFD0CCC3),
    secondaryText: Color(0xFF8A8473),
    accent: AppPalette.cinnabarDark,
    highlight: Color(0xFF594729),
    border: Color(0xFF3D392F),
  );

  static const menuLightDefault = ReaderAreaThemeColors(
    background: AppPalette.paper50,
    text: AppPalette.ink700,
    secondaryText: AppPalette.ink300,
    accent: AppPalette.cinnabar,
    highlight: AppPalette.paper300,
    border: AppPalette.paper400,
  );

  static const menuDarkDefault = ReaderAreaThemeColors(
    background: AppPalette.ink500,
    text: AppPalette.ink50,
    secondaryText: AppPalette.ink200,
    accent: AppPalette.cinnabarDark,
    highlight: AppPalette.ink400,
    border: AppPalette.ink400,
  );

  ReaderAreaThemeColors copyWith({
    Color? background,
    Color? text,
    Color? secondaryText,
    Color? accent,
    Color? highlight,
    Color? border,
  }) {
    return ReaderAreaThemeColors(
      background: background ?? this.background,
      text: text ?? this.text,
      secondaryText: secondaryText ?? this.secondaryText,
      accent: accent ?? this.accent,
      highlight: highlight ?? this.highlight,
      border: border ?? this.border,
    );
  }

  Map<String, dynamic> toJson() => {
    'background': background.toARGB32(),
    'text': text.toARGB32(),
    'secondaryText': secondaryText.toARGB32(),
    'accent': accent.toARGB32(),
    'highlight': highlight.toARGB32(),
    'border': border.toARGB32(),
  };

  factory ReaderAreaThemeColors.fromJson(
    Map<String, dynamic> json, {
    required ReaderAreaThemeColors fallback,
  }) {
    return ReaderAreaThemeColors(
      background: _readColor(json['background'], fallback.background),
      text: _readColor(json['text'], fallback.text),
      secondaryText: _readColor(json['secondaryText'], fallback.secondaryText),
      accent: _readColor(json['accent'], fallback.accent),
      highlight: _readColor(json['highlight'], fallback.highlight),
      border: _readColor(json['border'], fallback.border),
    );
  }
}

Color _readColor(dynamic value, Color fallback) {
  if (value is int) return Color(value);
  if (value is String) {
    final normalized = value.trim();
    if (normalized.startsWith('#')) {
      final hex = normalized.substring(1);
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) {
        return Color(hex.length <= 6 ? (0xFF000000 | parsed) : parsed);
      }
    }
    if (normalized.startsWith('0x')) {
      final parsed = int.tryParse(normalized.substring(2), radix: 16);
      if (parsed != null) return Color(parsed);
    }
    final parsed = int.tryParse(normalized);
    if (parsed != null) return Color(parsed);
  }
  return fallback;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_tokens.dart';

// 高亮色以使用者設定的深淺（不透明度）疊在正文上，取鮮明的螢光筆色，
// 淺色與深色共用。
const _amber = Color(0xFFFFC857);
const _citron = Color(0xFFE8C547);
const _sky = Color(0xFF5AA9FF);
const _apricot = Color(0xFFF5A742);

/// 外觀風格：一套同時套到 App 介面、閱讀正文與閱讀選單的配色，
/// 各有淺色與深色；使用者只選風格、深淺與強調色（[AppAccent]），不個別調色。
enum AppStyle {
  paper(
    '紙墨',
    light: StylePalette(
      brightness: Brightness.light,
      background: AppPalette.paper200,
      surface: AppPalette.paper50,
      bar: AppPalette.paper100,
      text: AppPalette.ink700,
      textMuted: AppPalette.ink300,
      border: AppPalette.paper400,
      primary: AppPalette.cinnabar,
      secondary: AppPalette.gold,
      readerBackground: AppPalette.paper100,
      readerText: Color(0xFF2A241C),
      readerInfo: Color(0xFF6D675E),
      highlight: _amber,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: AppPalette.ink600,
      surface: AppPalette.ink500,
      bar: AppPalette.ink500,
      text: AppPalette.ink50,
      textMuted: Color(0xFF968F7D),
      border: AppPalette.ink400,
      primary: AppPalette.cinnabarDark,
      secondary: AppPalette.gold,
      readerBackground: Color(0xFF14110D),
      readerText: Color(0xFFCFC6B2),
      readerInfo: Color(0xFF938C7D),
      highlight: _amber,
    ),
  ),
  bamboo(
    '竹青',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFE8EEDF),
      surface: Color(0xFFF6F9F0),
      bar: Color(0xFFEFF4E7),
      text: Color(0xFF1C2619),
      textMuted: Color(0xFF5A6854),
      border: Color(0xFFC9D4BC),
      primary: Color(0xFF4A6B45),
      secondary: Color(0xFFA0844A),
      readerBackground: Color(0xFFE3EDCD),
      readerText: Color(0xFF2D4A32),
      readerInfo: Color(0xFF576F56),
      highlight: _citron,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF101713),
      surface: Color(0xFF1A231D),
      bar: Color(0xFF1A231D),
      text: Color(0xFFDCE8D6),
      textMuted: Color(0xFF82937D),
      border: Color(0xFF2C3A2F),
      primary: Color(0xFF8FB58A),
      secondary: AppPalette.teaDark,
      readerBackground: Color(0xFF0F1D19),
      readerText: Color(0xFFB9D7C2),
      readerInfo: Color(0xFF839B8C),
      highlight: _citron,
    ),
  ),
  azurite(
    '石青',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFEDF0F3),
      surface: Color(0xFFFAFBFC),
      bar: Color(0xFFF4F6F8),
      text: Color(0xFF121820),
      textMuted: Color(0xFF586372),
      border: Color(0xFFD2D8DF),
      primary: Color(0xFF3D5F80),
      secondary: Color(0xFFB07D3A),
      readerBackground: Color(0xFFF1F4F7),
      readerText: Color(0xFF1E2833),
      readerInfo: Color(0xFF626972),
      highlight: _sky,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF10151B),
      surface: Color(0xFF19202A),
      bar: Color(0xFF19202A),
      text: Color(0xFFE2E8EF),
      textMuted: Color(0xFF8592A2),
      border: Color(0xFF2A3340),
      primary: AppPalette.azuriteDark,
      secondary: AppPalette.teaDark,
      readerBackground: Color(0xFF0D1217),
      readerText: Color(0xFFB6C3CF),
      readerInfo: Color(0xFF808A94),
      highlight: _sky,
    ),
  ),
  tea(
    '茶褐',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFE9DEC7),
      surface: Color(0xFFF6EEDD),
      bar: Color(0xFFF0E7D2),
      text: Color(0xFF2C2014),
      textMuted: Color(0xFF6B5840),
      border: Color(0xFFD2C2A2),
      primary: Color(0xFF7E5124),
      secondary: AppPalette.gold,
      readerBackground: Color(0xFFDFD0B0),
      readerText: Color(0xFF3E2A1E),
      readerInfo: Color(0xFF695745),
      highlight: _apricot,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF1B140D),
      surface: Color(0xFF292016),
      bar: Color(0xFF292016),
      text: Color(0xFFEDDFC5),
      textMuted: Color(0xFF9F8D6F),
      border: Color(0xFF3E3122),
      primary: Color(0xFFD9A66B),
      secondary: AppPalette.teaDark,
      readerBackground: Color(0xFF18120B),
      readerText: Color(0xFFCDB892),
      readerInfo: Color(0xFF938367),
      highlight: _apricot,
    ),
  ),
  plain(
    '素色',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFF2F2F2),
      surface: Color(0xFFFFFFFF),
      bar: Color(0xFFF8F8F8),
      text: Color(0xFF111111),
      textMuted: Color(0xFF6B6B6B),
      border: Color(0xFFDADADA),
      primary: Color(0xFF333333),
      secondary: Color(0xFF8E8E93),
      readerBackground: Color(0xFFFFFFFF),
      readerText: Color(0xFF1A1A1A),
      readerInfo: Color(0xFF636363),
      highlight: _amber,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF000000),
      surface: Color(0xFF151515),
      bar: Color(0xFF151515),
      text: Color(0xFFEDEDED),
      textMuted: Color(0xFF8A8A8A),
      border: Color(0xFF2A2A2A),
      primary: Color(0xFFD6D6D6),
      secondary: Color(0xFF8E8E93),
      readerBackground: Color(0xFF000000),
      readerText: Color(0xFFA3A3A3),
      readerInfo: Color(0xFF757575),
      highlight: _amber,
    ),
  ),
  // 以下五種取材自常見的編輯器與閱讀配色，明暗略有調整，
  // 色相與原作相同、明度不完全一樣。

  /// Rosé Pine（Dawn／Main）。
  rouge(
    '胭脂',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFF7EFE8),
      surface: Color(0xFFFFFAF3),
      bar: Color(0xFFFBF4ED),
      text: Color(0xFF3E3A5E),
      textMuted: Color(0xFF6E6A86),
      border: Color(0xFFE6D9CE),
      primary: Color(0xFFA9516A),
      secondary: Color(0xFFD7827E),
      readerBackground: Color(0xFFFAF4ED),
      readerText: Color(0xFF4A4570),
      readerInfo: Color(0xFF706C8A),
      highlight: Color(0xFFF6C177),
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF191724),
      surface: Color(0xFF1F1D2E),
      bar: Color(0xFF1F1D2E),
      text: Color(0xFFE0DEF4),
      textMuted: Color(0xFF908CAA),
      border: Color(0xFF2E2B44),
      primary: Color(0xFFF2A0B7),
      secondary: Color(0xFFEBBCBA),
      readerBackground: Color(0xFF171521),
      readerText: Color(0xFFD3D0E8),
      readerInfo: Color(0xFF908CAA),
      highlight: Color(0xFFF6C177),
    ),
  ),

  /// Catppuccin（Latte／Mocha）。
  lotus(
    '藕荷',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFE6E9EF),
      surface: Color(0xFFEFF1F5),
      bar: Color(0xFFECEEF3),
      text: Color(0xFF3A3D55),
      textMuted: Color(0xFF5C5F77),
      border: Color(0xFFCCD0DA),
      primary: Color(0xFF8534EF),
      secondary: Color(0xFF7287FD),
      readerBackground: Color(0xFFEFF1F5),
      readerText: Color(0xFF3A3D55),
      readerInfo: Color(0xFF5C5F77),
      highlight: Color(0xFFDF8E1D),
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF181825),
      surface: Color(0xFF1E1E2E),
      bar: Color(0xFF1E1E2E),
      text: Color(0xFFCDD6F4),
      textMuted: Color(0xFFA6ADC8),
      border: Color(0xFF313244),
      primary: Color(0xFFCCA8F7),
      secondary: Color(0xFFB4BEFE),
      readerBackground: Color(0xFF161622),
      readerText: Color(0xFFBAC2DE),
      readerInfo: Color(0xFF9399B2),
      highlight: Color(0xFFF9E2AF),
    ),
  ),

  /// Solarized。
  scroll(
    '黃卷',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFEEE8D5),
      surface: Color(0xFFFDF6E3),
      bar: Color(0xFFF6F0DC),
      text: Color(0xFF073642),
      textMuted: Color(0xFF566B72),
      border: Color(0xFFDDD6C1),
      primary: Color(0xFF1B6C66),
      secondary: Color(0xFFB58900),
      readerBackground: Color(0xFFFDF6E3),
      readerText: Color(0xFF073642),
      readerInfo: Color(0xFF5F747C),
      highlight: Color(0xFFB58900),
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF00212B),
      surface: Color(0xFF002B36),
      bar: Color(0xFF002B36),
      text: Color(0xFFEEE8D5),
      textMuted: Color(0xFF93A1A1),
      border: Color(0xFF0B4250),
      primary: Color(0xFF30B7AD),
      secondary: Color(0xFFB58900),
      readerBackground: Color(0xFF002B36),
      readerText: Color(0xFFD2CDBA),
      readerInfo: Color(0xFF839496),
      highlight: Color(0xFFB58900),
    ),
  ),

  /// Gruvbox。
  amber(
    '琥珀',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFF2E5BC),
      surface: Color(0xFFFBF1C7),
      bar: Color(0xFFF7EBC1),
      text: Color(0xFF3C3836),
      textMuted: Color(0xFF665C54),
      border: Color(0xFFD5C4A1),
      primary: Color(0xFFAF3A03),
      secondary: Color(0xFF79740E),
      readerBackground: Color(0xFFFBF1C7),
      readerText: Color(0xFF3C3836),
      readerInfo: Color(0xFF786B61),
      highlight: Color(0xFFFABD2F),
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF1D2021),
      surface: Color(0xFF282828),
      bar: Color(0xFF282828),
      text: Color(0xFFEBDBB2),
      textMuted: Color(0xFFA89984),
      border: Color(0xFF3C3836),
      primary: Color(0xFFFE953F),
      secondary: Color(0xFFB8BB26),
      readerBackground: Color(0xFF1D2021),
      readerText: Color(0xFFD5C4A1),
      readerInfo: Color(0xFFA89984),
      highlight: Color(0xFFFABD2F),
    ),
  ),

  /// Nord。
  frost(
    '霜夜',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFE5E9F0),
      surface: Color(0xFFECEFF4),
      bar: Color(0xFFE9ECF2),
      text: Color(0xFF2E3440),
      textMuted: Color(0xFF4C566A),
      border: Color(0xFFD8DEE9),
      primary: Color(0xFF4A6990),
      secondary: Color(0xFFBF616A),
      readerBackground: Color(0xFFECEFF4),
      readerText: Color(0xFF2E3440),
      readerInfo: Color(0xFF4C566A),
      highlight: Color(0xFFEBCB8B),
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF2E3440),
      surface: Color(0xFF3B4252),
      bar: Color(0xFF3B4252),
      text: Color(0xFFECEFF4),
      textMuted: Color(0xFFD8DEE9),
      border: Color(0xFF434C5E),
      primary: Color(0xFF88C0D0),
      secondary: Color(0xFFB48EAD),
      readerBackground: Color(0xFF2E3440),
      readerText: Color(0xFFD8DEE9),
      readerInfo: Color(0xFFA3ABBA),
      highlight: Color(0xFFEBCB8B),
    ),
  );

  const AppStyle(this.label, {required this.light, required this.dark});

  final String label;
  final StylePalette light;
  final StylePalette dark;

  StylePalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 套上強調色後的配色：主色換成強調色在這個深淺的顏色，其餘照風格；
  /// [AppAccent.theme] 就是 [of]。
  StylePalette paletteFor(Brightness brightness, AppAccent accent) {
    final palette = of(brightness);
    final color = accent.colorFor(brightness);
    return color == null ? palette : palette.copyWith(primary: color);
  }

  static AppStyle fromStorage(String? value) => AppStyle.values.firstWhere(
    (style) => style.name == value,
    orElse: () => AppStyle.paper,
  );
}

/// 強調色：開關、選取、勾勾、強調按鈕與純文字動作用的主色。預設跟隨風格；
/// 其他顏色各有一個淺色、一個深色版本，不分風格。
enum AppAccent {
  theme('跟隨主題'),
  cinnabar('朱紅', light: Color(0xFFA8322B), dark: Color(0xFFE8806F)),
  rouge('胭脂', light: Color(0xFFB4446C), dark: Color(0xFFF08FB0)),
  amber('琥珀', light: Color(0xFFB5530F), dark: Color(0xFFF59A4A)),
  tea('茶金', light: Color(0xFF8F6A1E), dark: Color(0xFFD9B061)),
  yellow('黃', light: Color(0xFF8A6D00), dark: Color(0xFFE8C547)),
  bamboo('竹綠', light: Color(0xFF3F7A34), dark: Color(0xFF8CC47E)),
  teal('青綠', light: Color(0xFF12796F), dark: Color(0xFF5CC6B8)),
  sky('天藍', light: Color(0xFF1F78B4), dark: Color(0xFF7CC3F0)),
  azurite('石青', light: Color(0xFF2F5F99), dark: Color(0xFF8AB4E8)),
  lotus('藕荷', light: Color(0xFF7446B8), dark: Color(0xFFBFA0F0)),
  gray('灰', light: Color(0xFF666666), dark: Color(0xFFA6A6A6)),
  ink('墨', light: Color(0xFF222222), dark: Color(0xFFE6E6E6));

  const AppAccent(this.label, {this.light, this.dark});

  final String label;
  final Color? light;
  final Color? dark;

  /// 這個深淺用的顏色；[theme] 沒有自己的顏色。
  Color? colorFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static AppAccent fromStorage(String? value) => AppAccent.values.firstWhere(
    (accent) => accent.name == value,
    orElse: () => AppAccent.theme,
  );
}

/// 一個風格在某個深淺下的完整配色。
///
/// 以 [ThemeExtension] 掛在 App 主題上：閱讀器與選單一律經 [StylePalette.of]
/// 取色，因此和 App 介面永遠是同一個風格、同一個深淺。
@immutable
class StylePalette extends ThemeExtension<StylePalette> {
  const StylePalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.bar,
    required this.text,
    required this.textMuted,
    required this.border,
    required this.primary,
    required this.secondary,
    required this.readerBackground,
    required this.readerText,
    required this.readerInfo,
    required this.highlight,
  });

  final Brightness brightness;

  /// App 頁面底色。
  final Color background;

  /// 卡片、面板與閱讀選單底色。
  final Color surface;

  /// 頁首、浮動分頁列等玻璃列的色調。
  final Color bar;
  final Color text;
  final Color textMuted;
  final Color border;

  /// 主色：選取狀態、開關、強調按鈕。
  final Color primary;

  /// 點綴色。
  final Color secondary;

  /// 閱讀正文的紙張與文字。
  final Color readerBackground;
  final Color readerText;

  /// 閱讀器頁首／頁尾資訊列的文字與圖示。
  final Color readerInfo;

  /// 朗讀高亮與選字反白選「跟隨主題」時的顏色（實際以設定的深淺疊上）。
  final Color highlight;

  /// 疊在主色上的勾勾與文字：紙白、墨色中對主色對比較高的一個。
  Color get onPrimary =>
      _contrast(AppPalette.paper50, primary) >=
          _contrast(AppPalette.ink700, primary)
      ? AppPalette.paper50
      : AppPalette.ink700;

  /// 目前主題的配色；主題沒有掛擴充時以預設風格補上。
  static StylePalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<StylePalette>() ??
        AppStyle.paper.of(theme.brightness);
  }

  @override
  StylePalette copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? bar,
    Color? text,
    Color? textMuted,
    Color? border,
    Color? primary,
    Color? secondary,
    Color? readerBackground,
    Color? readerText,
    Color? readerInfo,
    Color? highlight,
  }) {
    return StylePalette(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      bar: bar ?? this.bar,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      readerBackground: readerBackground ?? this.readerBackground,
      readerText: readerText ?? this.readerText,
      readerInfo: readerInfo ?? this.readerInfo,
      highlight: highlight ?? this.highlight,
    );
  }

  /// 換風格或深淺時不做漸變，在動畫中點一次切換：正文段落快取以文字色
  /// 為鍵，逐幀漸變會讓每一幀都重排正文。
  @override
  StylePalette lerp(ThemeExtension<StylePalette>? other, double t) {
    if (other is! StylePalette) return this;
    return t < 0.5 ? this : other;
  }
}

/// WCAG 2.x 對比度。
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

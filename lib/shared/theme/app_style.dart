import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_layers.dart';
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
      background: Color(0xFFDDD9D1),
      surface: AppPalette.paper50,
      bar: AppPalette.paper50,
      text: AppPalette.ink700,
      textMuted: AppPalette.ink300,
      border: AppPalette.paper400,
      primary: AppPalette.cinnabar,
      secondary: AppPalette.gold,
      readerBackground: AppPalette.paper100,
      readerMenu: Color(0xFFD8D3C8),
      readerText: Color(0xFF2A241C),
      readerInfo: Color(0xFF6D675E),
      highlight: _amber,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: AppPalette.ink600,
      surface: Color(0xFF3A352F),
      bar: Color(0xFF47433B),
      text: AppPalette.ink50,
      textMuted: Color(0xFFA19A87),
      border: Color(0xFF464239),
      primary: AppPalette.cinnabarDark,
      secondary: AppPalette.gold,
      readerBackground: Color(0xFF14110D),
      readerMenu: Color(0xFF34302A),
      readerText: Color(0xFFCFC6B2),
      readerInfo: Color(0xFF938C7D),
      highlight: _amber,
    ),
  ),
  bamboo(
    '竹青',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFD3D7CE),
      surface: Color(0xFFF6F9F0),
      bar: Color(0xFFF6F9F0),
      text: Color(0xFF1C2619),
      textMuted: Color(0xFF5A6854),
      border: Color(0xFFC9D4BC),
      primary: Color(0xFF4A6B45),
      secondary: Color(0xFFA0844A),
      readerBackground: Color(0xFFE4ECD6),
      readerMenu: Color(0xFFC1CAB6),
      readerText: Color(0xFF202D21),
      readerInfo: Color(0xFF56664F),
      highlight: _citron,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF101713),
      surface: Color(0xFF2F3730),
      bar: Color(0xFF3C443D),
      text: Color(0xFFDCE8D6),
      textMuted: Color(0xFF94A48E),
      border: Color(0xFF404741),
      primary: Color(0xFF8FB58A),
      secondary: AppPalette.teaDark,
      readerBackground: Color(0xFF0F1D19),
      readerMenu: Color(0xFF2D3E37),
      readerText: Color(0xFFB9D7C2),
      readerInfo: Color(0xFF839B8C),
      highlight: _citron,
    ),
  ),
  azurite(
    '石青',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFD7D9DB),
      surface: Color(0xFFFAFBFC),
      bar: Color(0xFFFAFBFC),
      text: Color(0xFF121820),
      textMuted: Color(0xFF586372),
      border: Color(0xFFD2D8DF),
      primary: Color(0xFF3D5F80),
      secondary: Color(0xFFB07D3A),
      readerBackground: Color(0xFFF1F4F7),
      readerMenu: Color(0xFFCED2D6),
      readerText: Color(0xFF1E2833),
      readerInfo: Color(0xFF626972),
      highlight: _sky,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF10151B),
      surface: Color(0xFF2F343A),
      bar: Color(0xFF3C4248),
      text: Color(0xFFE2E8EF),
      textMuted: Color(0xFF98A4B2),
      border: Color(0xFF3C4248),
      primary: AppPalette.azuriteDark,
      secondary: AppPalette.teaDark,
      readerBackground: Color(0xFF0D1217),
      readerMenu: Color(0xFF2B3238),
      readerText: Color(0xFFB6C3CF),
      readerInfo: Color(0xFF808A94),
      highlight: _sky,
    ),
  ),
  tea(
    '茶褐',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFD5CCBC),
      surface: Color(0xFFF6EEDD),
      bar: Color(0xFFF6EEDD),
      text: Color(0xFF2C2014),
      textMuted: Color(0xFF6B5840),
      border: Color(0xFFD2C2A2),
      primary: Color(0xFF7E5124),
      secondary: AppPalette.gold,
      readerBackground: Color(0xFFF0E4CA),
      readerMenu: Color(0xFFCFC2AB),
      readerText: Color(0xFF33241A),
      readerInfo: Color(0xFF6A5945),
      highlight: _apricot,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF1B140D),
      surface: Color(0xFF3B3329),
      bar: Color(0xFF494135),
      text: Color(0xFFEDDFC5),
      textMuted: Color(0xFFAE9D7F),
      border: Color(0xFF474034),
      primary: Color(0xFFD9A66B),
      secondary: AppPalette.teaDark,
      readerBackground: Color(0xFF18120B),
      readerMenu: Color(0xFF3A3124),
      readerText: Color(0xFFCDB892),
      readerInfo: Color(0xFF938367),
      highlight: _apricot,
    ),
  ),
  plain(
    '素色',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFDDDDDD),
      surface: Color(0xFFFFFFFF),
      bar: Color(0xFFFFFFFF),
      text: Color(0xFF111111),
      textMuted: Color(0xFF6B6B6B),
      border: Color(0xFFDADADA),
      primary: Color(0xFF333333),
      secondary: Color(0xFF8E8E93),
      readerBackground: Color(0xFFFFFFFF),
      readerMenu: Color(0xFFDDDDDD),
      readerText: Color(0xFF1A1A1A),
      readerInfo: Color(0xFF636363),
      highlight: _amber,
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF000000),
      surface: Color(0xFF262626),
      bar: Color(0xFF323232),
      text: Color(0xFFEDEDED),
      textMuted: Color(0xFF999999),
      border: Color(0xFF363636),
      primary: Color(0xFFD6D6D6),
      secondary: Color(0xFF8E8E93),
      readerBackground: Color(0xFF000000),
      readerMenu: Color(0xFF262626),
      readerText: Color(0xFFC4C4C4),
      readerInfo: Color(0xFF808080),
      highlight: _amber,
    ),
  ),
  // 以下五種取材自常見的編輯器與閱讀配色，明暗略有調整，
  // 色相與原作相同、明度不完全一樣。頁面、卡片、玻璃列與閱讀選單的底色
  // 照 [AppLayers] 從原作的卡片（淺色）與頁面（深色）算出。

  /// Rosé Pine（Dawn／Main）。
  rouge(
    '胭脂',
    light: StylePalette(
      brightness: Brightness.light,
      background: Color(0xFFDCD7D8),
      surface: Color(0xFFFFFAF3),
      bar: Color(0xFFFFFAF3),
      text: Color(0xFF3E3A5E),
      textMuted: Color(0xFF6E6A86),
      border: Color(0xFFE6D9CE),
      primary: Color(0xFFA9516A),
      secondary: Color(0xFFD7827E),
      readerBackground: Color(0xFFFAF4ED),
      readerMenu: Color(0xFFD7D1D4),
      readerText: Color(0xFF4A4570),
      readerInfo: Color(0xFF706C8A),
      highlight: Color(0xFFF6C177),
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF191724),
      surface: Color(0xFF383645),
      bar: Color(0xFF464453),
      text: Color(0xFFE0DEF4),
      textMuted: Color(0xFFA7A4BF),
      border: Color(0xFF3A3750),
      primary: Color(0xFFF2A0B7),
      secondary: Color(0xFFEBBCBA),
      readerBackground: Color(0xFF171521),
      readerMenu: Color(0xFF363442),
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
      background: Color(0xFFCDCFD7),
      surface: Color(0xFFEFF1F5),
      bar: Color(0xFFEFF1F5),
      text: Color(0xFF3A3D55),
      textMuted: Color(0xFF5C5F77),
      border: Color(0xFFCCD0DA),
      primary: Color(0xFF8534EF),
      secondary: Color(0xFF7287FD),
      readerBackground: Color(0xFFEFF1F5),
      readerMenu: Color(0xFFCDCFD7),
      readerText: Color(0xFF3A3D55),
      readerInfo: Color(0xFF5C5F77),
      highlight: Color(0xFFDF8E1D),
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF181825),
      surface: Color(0xFF363848),
      bar: Color(0xFF434556),
      text: Color(0xFFCDD6F4),
      textMuted: Color(0xFFBDC5E2),
      border: Color(0xFF444659),
      primary: Color(0xFFCCA8F7),
      secondary: Color(0xFFB4BEFE),
      readerBackground: Color(0xFF161622),
      readerMenu: Color(0xFF343544),
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
      background: Color(0xFFD3D6C8),
      surface: Color(0xFFFDF6E3),
      bar: Color(0xFFFDF6E3),
      text: Color(0xFF073642),
      textMuted: Color(0xFF566B72),
      border: Color(0xFFDDD6C1),
      primary: Color(0xFF1B6C66),
      secondary: Color(0xFFB58900),
      readerBackground: Color(0xFFFDF6E3),
      readerMenu: Color(0xFFD3D6C8),
      readerText: Color(0xFF073642),
      readerInfo: Color(0xFF5F747C),
      highlight: Color(0xFFB58900),
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF00212B),
      surface: Color(0xFF274247),
      bar: Color(0xFF374F53),
      text: Color(0xFFEEE8D5),
      textMuted: Color(0xFFACB5AF),
      border: Color(0xFF24545E),
      primary: Color(0xFF30B7AD),
      secondary: Color(0xFFB58900),
      readerBackground: Color(0xFF002B36),
      readerMenu: Color(0xFF2C4D52),
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
      background: Color(0xFFD8CFAC),
      surface: Color(0xFFFBF1C7),
      bar: Color(0xFFFBF1C7),
      text: Color(0xFF3C3836),
      textMuted: Color(0xFF665C54),
      border: Color(0xFFD5C4A1),
      primary: Color(0xFFAF3A03),
      secondary: Color(0xFF79740E),
      readerBackground: Color(0xFFFBF1C7),
      readerMenu: Color(0xFFD8CFAC),
      readerText: Color(0xFF3C3836),
      readerInfo: Color(0xFF786B61),
      highlight: Color(0xFFFABD2F),
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF1D2021),
      surface: Color(0xFF40403A),
      bar: Color(0xFF4F4E45),
      text: Color(0xFFEBDBB2),
      textMuted: Color(0xFFBEAE93),
      border: Color(0xFF4F4943),
      primary: Color(0xFFFE953F),
      secondary: Color(0xFFB8BB26),
      readerBackground: Color(0xFF1D2021),
      readerMenu: Color(0xFF41403A),
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
      background: Color(0xFFCACDD3),
      surface: Color(0xFFECEFF4),
      bar: Color(0xFFECEFF4),
      text: Color(0xFF2E3440),
      textMuted: Color(0xFF4C566A),
      border: Color(0xFFD8DEE9),
      primary: Color(0xFF4A6990),
      secondary: Color(0xFFBF616A),
      readerBackground: Color(0xFFECEFF4),
      readerMenu: Color(0xFFCACDD3),
      readerText: Color(0xFF2E3440),
      readerInfo: Color(0xFF4C566A),
      highlight: Color(0xFFEBCB8B),
    ),
    dark: StylePalette(
      brightness: Brightness.dark,
      background: Color(0xFF2E3440),
      surface: Color(0xFF515661),
      bar: Color(0xFF60656F),
      text: Color(0xFFECEFF4),
      // 照規則移的話會和正文字色只差一階、分不出主次，留原作的次要字色。
      textMuted: Color(0xFFD8DEE9),
      border: Color(0xFF4A5364),
      primary: Color(0xFF88C0D0),
      secondary: Color(0xFFB48EAD),
      readerBackground: Color(0xFF2E3440),
      readerMenu: Color(0xFF505662),
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
    required this.readerMenu,
    required this.readerText,
    required this.readerInfo,
    required this.highlight,
  });

  final Brightness brightness;

  /// App 頁面底色、卡片與面板底色、頁首與浮動分頁列等玻璃列的色調，照
  /// [AppLayers] 的分層規則算好：淺色頁面比卡片暗、玻璃與卡片同色；深色
  /// 卡片比頁面亮、玻璃再亮一階。
  final Color background;
  final Color surface;
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

  /// 閱讀選單與閱讀器內面板的底色：閱讀底色往閱讀文字色移（[AppLayers]），
  /// 淺色、深色都和紙分得開。
  final Color readerMenu;

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
    Color? readerMenu,
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
      readerMenu: readerMenu ?? this.readerMenu,
      readerText: readerText ?? this.readerText,
      readerInfo: readerInfo ?? this.readerInfo,
      highlight: highlight ?? this.highlight,
    );
  }

  // 強調色會讓 [AppStyle.paletteFor] 每次 copyWith 出新物件；照值比較才能
  // 讓相同設定產生相等的 ThemeData，避免全 App 跟著重建（ADR 0029）。
  @override
  bool operator ==(Object other) =>
      other is StylePalette &&
      other.brightness == brightness &&
      other.background == background &&
      other.surface == surface &&
      other.bar == bar &&
      other.text == text &&
      other.textMuted == textMuted &&
      other.border == border &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.readerBackground == readerBackground &&
      other.readerMenu == readerMenu &&
      other.readerText == readerText &&
      other.readerInfo == readerInfo &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(
    brightness,
    background,
    surface,
    bar,
    text,
    textMuted,
    border,
    primary,
    secondary,
    readerBackground,
    readerMenu,
    readerText,
    readerInfo,
    highlight,
  );

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

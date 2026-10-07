import 'dart:ui';

const List<FontFeature> kReaderV2CjkFontFeatures = <FontFeature>[
  FontFeature.enable('fwid'),
];

/// 正文與資訊列的文字語系。
///
/// Android 的 Noto Sans CJK 是一個字型集合，同一個碼位依語系選用
/// 簡中／繁中／日文字形；未指定語系時回退鏈取第一個（簡中）字形，
/// 「，。：；！？」因此擠在字格左下角、「」緊貼一側。指定繁中（臺灣）
/// 後使用置中的全形標點與置中的上下引號，符合臺灣出版排版慣例。
const Locale kReaderV2TextLocale = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hant',
  countryCode: 'TW',
);

// lastline-v1 為已移除的末行字距補償所留；保留字串以免無謂地讓既有
// metrics 快取失效。
// physicalwidth-v1：contentWidth 只代表 viewport 扣除使用者 padding 後的
// 實體可畫寬度，cell metric 不再裁切正文寬度。
// centered-text-frame-v1：typography 在 physical content frame 內建立置中的
// drawable text frame；visual-line planning、Paragraph 與 paint 共用同一幾何。
// readerbreak-v1：visual-line boundary 由 Night Reader 自己依 grapheme 的
// 真實 shaping advance 決定；SkParagraph 不再擁有 soft-wrap policy。
// systemfont-v1：使用平台字型 fallback；字形幾何可能改變，舊 metrics
// 不可沿用。
// locale-zh-hant-tw-v1：正文以繁中（臺灣）語系選字形，標點字形改變，
// 舊 metrics 不可沿用。
// chapter-gap-v1：章末 block 高度含固定的章末空行，舊的章末高度不可沿用。
// chapter-gap-v2：章末留白改為使用者設定的章節間距，不再疊加在段距之上。
const String kReaderV2CjkTypographyFeatureSignature =
    'fwid+lastline-v1+physicalwidth-v1+centered-text-frame-v1+readerbreak-v1+systemfont-v1+locale-zh-hant-tw-v1+chapter-gap-v2';

/// 未設定標題字號時，章節標題比正文大的字號（舊版固定規則）。
const double kReaderV2DefaultTitleSizeDelta = 4.0;

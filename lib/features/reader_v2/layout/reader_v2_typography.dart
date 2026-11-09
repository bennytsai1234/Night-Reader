import 'dart:ui';

const List<FontFeature> kReaderV2CjkFontFeatures = <FontFeature>[
  FontFeature.enable('fwid'),
];

/// 正文與資訊列的文字語系。
///
/// Android 的 Noto Sans CJK 是一個字型集合，同一個碼位依語系選用
/// 簡中／繁中／日文字形；指定繁中（臺灣）讓漢字回退到繁中字形。
/// 標點不靠語系：部分機型的系統字型不提供繁中字形，見
/// [kReaderV2PunctFontFamily]。
const Locale kReaderV2TextLocale = Locale.fromSubtags(
  languageCode: 'zh',
  scriptCode: 'Hant',
  countryCode: 'TW',
);

/// 正文與資訊列的標點字型（`assets/fonts/NightReaderPunct-*.ttf`，由同目錄
/// `generate_punct_font.py` 從 Noto Sans CJK TC 產生）。
///
/// 只收「，。、；：！？」的繁中置中字形、改為教育部位置的「」『』
/// （直筆外緣貼字格中線，各佔四分之一格），以及置中的刪節號「…」與拉滿
/// 整格的破折號「—」（系統回退會落到 Roboto 的西文窄字形）。放在字型清單首位，標點不受
/// 手機系統字型的語系與廠商設定影響；其餘字元交給
/// [kReaderV2FontFamilyFallback] 與平台回退，與未指定字型時相同。
const String kReaderV2PunctFontFamily = 'NightReaderPunct';

/// 未指定字型時引擎使用的平台預設字族；接在標點字型之後，讓拉丁字母與
/// 數字維持原本的系統字型。
const List<String> kReaderV2FontFamilyFallback = <String>['sans-serif'];

/// 標點字型之後的字族清單：選了下載的字型（[family]，ADR 0045）時排在
/// 平台預設（Android 的 `sans-serif` 只有 Roboto，沒有漢字）後面，英數字照舊
/// 用系統字型、照 ADR 0007 補半格，漢字才落到下載的字型；思源宋體自己的英數字
/// 吃了 `fwid` 會變成全形。那套字型沒有的字（例如子集外的罕見字）照樣交給平台。
List<String> readerV2FontFallback(String? family) => family == null
    ? kReaderV2FontFamilyFallback
    : <String>[...kReaderV2FontFamilyFallback, family];

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
// twpunct-v1：標點改由 NightReaderPunct 繪製，字形與 run 切分改變，
// 舊 metrics 不可沿用。
// twpunct-v2：刪節號與破折號也改由 NightReaderPunct 繪製，各佔一格。
// halfcell-v1：英數字段補到半格、emoji 縮到一格、行高由 strut 固定。
// kinsoku-v2：換行做避頭尾，英數字段只拉最後一個單字；被拉字的行把空隙
// 攤進字距，每個字距最多 1/4 格。
const String kReaderV2CjkTypographyFeatureSignature =
    'fwid+lastline-v1+physicalwidth-v1+centered-text-frame-v1+readerbreak-v1+systemfont-v1+locale-zh-hant-tw-v1+chapter-gap-v2+twpunct-v2+halfcell-v1+kinsoku-v2';

/// 未設定標題字號時，章節標題比正文大的字號（舊版固定規則）。
const double kReaderV2DefaultTitleSizeDelta = 4.0;

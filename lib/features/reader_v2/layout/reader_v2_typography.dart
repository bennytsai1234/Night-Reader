import 'dart:ui';

const List<FontFeature> kReaderV2CjkFontFeatures = <FontFeature>[
  FontFeature.enable('fwid'),
];

// 末行補償演算法版本也要進入 metrics fingerprint，避免沿用舊 Paragraph
// 幾何；開關本身則由 StyleFingerprint.lastLineSpacingCompensation 區分。
// physicalwidth-v1：contentWidth 只代表 viewport 扣除使用者 padding 後的
// 實體可畫寬度，cell metric 不再裁切正文寬度。
// centered-text-frame-v1：typography 在 physical content frame 內建立置中的
// drawable text frame；visual-line planning、Paragraph 與 paint 共用同一幾何。
// readerbreak-v1：visual-line boundary 由 Night Reader 自己依 grapheme 的
// 真實 shaping advance 決定；SkParagraph 不再擁有 soft-wrap policy。
// systemfont-v1：使用平台字型 fallback；字形幾何可能改變，舊 metrics
// 不可沿用。
const String kReaderV2CjkTypographyFeatureSignature =
    'fwid+lastline-v1+physicalwidth-v1+centered-text-frame-v1+readerbreak-v1+systemfont-v1';

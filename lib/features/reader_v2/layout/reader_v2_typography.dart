import 'dart:ui';

const List<FontFeature> kReaderV2CjkFontFeatures = <FontFeature>[
  FontFeature.enable('fwid'),
];

/// 歧義寬度標點的全形保證字型（`assets/fonts/NightReaderPunct.ttf`，
/// 由 `tool/punct_font/generate.py` 從 Noto Sans TC 子集產生）。
///
/// 只含 U+2014/U+2015/U+2025/U+2026/U+22EF 五個碼位的滿版全形字形，
/// 放在排版 TextStyle fontFamily 首位：這些碼位不再落到 Roboto 的西文
/// 窄字形，「——」「……」必佔滿格；其餘字元本字型無字形，回退鏈行為
/// 與原本完全相同。
const String kReaderV2PunctFontFamily = 'NightReaderPunct';

// 末行補償演算法版本也要進入 metrics fingerprint，避免沿用舊 Paragraph
// 幾何；開關本身則由 StyleFingerprint.lastLineSpacingCompensation 區分。
// punct-v1：引入 NightReaderPunct 標點字型（2026-07-18），字形寬度變更，
// 舊 metrics 不可沿用。
// emgrid-v1：em 網格鎖寬（2026-07-19）——contentWidth 修剪至實測 cell
// 整數倍、內文 justify 改 start、縮排 placeholder 寬改 cell；幾何整批
// 變更，舊 metrics 不可沿用（contentWidth/justify 本在 fingerprint 內，
// 此處雙保險）。
const String kReaderV2CjkTypographyFeatureSignature =
    'fwid+lastline-v1+punct-v1+emgrid-v1';

import 'dart:ui';

const List<FontFeature> kReaderV2CjkFontFeatures = <FontFeature>[
  FontFeature.enable('fwid'),
];

// 末行補償演算法版本也要進入 metrics fingerprint，避免沿用舊 Paragraph
// 幾何；開關本身則由 StyleFingerprint.lastLineSpacingCompensation 區分。
// emgrid-v1：em 網格鎖寬（2026-07-19）——contentWidth 修剪至實測 cell
// 整數倍、內文 justify 改 start、縮排 placeholder 寬改 cell；幾何整批
// 變更，舊 metrics 不可沿用（contentWidth/justify 本在 fingerprint 內，
// 此處雙保險）。
// systemfont-v1：移除標點子集字型（2026-07-29），改回平台字型 fallback；
// 字形幾何可能改變，舊 metrics 不可沿用。
const String kReaderV2CjkTypographyFeatureSignature =
    'fwid+lastline-v1+emgrid-v1+systemfont-v1';

import 'dart:ui';

const List<FontFeature> kReaderV2CjkFontFeatures = <FontFeature>[
  FontFeature.enable('fwid'),
];

// 末行補償演算法版本也要進入 metrics fingerprint，避免沿用舊 Paragraph
// 幾何；開關本身則由 StyleFingerprint.lastLineSpacingCompensation 區分。
const String kReaderV2CjkTypographyFeatureSignature = 'fwid+lastline-v1';

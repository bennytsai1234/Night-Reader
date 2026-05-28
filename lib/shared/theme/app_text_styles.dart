import 'package:flutter/material.dart';

/// Typography scale tokens — 夜讀 (Yè Dú)
class AppTextStyles {
  AppTextStyles._();

  // Font family name constants — kept for call-site reference.
  // Fonts are not bundled; Flutter silently falls back to the system default.
  static const String fontFamilySerif = 'Noto Serif TC';
  static const String fontFamilySans = 'Noto Sans TC';

  static const TextStyle display = TextStyle(
    fontSize: 88,
    fontWeight: FontWeight.bold,
  );
  static const TextStyle title4Xl = TextStyle(
    fontSize: 64,
    fontWeight: FontWeight.bold,
  );
  static const TextStyle title3Xl = TextStyle(
    fontSize: 44,
    fontWeight: FontWeight.bold,
  );
  static const TextStyle title2Xl = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
  );
  static const TextStyle titleXl = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle titleLg = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle titleMd = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle bodyLg = TextStyle(fontSize: 20);
  static const TextStyle bodyMd = TextStyle(fontSize: 17);
  static const TextStyle bodyBase = TextStyle(fontSize: 15);
  static const TextStyle bodySm = TextStyle(fontSize: 13);
  static const TextStyle bodyXs = TextStyle(fontSize: 11);

  static const TextStyle uiMd = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle uiSm = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle uiXs = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );

  // Legacy mappings for incremental migration
  static const TextStyle labelXs = TextStyle(fontSize: 11);
  static const TextStyle labelSm = TextStyle(fontSize: 12);
  static const TextStyle titleSm = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );
}

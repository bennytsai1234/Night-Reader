import 'package:flutter/material.dart';

/// Typography scale tokens — 夜讀 (Yè Dú)
class AppTextStyles {
  AppTextStyles._();

  /// 正文、資訊列與介面文字的標點字型（`assets/fonts/NightReaderPunct-*.ttf`，由同目錄
  /// `generate_punct_font.py` 從 Noto Sans CJK TC 產生）。
  ///
  /// 只收「，。、；：！？」的繁中置中字形、改為教育部位置的「」『』
  /// （直筆外緣貼字格中線，各佔四分之一格），以及置中的刪節號「…」與拉滿
  /// 整格的破折號「—」（系統回退會落到 Roboto 的西文窄字形）。放在字型清單首位，標點不受
  /// 手機系統字型的語系與廠商設定影響；其餘字元交給後面的字族（正文的回退
  /// 字族，介面是介面字型或平台預設字族，見 `buildAppTheme`）與平台回退，
  /// 與未指定字型時相同。上下度量和 Noto Sans CJK 相同，混排時行高與基線
  /// 不變。
  static const String punctuationFontFamily = 'NightReaderPunct';

  static const TextStyle display = TextStyle(
    fontSize: 88,
    height: 1.15,
    fontWeight: FontWeight.bold,
  );
  static const TextStyle title4Xl = TextStyle(
    fontSize: 64,
    height: 1.15,
    fontWeight: FontWeight.bold,
  );
  static const TextStyle title3Xl = TextStyle(
    fontSize: 44,
    height: 1.2,
    fontWeight: FontWeight.bold,
  );
  static const TextStyle title2Xl = TextStyle(
    fontSize: 32,
    height: 1.25,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle titleXl = TextStyle(
    fontSize: 24,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle titleLg = TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle titleMd = TextStyle(
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle bodyLg = TextStyle(fontSize: 20, height: 1.5);
  static const TextStyle bodyMd = TextStyle(fontSize: 17, height: 1.5);
  static const TextStyle bodyBase = TextStyle(fontSize: 15, height: 1.5);
  static const TextStyle bodySm = TextStyle(fontSize: 13, height: 1.45);
  static const TextStyle bodyXs = TextStyle(fontSize: 11, height: 1.45);

  static const TextStyle uiMd = TextStyle(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle uiSm = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
  );
  static const TextStyle uiXs = TextStyle(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w500,
  );

  // Legacy mappings for incremental migration
  static const TextStyle labelXs = TextStyle(fontSize: 11, height: 1.2);
  static const TextStyle labelSm = TextStyle(fontSize: 12, height: 1.2);

  /// 徽章、標籤等極小輔助文字（書源標記、網址）。
  static const TextStyle micro = TextStyle(fontSize: 10, height: 1.2);
  static const TextStyle titleSm = TextStyle(
    fontSize: 18,
    height: 1.3,
    fontWeight: FontWeight.bold,
  );
}

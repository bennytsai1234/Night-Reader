import 'dart:convert';

import 'package:night_reader/features/source_manager/source_manager_provider.dart';

/// 外部匯入的內容類型。
enum ImportContentKind {
  bookSource('辨識為書源資料'),
  rssSource('這是訂閱源，夜讀只支援書源，無法匯入'),
  replaceRule('辨識為替換規則'),
  theme('辨識為閱讀主題，但目前沒有可用的主題匯入流程'),
  bookshelf('辨識為書架資料');

  const ImportContentKind(this.description);

  /// 外部匯入對話框裡說明這份內容是什麼的那一行。
  final String description;

  /// 夜讀有匯入流程的類型；其他類型只告知、不提供匯入按鈕。
  bool get importable => this != rssSource && this != theme;
}

/// 依內容判斷外部匯入的類型；不是 JSON 或認不出來時回 `null`。
///
/// 分享的檔案、分享的文字、沒帶類型的匯入連結（`legado://import/auto`）都用
/// 這一個判斷，同一份內容不會一處說是書源、另一處說無法辨識。判斷順序對照
/// Legado 的 `BaseAssociationViewModel.importJson`：看陣列第一筆（不是陣列就
/// 看整個物件）有哪個欄位。書架匯出是夜讀自己的格式，最後才看。
ImportContentKind? detectImportContentKind(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(normalizeImportJson(text));
  } on FormatException {
    return null;
  }
  final first = decoded is List && decoded.isNotEmpty ? decoded.first : decoded;
  if (first is! Map) return null;
  if (first.containsKey('bookSourceUrl')) return ImportContentKind.bookSource;
  if (first.containsKey('sourceUrl')) return ImportContentKind.rssSource;
  if (first.containsKey('pattern')) return ImportContentKind.replaceRule;
  if (first.containsKey('themeName')) return ImportContentKind.theme;
  // 夜讀的書架匯出（{kind, books, chapters, sources}），或書籍物件與其陣列。
  if (first['books'] is List || first.containsKey('bookUrl')) {
    return ImportContentKind.bookshelf;
  }
  return null;
}

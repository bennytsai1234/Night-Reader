import 'dart:convert';
import 'dart:isolate';

import 'package:night_reader/core/backup/bookshelf_exchange_service.dart';
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
}

/// 判斷好的外部匯入內容（[detectImportContent]）。
class DetectedImport {
  const DetectedImport(this.kind, {this.bookshelf});

  final ImportContentKind kind;

  /// 書架檔解析好的內容，只有 [ImportContentKind.bookshelf] 有：交給書架匯入
  /// 不用再解析一次。
  final BookshelfFile? bookshelf;
}

/// 依內容判斷外部匯入的類型；不是 JSON 或認不出來時回 `null`。在背景
/// isolate 解析一次（分享的檔可能很大）。
///
/// 分享的檔案、分享的文字、沒帶類型的匯入連結（`legado://import/auto`）都用
/// 這一個判斷，同一份內容不會一處說是書源、另一處說無法辨識。欄位與順序對照
/// Legado 的 `BaseAssociationViewModel.importJson`；陣列看第一個認得的項目，
/// 和各匯入器一樣略過前面的空項目。都不是書源、訂閱源、替換規則、主題時，
/// 照書架匯入同一個判斷（[BookshelfFile.fromDecoded]）看是不是書架檔。
Future<DetectedImport?> detectImportContent(String text) =>
    Isolate.run(() => _detect(text));

DetectedImport? _detect(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(normalizeImportJson(text));
  } on FormatException {
    return null;
  }
  final entries = decoded is List ? decoded : [decoded];
  for (final entry in entries) {
    if (entry is! Map) continue;
    final kind = _kindOfEntry(entry);
    if (kind != null) return DetectedImport(kind);
  }
  final bookshelf = BookshelfFile.fromDecoded(decoded);
  return bookshelf == null
      ? null
      : DetectedImport(ImportContentKind.bookshelf, bookshelf: bookshelf);
}

ImportContentKind? _kindOfEntry(Map<dynamic, dynamic> entry) {
  if (entry.containsKey('bookSourceUrl')) return ImportContentKind.bookSource;
  if (entry.containsKey('sourceUrl')) return ImportContentKind.rssSource;
  // 替換規則的匯入（`ReplaceRule.fromJson`）也收 `regex` 這個別名。
  if (entry.containsKey('pattern') || entry.containsKey('regex')) {
    return ImportContentKind.replaceRule;
  }
  if (entry.containsKey('themeName')) return ImportContentKind.theme;
  return null;
}

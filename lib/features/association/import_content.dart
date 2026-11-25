import 'dart:convert';
import 'dart:isolate';

import 'package:night_reader/core/backup/bookshelf_exchange_service.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';

/// 外部匯入的內容類型。
enum ImportContentKind {
  bookSource('匯入書源？', '下一步再挑要匯入哪些。'),
  rssSource('無法匯入', '這是訂閱源，夜讀只支援書源。'),
  replaceRule('匯入替換規則？', '下一步再挑要匯入哪些。'),
  theme('無法匯入', '這是閱讀主題，夜讀沒有主題匯入。'),
  bookshelf('匯入書架？', '檔裡的書加進書架，已有的不重複加。');

  const ImportContentKind(this.title, this.consequence);

  /// 外部匯入提示框的標題：能匯入的直接問，不能的寫狀態。
  final String title;

  /// 標題下面那一句：按下去之後會怎樣，或為什麼不能匯入。
  final String consequence;
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

import 'dart:convert';

import 'package:night_reader/core/config/app_config.dart';
import 'package:night_reader/core/constant/book_type.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/engine/book/book_help.dart';

import 'book_base.dart';

/// Book 擴展 - 類型感知與業務屬性
/// (原 Android BookExtensions.kt)
extension BookExtensions on BookBase {
  // --- 延遲加載變數 Map ---
  Map<String, String> get variableMap {
    if (variable != null && variable!.isNotEmpty) {
      try {
        final decoded = jsonDecode(variable!);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }
    return {};
  }

  /// 這本書是小說、漫畫還是有聲（ADR 0053）：問這一個，不自己看 `type`。
  /// 加入書架與換源時照書源的類別寫進 `type`，書源的類型改了也跟著改。
  BookSourceKind get bookKind => BookSourceKind.ofBookType(type);

  /// 閱讀統計、書籤、標註記的書名：小說就是書名，漫畫、有聲加上前綴
  /// （[BookSourceKind.recordName]）。
  String get recordName => bookKind.recordName(name);

  bool get isLocal =>
      origin == BookType.localOrigin ||
      origin == BookType.localTag ||
      origin.startsWith('loc_');
  bool get isUpdate => lastCheckCount > 0;

  // --- 顯示輔助 ---
  String getRealAuthor() => BookHelp.formatBookAuthor(author);
  String? getDisplayCover() {
    if (customCoverLocalPath != null && customCoverLocalPath!.isNotEmpty) {
      return 'local://$customCoverLocalPath';
    }
    if (customCoverUrl != null && customCoverUrl!.isNotEmpty) {
      return customCoverUrl;
    }
    if (coverLocalPath != null && coverLocalPath!.isNotEmpty) {
      return 'local://$coverLocalPath';
    }
    return coverUrl;
  }

  String? getDisplayIntro() =>
      (customIntro == null || customIntro!.isEmpty) ? intro : customIntro;

  /// 轉換為 SearchBook (對標 Android Book.toSearchBook)
  SearchBook toSearchBook() {
    return SearchBook(
      bookUrl: bookUrl,
      name: name,
      author: author,
      kind: kind,
      coverUrl: coverUrl,
      intro: intro,
      latestChapterTitle: latestChapterTitle,
      tocUrl: tocUrl,
      origin: origin,
      originName: originName,
      originOrder: originOrder,
      type: type,
      variable: variable,
      wordCount: wordCount,
    );
  }

  /// 是否使用淨化替換規則
  bool getUseReplaceRule() {
    final explicitValue = readConfig?.useReplaceRule;
    if (explicitValue != null) return explicitValue;
    // 漫畫、有聲書預設關閉淨化
    if (bookKind != BookSourceKind.novel) return false;
    return AppConfig.replaceEnableDefault;
  }

  bool getReSegment() => readConfig?.reSegment ?? false;
}

/// Book 位元運算擴展
extension BookBitwiseExtension on BookBase {
  bool isType(int typeMask) => (type & typeMask) != 0;
  void addType(int typeMask) => type |= typeMask;
  void removeType(int typeMask) => type &= ~typeMask;

  bool hasGroup(int groupIdMask) {
    if (groupIdMask <= 0) return true;
    return (group & groupIdMask) != 0;
  }

  void addGroup(int groupIdMask) => group |= groupIdMask;
  void removeGroup(int groupIdMask) => group &= ~groupIdMask;
}

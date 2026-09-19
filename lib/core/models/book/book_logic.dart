import 'dart:convert';

import 'package:night_reader/core/models/chapter.dart';

import '../book.dart';
import 'chapter_alignment.dart';

/// Book 業務邏輯擴展
extension BookLogic on Book {
  void setVariable(String key, String value) {
    var map = variableMap;
    map[key] = value;
    variable = jsonEncode(map);
  }

  /// 書籍遷移邏輯 (原 Android Book.migrateTo)
  Book migrateTo(Book newBook, List<BookChapter>? toc) {
    var alignedIndex = chapterIndex;
    if (toc != null && toc.isNotEmpty) {
      alignedIndex = alignChapterIndex(
        oldIndex: chapterIndex,
        oldTitle: durChapterTitle,
        oldTotalCount: totalChapterNum,
        newChapters: toc,
      );
    }

    final migratedAnchor = _migratedReaderAnchor(alignedIndex);
    final preserveContentAddress = migratedAnchor != null;

    return newBook.copyWith(
      chapterIndex: alignedIndex,
      durChapterTitle: (toc != null && alignedIndex < toc.length)
          ? toc[alignedIndex].title
          : durChapterTitle,
      // A scalar UTF-16 offset has no meaning in another source. Preserve the
      // intra-chapter address only when it is bound to the exact old display
      // text; Reader V2 will resolve that content anchor against the new text.
      charOffset: preserveContentAddress ? charOffset : 0,
      visualOffsetPx: preserveContentAddress ? visualOffsetPx : 0.0,
      readerAnchorJson: migratedAnchor,
      durChapterTime: durChapterTime,
      group: group,
      order: order,
      customCoverUrl: customCoverUrl,
      customIntro: customIntro,
      customTag: customTag,
      canUpdate: canUpdate,
      readConfig: readConfig,
      isInBookshelf: isInBookshelf,
    );
  }

  String? _migratedReaderAnchor(int alignedIndex) {
    final encoded = readerAnchorJson;
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      final anchor = Map<String, dynamic>.from(decoded);
      final hash = anchor['contentHash'];
      final contentLength = anchor['contentLength'];
      final ownsCurrentScalar =
          anchor['chapterIndex'] == chapterIndex &&
          anchor['charOffset'] == charOffset;
      if (!ownsCurrentScalar ||
          hash is! String ||
          hash.isEmpty ||
          contentLength is! num ||
          contentLength < 0) {
        return null;
      }
      anchor['chapterIndex'] = alignedIndex;
      anchor['charOffset'] = charOffset;
      anchor['visualOffsetPx'] = visualOffsetPx;
      return jsonEncode(anchor);
    } catch (_) {
      return null;
    }
  }
}

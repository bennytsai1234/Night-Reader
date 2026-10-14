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

  /// 已存的目錄整份換成 [toc] 之前呼叫：把閱讀進度對到新目錄裡的同一章。
  /// [oldChapter] 是舊目錄在目前序號上的那一章。
  ///
  /// 書源在中間插入或刪除章節後序號會位移，所以依章節網址找回那一章，章內
  /// 位置照舊。那一章已不在新目錄裡，才照標題、章號與比例估計（同換源），
  /// 章內位置只在綁得住原文時保留。舊目錄沒有這一章時無從對應，進度不動。
  /// 回傳進度有沒有變。
  bool realignProgress(List<BookChapter> toc, {BookChapter? oldChapter}) {
    if (toc.isEmpty || oldChapter == null) return false;
    final sameChapter = toc.indexWhere((c) => c.url == oldChapter.url);
    if (sameChapter >= 0) {
      if (sameChapter == chapterIndex) return false;
      readerAnchorJson = _reindexedReaderAnchor(sameChapter);
      chapterIndex = sameChapter;
      durChapterTitle = toc[sameChapter].title;
      return true;
    }
    final alignedIndex = alignChapterIndex(
      oldIndex: chapterIndex,
      oldTitle: oldChapter.title,
      oldTotalCount: totalChapterNum,
      newChapters: toc,
    );
    // 只是換了網址（例如書源搬家），同一個位置還是同名的章。
    if (alignedIndex == chapterIndex &&
        toc[alignedIndex].title == oldChapter.title) {
      return false;
    }
    final anchor = _migratedReaderAnchor(alignedIndex);
    if (anchor == null) {
      charOffset = 0;
      visualOffsetPx = 0.0;
    }
    readerAnchorJson = anchor;
    chapterIndex = alignedIndex;
    durChapterTitle = toc[alignedIndex].title;
    return true;
  }

  /// 同一章換了序號：錨點跟著換序號，章內位置不變。錨點不屬於目前進度時
  /// 本來就不會被採用，直接丟掉。
  String? _reindexedReaderAnchor(int newIndex) {
    final anchor = _ownedReaderAnchor();
    if (anchor == null) return null;
    anchor['chapterIndex'] = newIndex;
    return jsonEncode(anchor);
  }

  String? _migratedReaderAnchor(int alignedIndex) {
    final anchor = _ownedReaderAnchor();
    if (anchor == null) return null;
    final hash = anchor['contentHash'];
    final contentLength = anchor['contentLength'];
    if (hash is! String ||
        hash.isEmpty ||
        contentLength is! num ||
        contentLength < 0) {
      return null;
    }
    anchor['chapterIndex'] = alignedIndex;
    anchor['charOffset'] = charOffset;
    anchor['visualOffsetPx'] = visualOffsetPx;
    return jsonEncode(anchor);
  }

  Map<String, dynamic>? _ownedReaderAnchor() {
    final encoded = readerAnchorJson;
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      final anchor = Map<String, dynamic>.from(decoded);
      final ownsCurrentScalar =
          anchor['chapterIndex'] == chapterIndex &&
          anchor['charOffset'] == charOffset;
      return ownsCurrentScalar ? anchor : null;
    } catch (_) {
      return null;
    }
  }
}

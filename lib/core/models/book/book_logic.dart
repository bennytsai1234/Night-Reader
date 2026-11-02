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
      progressTime: progressTime,
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

  /// 已存的目錄 [oldToc] 整份換成 [toc] 時呼叫：把閱讀進度對到新目錄裡的
  /// 同一章。
  ///
  /// 書源在中間插入或刪除章節後序號會位移，所以依章節網址找回那一章，章內
  /// 位置照舊。那一章已不在新目錄裡，才照標題、章號與比例估計（同換源），
  /// 章內位置只在綁得住原文時保留。舊目錄沒有這一章時無從對應，進度不動。
  /// 回傳進度有沒有變。
  bool realignProgress(
    List<BookChapter> toc, {
    required List<BookChapter> oldToc,
  }) {
    BookChapter? oldChapter;
    for (final chapter in oldToc) {
      if (chapter.index == chapterIndex) oldChapter = chapter;
    }
    if (toc.isEmpty || oldChapter == null) return false;
    final oldUrl = oldChapter.url;
    final sameChapter = toc.indexWhere((c) => c.url == oldUrl);
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
      oldTotalCount: oldToc.length,
      newChapters: toc,
    );
    // 同名不代表正文相同（例如書源搬家後改了內容），所以即使落在同一個
    // 序號，章內位置也照錨點決定。
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

  /// 閱讀紀錄還沒有章名（剛加入書架、還沒讀過）時，照目錄 [toc] 記下目前
  /// 那一章的章名：開書時頁首頁尾的骨架照它量章名的長度，不用等目錄讀出來。
  /// 已有章名就不動，那是讀的時候寫的。
  void fillChapterTitle(List<BookChapter> toc) {
    if (durChapterTitle?.isNotEmpty ?? false) return;
    for (final chapter in toc) {
      if (chapter.index == chapterIndex) {
        durChapterTitle = chapter.title;
        return;
      }
    }
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

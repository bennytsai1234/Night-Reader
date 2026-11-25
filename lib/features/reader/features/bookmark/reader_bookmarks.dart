import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/chapter_alignment.dart';
import 'package:night_reader/core/models/reading/bookmark.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/reader/text_view/overlay/bookmark_marks.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';

/// 閱讀器裡這本書的書籤：照書名加作者讀出來，資料表一變（新增、刪除、
/// 另一台同步過來）就跟著更新，正文旁的記號與目錄的書籤分頁都看它。
class ReaderBookmarks extends ValueNotifier<List<Bookmark>> {
  ReaderBookmarks({
    required Book book,
    required BookmarkDao? dao,
    required this._chapters,
  }) : _book = book,
       _dao = dao,
       super(const <Bookmark>[]) {
    _subscription = dao
        ?.watchByBook(book.recordName, book.author)
        .listen((items) => value = items);
  }

  final Book _book;
  final BookmarkDao? _dao;
  final List<BookChapter> Function() _chapters;
  StreamSubscription<List<Bookmark>>? _subscription;

  /// 正文旁要畫記號的位置，章節序號已經對到這台的目錄。
  late final ValueNotifier<List<ReaderMark>> marks = ValueNotifier(const []);

  @override
  set value(List<Bookmark> items) {
    super.value = items;
    refreshMarks();
  }

  /// 目錄讀出來或換過時重算記號落在哪一章。
  void refreshMarks() {
    final chapters = _chapters();
    marks.value = [
      for (final bookmark in value)
        (
          id: bookmark.id,
          location: locationOf(
            bookmark,
            chapterIndex: chapterIndexIn(
              bookmark,
              chapters,
              reversed: _book.getReverseToc(),
            ),
          ),
        ),
    ];
  }

  bool get available => _dao != null;

  /// 在 [location]（已綁好那一章正文的錨點）留一個書籤。
  Future<Bookmark?> add({
    required ReaderLocation location,
    required String chapterTitle,
    required String excerpt,
  }) async {
    final dao = _dao;
    if (dao == null) return null;
    return dao.add(
      Bookmark(
        id: 0,
        bookName: _book.recordName,
        bookAuthor: _book.author,
        chapterIndex: location.chapterIndex,
        chapterTitle: chapterTitle,
        charOffset: location.charOffset,
        anchor: jsonEncode(location.toJson()),
        excerpt: excerpt,
        tocReversed: _book.getReverseToc(),
      ),
    );
  }

  Future<void> remove(Bookmark bookmark) async =>
      _dao?.deleteByIds([bookmark.id]);

  /// 刪掉後按「復原」：照原本的編號放回去。
  Future<void> restore(Bookmark bookmark) async => _dao?.upsertAll([bookmark]);

  /// 書籤在這台目錄（[chapters]，[reversed] 是這本書現在反轉了沒）裡是
  /// 第幾章（[chapterIndexByTitle]）。
  static int chapterIndexIn(
    Bookmark bookmark,
    List<BookChapter> chapters, {
    required bool reversed,
  }) => chapterIndexByTitle(
    chapterIndex: bookmark.chapterIndex,
    chapterTitle: bookmark.chapterTitle,
    countedReversed: bookmark.tocReversed,
    reversed: reversed,
    chapters: chapters,
  );

  /// 跳回書籤要去的位置：記下的錨點（含前後原文，正文變了照它找回同一
  /// 句），章節序號換成這台目錄裡的。
  static ReaderLocation locationOf(
    Bookmark bookmark, {
    required int chapterIndex,
  }) => locationFromAnchor(
    bookmark.anchor,
    chapterIndex: chapterIndex,
    charOffset: bookmark.charOffset,
  );

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    marks.dispose();
    super.dispose();
  }
}

/// 記下的錨點（`ReaderLocation` 的 JSON，含前後原文）換成閱讀器的位置，
/// 章節序號換成這台目錄裡的 [chapterIndex]；讀不懂時照章內第幾個字。書籤
/// 與標註共用。
ReaderLocation locationFromAnchor(
  String? anchor, {
  required int chapterIndex,
  required int charOffset,
}) {
  if (anchor != null) {
    try {
      final decoded = jsonDecode(anchor);
      if (decoded is Map) {
        return ReaderLocation.fromJson(Map<String, dynamic>.from(decoded))
            .copyWith(chapterIndex: chapterIndex, visualOffsetPx: 0);
      }
    } on FormatException {
      // 讀不懂的錨點照章內第幾個字跳。
    }
  }
  return ReaderLocation(chapterIndex: chapterIndex, charOffset: charOffset);
}

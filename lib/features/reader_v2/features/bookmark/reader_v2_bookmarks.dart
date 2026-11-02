import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book/chapter_alignment.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/bookmark_marks.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

/// 閱讀器裡這本書的書籤：照書名加作者讀出來，資料表一變（新增、刪除、
/// 另一台同步過來）就跟著更新，正文旁的記號與目錄的書籤分頁都看它。
class ReaderV2Bookmarks extends ValueNotifier<List<Bookmark>> {
  ReaderV2Bookmarks({
    required Book book,
    required BookmarkDao? dao,
    required this._chapters,
  }) : _book = book,
       _dao = dao,
       super(const <Bookmark>[]) {
    _subscription = dao
        ?.watchByBook(book.name, book.author)
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
            chapterIndex: chapterIndexIn(bookmark, chapters),
          ),
        ),
    ];
  }

  bool get available => _dao != null;

  /// 在 [location]（已綁好那一章正文的錨點）留一個書籤。
  Future<Bookmark?> add({
    required ReaderV2Location location,
    required String chapterTitle,
    required String excerpt,
  }) async {
    final dao = _dao;
    if (dao == null) return null;
    return dao.add(
      Bookmark(
        id: 0,
        bookName: _book.name,
        bookAuthor: _book.author,
        chapterIndex: location.chapterIndex,
        chapterTitle: chapterTitle,
        charOffset: location.charOffset,
        anchor: jsonEncode(location.toJson()),
        excerpt: excerpt,
      ),
    );
  }

  Future<void> remove(Bookmark bookmark) async =>
      _dao?.deleteByIds([bookmark.id]);

  /// 刪掉後按「復原」：照原本的編號放回去。
  Future<void> restore(Bookmark bookmark) async => _dao?.upsertAll([bookmark]);

  /// 書籤在這台目錄（[chapters]）裡是第幾章：先找同名的章（繁簡不同也
  /// 算），再照章號；目錄還沒讀出來時照記下的序號。
  static int chapterIndexIn(Bookmark bookmark, List<BookChapter> chapters) =>
      alignChapterIndex(
        oldIndex: bookmark.chapterIndex,
        oldTitle: bookmark.chapterTitle,
        oldTotalCount: 0,
        newChapters: chapters,
      );

  /// 跳回書籤要去的位置：記下的錨點（含前後原文，正文變了照它找回同一
  /// 句），章節序號換成這台目錄裡的。
  static ReaderV2Location locationOf(
    Bookmark bookmark, {
    required int chapterIndex,
  }) {
    final encoded = bookmark.anchor;
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          return ReaderV2Location.fromJson(Map<String, dynamic>.from(decoded))
              .copyWith(chapterIndex: chapterIndex, visualOffsetPx: 0);
        }
      } on FormatException {
        // 讀不懂的錨點照章內第幾個字跳。
      }
    }
    return ReaderV2Location(
      chapterIndex: chapterIndex,
      charOffset: bookmark.charOffset,
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    marks.dispose();
    super.dispose();
  }
}

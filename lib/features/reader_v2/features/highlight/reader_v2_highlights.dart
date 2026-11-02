import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/highlight.dart';
import 'package:night_reader/features/reader_v2/features/bookmark/reader_v2_bookmarks.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/highlight_marks.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

/// 閱讀器裡這本書的標註：照書名加作者讀出來，資料表一變就跟著更新，
/// 正文上的底色、底線與目錄的標註分頁都看它（同 [ReaderV2Bookmarks]）。
class ReaderV2Highlights extends ValueNotifier<List<Highlight>> {
  ReaderV2Highlights({
    required Book book,
    required HighlightDao? dao,
    required this._chapters,
  }) : _book = book,
       _dao = dao,
       super(const <Highlight>[]) {
    _subscription = dao
        ?.watchByBook(book.name, book.author)
        .listen((items) => value = items);
  }

  final Book _book;
  final HighlightDao? _dao;
  final List<BookChapter> Function() _chapters;
  StreamSubscription<List<Highlight>>? _subscription;

  /// 正文上要畫的標註，章節序號已經對到這台的目錄。
  late final ValueNotifier<List<ReaderHighlightMark>> marks = ValueNotifier(
    const [],
  );

  @override
  set value(List<Highlight> items) {
    super.value = items;
    refreshMarks();
  }

  /// 目錄讀出來或換過時重算標註落在哪一章。
  void refreshMarks() {
    final chapters = _chapters();
    marks.value = [
      for (final highlight in value)
        if (highlight.quote.isNotEmpty)
          (
            id: highlight.id,
            location: locationOf(
              highlight,
              chapterIndex: chapterIndexIn(highlight, chapters),
            ),
            length: highlight.quote.length,
            color: highlight.color,
            style: highlight.style,
          ),
    ];
  }

  bool get available => _dao != null;

  Highlight? byId(int id) {
    for (final highlight in value) {
      if (highlight.id == id) return highlight;
    }
    return null;
  }

  /// 把 [location]（已綁好那一章正文的錨點）起的 [quote] 畫上標註，顏色與
  /// 樣子沿用最近畫的那一個（第一次是黃色底色）。
  Future<Highlight?> add({
    required ReaderV2Location location,
    required String chapterTitle,
    required String quote,
  }) async {
    final dao = _dao;
    if (dao == null || quote.isEmpty) return null;
    final latest = await dao.latest();
    return dao.add(
      Highlight(
        id: 0,
        bookName: _book.name,
        bookAuthor: _book.author,
        chapterIndex: location.chapterIndex,
        chapterTitle: chapterTitle,
        charOffset: location.charOffset,
        anchor: jsonEncode(location.toJson()),
        quote: quote,
        color: latest?.color ?? HighlightColor.amber,
        style: latest?.style ?? HighlightStyle.fill,
      ),
    );
  }

  /// 換顏色或樣子、刪掉後復原：照原本的編號存回去。
  Future<void> save(Highlight highlight) async => _dao?.upsertAll([highlight]);

  Future<void> remove(Highlight highlight) async =>
      _dao?.deleteByIds([highlight.id]);

  /// 標註在這台目錄（[chapters]）裡是第幾章（同書籤）。
  static int chapterIndexIn(Highlight highlight, List<BookChapter> chapters) =>
      chapterIndexByTitle(
        chapterIndex: highlight.chapterIndex,
        chapterTitle: highlight.chapterTitle,
        chapters: chapters,
      );

  /// 標註開頭的位置：記下的錨點，章節序號換成這台目錄裡的（同書籤）。
  static ReaderV2Location locationOf(
    Highlight highlight, {
    required int chapterIndex,
  }) => locationFromAnchor(
    highlight.anchor,
    chapterIndex: chapterIndex,
    charOffset: highlight.charOffset,
  );

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    marks.dispose();
    super.dispose();
  }
}

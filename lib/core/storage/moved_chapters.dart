import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book/chapter_alignment.dart';

/// 檢查更新換目錄時，書源換了網址的章：舊網址 → 新網址（`BookTocReplacer`
/// 換目錄那一次認出的同一章）。記在畫面執行緒的記憶體裡，重開 App 就清掉。
///
/// 開著的閱讀器、漫畫閱讀器與播放器手上是開書時的目錄，存進度時照
/// [indexOf] 找這一章在目前目錄的序號：網址還在就是它，換了網址照這裡記的
/// 新網址找，都查不到時照章名與章號對（書源同時換了網址與序號、換目錄時
/// 沒認出同一章）。
abstract final class MovedChapters {
  static final Map<String, Map<String, String>> _byBook = {};
  static final StreamController<String> _recorded =
      StreamController.broadcast();

  /// 查過、目前目錄裡就是沒有這一章的：存進度每隔幾百毫秒一次，不必每次
  /// 都讀整份目錄再比一次章名。換目錄（[record]）時清掉。
  static final Map<String, Set<String>> _missing = {};

  /// 記下一本書換目錄時換了網址的章（[moved]）。之前記過的舊網址接到最新
  /// 的網址：換過兩次網址的章，第一次的網址也找得到。
  static void record(String bookUrl, Map<String, String> moved) {
    // 目錄換過了：之前查不到這一章的結果不算，再照章名找一次。
    _missing.remove(bookUrl);
    if (moved.isEmpty) return;
    final book = _byBook.putIfAbsent(bookUrl, () => {});
    for (final entry in book.entries) {
      final next = moved[entry.value];
      if (next != null) book[entry.key] = next;
    }
    book.addAll(moved);
    _recorded.add(bookUrl);
  }

  /// 記下新的對應時傳出那本書的網址：開著的閱讀器收到後把目前位置重存
  /// 一次（資料庫換好目錄、對應還沒傳回來的那一下存的進度會照舊序號寫）。
  static Stream<String> get recorded => _recorded.stream;

  /// 章節 [url] 在這本書目前目錄裡的序號。網址還在就是它；換了網址照記下
  /// 的新網址找；都查不到時照 [title] 找：書源同時換了這一章的網址與序號、
  /// 換目錄時沒認出同一章（新目錄只回來章號，或章名改了寫法）時，照章名與
  /// 章號對回同一章（比對方式同 `Book.realignProgress`），認出的對應記下來，
  /// 下次不必再讀整份目錄。對不到是 null。
  ///
  /// [oldIndex]、[oldTotalCount] 是開書時的目錄裡這一章的位置與章數：好幾
  /// 章同名時取離它最近的那一章。
  static Future<int?> indexOf(
    ChapterDao chapterDao,
    String bookUrl,
    String url, {
    String? title,
    int oldIndex = 0,
    int oldTotalCount = 0,
  }) async {
    final index = await chapterDao.indexOfUrl(bookUrl, url);
    if (index != null) return index;
    final moved = _byBook[bookUrl]?[url];
    if (moved != null) {
      final movedIndex = await chapterDao.indexOfUrl(bookUrl, moved);
      if (movedIndex != null) return movedIndex;
    }
    final name = title?.trim() ?? '';
    if (name.isEmpty || (_missing[bookUrl]?.contains(url) ?? false)) {
      return null;
    }
    final chapters = await chapterDao.getByBook(bookUrl);
    if (chapters.isEmpty) {
      _missing.putIfAbsent(bookUrl, () => {}).add(url);
      return null;
    }
    final found = alignChapter(
      oldIndex: oldIndex,
      oldTitle: name,
      oldTotalCount: oldTotalCount,
      newChapters: chapters,
    );
    if (!found.matched) {
      _missing.putIfAbsent(bookUrl, () => {}).add(url);
      return null;
    }
    _remember(bookUrl, url, chapters[found.index].url);
    return found.index;
  }

  /// 照章名認出的對應記進 [_byBook]，和 [record] 一樣把之前指著 [url] 的舊
  /// 網址接到新的。存進度的人自己正用著這個結果，不必再通知重存。
  static void _remember(String bookUrl, String url, String movedTo) {
    final book = _byBook.putIfAbsent(bookUrl, () => {});
    for (final entry in book.entries.toList()) {
      if (entry.value == url) book[entry.key] = movedTo;
    }
    book[url] = movedTo;
  }

  @visibleForTesting
  static void clear() {
    _byBook.clear();
    _missing.clear();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';

/// 檢查更新換目錄時，書源換了網址的章：舊網址 → 新網址（`BookTocReplacer`
/// 換目錄那一次認出的同一章）。記在畫面執行緒的記憶體裡，重開 App 就清掉。
///
/// 開著的閱讀器、漫畫閱讀器與播放器手上是開書時的目錄，存進度時照
/// [indexOf] 找這一章在目前目錄的序號：網址還在就是它，換了網址照這裡記的
/// 新網址找，不再自己比章名。
abstract final class MovedChapters {
  static final Map<String, Map<String, String>> _byBook = {};
  static final StreamController<String> _recorded =
      StreamController.broadcast();

  /// 記下一本書換目錄時換了網址的章（[moved]）。之前記過的舊網址接到最新
  /// 的網址：換過兩次網址的章，第一次的網址也找得到。
  static void record(String bookUrl, Map<String, String> moved) {
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

  /// 章節網址 [url] 在這本書目前目錄裡的序號：網址還在就是它，換了網址照
  /// 記下的新網址找；都沒有是 null。
  static Future<int?> indexOf(
    ChapterDao chapterDao,
    String bookUrl,
    String url,
  ) async {
    final index = await chapterDao.indexOfUrl(bookUrl, url);
    if (index != null) return index;
    final moved = _byBook[bookUrl]?[url];
    return moved == null ? null : chapterDao.indexOfUrl(bookUrl, moved);
  }

  @visibleForTesting
  static void clear() => _byBook.clear();
}

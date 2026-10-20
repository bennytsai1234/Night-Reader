import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/utils/string_utils.dart';

/// 從書籍詳情補到的封面與字數；沒抓到的是空字串。
typedef ExploreBookExtras = ({String coverUrl, String wordCount});

typedef ExploreExtrasLoader = Future<ExploreBookExtras> Function(
  BookSource source,
  Book book, {
  CancelToken? cancelToken,
});

/// 發現清單上畫出來的書，清單規則沒給封面或字數時，在背景向書源取書籍
/// 詳情補上（[BookSourceService.getCoverAndWordCount]，在書源 isolate
/// 解析，ADR 0028）。
///
/// 每一本只取一次、記住結果到離開這一頁；補到的只通知那一本的
/// [extrasOf]，清單本身不重建。還在排隊的書捲出畫面就不取，下次畫出來
/// 再排；離開頁面（[dispose]）時取消進行中的請求。
class ExploreBookDetails {
  ExploreBookDetails({ExploreExtrasLoader? loader})
    : _loader = loader ?? BookSourceService().getCoverAndWordCount;

  /// 同時取幾本。全部打在同一個網站上，和抓一章的多個正文分頁一樣同時 4 個
  /// （`CompleteContentFetcher` 的預設）；書源自己設的限流（`concurrentRate`）
  /// 照樣生效。一個畫面約八、九列，兩輪就補完。
  static const int maxConcurrent = 4;

  final ExploreExtrasLoader _loader;
  final Map<String, ValueNotifier<ExploreBookExtras?>> _extras = {};

  /// 排過的書：排隊中、取得中或已經取過（含失敗）。
  final Set<String> _requested = {};
  final ListQueue<(BookSource, SearchBook)> _queue = ListQueue();
  final Map<String, CancelToken> _running = {};
  bool _disposed = false;

  /// 缺封面，或照清單的寫法（字數欄沒有時從分類補）也寫不出字數。
  static bool lacksExtras(SearchBook book) =>
      (book.coverUrl ?? '').trim().isEmpty ||
      StringUtils.displayWordCount(book.wordCount, book.kind).isEmpty;

  /// [book] 補上 [extras] 裡它缺的封面與字數；沒有要補的就是 [book] 本身。
  static SearchBook withExtras(SearchBook book, ExploreBookExtras? extras) {
    if (extras == null) return book;
    final cover = (book.coverUrl ?? '').trim().isEmpty ? extras.coverUrl : '';
    final words =
        StringUtils.displayWordCount(book.wordCount, book.kind).isEmpty
        ? extras.wordCount
        : '';
    if (cover.isEmpty && words.isEmpty) return book;
    return SearchBook.fromJson(book.toJson())
      ..coverUrl = cover.isEmpty ? book.coverUrl : cover
      ..wordCount = words.isEmpty ? book.wordCount : words;
  }

  /// 這本書補到的封面與字數；還沒補到是 null。
  ValueListenable<ExploreBookExtras?> extrasOf(String bookUrl) =>
      _extras.putIfAbsent(bookUrl, () => ValueNotifier(null));

  /// 詳情網址帶 `,{"webView":true}`：要開無頭瀏覽器渲染，一次只能跑一個、
  /// 取消也停不下來。背景補資料不佔用它，這種書照清單原本的樣子，點進
  /// 詳情時照常讀。
  static final RegExp _webViewOption = RegExp(
    r'''["']?webView["']?\s*:\s*(true|["']true["'])''',
  );

  static bool rendersInWebView(SearchBook book) {
    final options = RegExp(r',\s*\{').firstMatch(book.bookUrl);
    return options != null &&
        _webViewOption.hasMatch(book.bookUrl.substring(options.start));
  }

  /// [book] 出現在畫面上了：缺封面或字數、還沒排過就排進去。
  void shown(BookSource source, SearchBook book) {
    if (_disposed ||
        !lacksExtras(book) ||
        rendersInWebView(book) ||
        !_requested.add(book.bookUrl)) {
      return;
    }
    _queue.add((source, book));
    // 不在建構清單列的這一幀裡送出請求（要把書源複製到書源 isolate）。
    Timer.run(_startNext);
  }

  /// 這本書捲出畫面了：還在排隊就不取。
  void hidden(String bookUrl) {
    final before = _queue.length;
    _queue.removeWhere((entry) => entry.$2.bookUrl == bookUrl);
    if (_queue.length != before) _requested.remove(bookUrl);
  }

  /// 補位：同時取得中的不到 [maxConcurrent] 本時，送出排隊的下一本。每次
  /// 只送一本，送出的工作分散在不同的事件裡。
  void _startNext() {
    if (_disposed || _running.length >= maxConcurrent || _queue.isEmpty) {
      return;
    }
    final (source, book) = _queue.removeFirst();
    unawaited(_fetch(source, book));
    if (_queue.isNotEmpty) Timer.run(_startNext);
  }

  Future<void> _fetch(BookSource source, SearchBook book) async {
    final token = CancelToken();
    _running[book.bookUrl] = token;
    try {
      final extras = await _loader(source, book.toBook(), cancelToken: token);
      if (_disposed) return;
      if (extras.coverUrl.isEmpty && extras.wordCount.isEmpty) return;
      (_extras.putIfAbsent(book.bookUrl, () => ValueNotifier(null))).value =
          extras;
    } catch (error) {
      // 取不到就照清單原本的樣子，這一頁不再重試。
      if (!_disposed &&
          !(error is DioException && CancelToken.isCancel(error))) {
        AppLog.d('發現清單補封面與字數失敗：${book.name}：$error');
      }
    } finally {
      _running.remove(book.bookUrl);
      _startNext();
    }
  }

  void dispose() {
    _disposed = true;
    _queue.clear();
    for (final token in _running.values) {
      token.cancel('ExploreBookDetails disposed');
    }
    for (final notifier in _extras.values) {
      notifier.dispose();
    }
  }
}

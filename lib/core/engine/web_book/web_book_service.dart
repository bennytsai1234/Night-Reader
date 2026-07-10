import 'dart:async';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/engine/web_book/content_parser.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/network/str_response.dart';

/// WebBook - 書源抓取業務調度 (對標 Android model/webBook/WebBook.kt)
///
/// 注意：不使用 Isolate.run()，因為 AnalyzeRule 可能呼叫 JS 引擎 (flutter_js FFI)，
/// 而 FFI 綁定無法跨 Isolate 傳遞。解析操作本身是輕量的字串處理，不會阻塞 UI。
class WebBook {
  WebBook._();

  /// 目錄翻頁上限，防止無限迴圈
  static const int _maxTocPages = 100;

  /// 正文翻頁上限
  static const int _maxContentPages = 20;

  /// 多頁並發抓取的預設執行緒數 (對標 Android AppConfig.threadCount)
  static const int _pageConcurrency = 4;

  /// 搜尋書籍 (對標 searchBookAwait)
  static Future<List<SearchBook>> searchBookAwait(
    BookSource source,
    String key, {
    int? page = 1,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
    CancelToken? cancelToken,
  }) async {
    final searchUrl = source.searchUrl;
    if (searchUrl == null || searchUrl.isEmpty) {
      throw SourceException('搜尋 URL 不能為空', sourceUrl: source.bookSourceUrl);
    }

    final analyzeUrl = await AnalyzeUrl.create(
      searchUrl,
      source: source,
      key: key,
      page: page,
    );

    var res = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
    res = _runLoginCheckJs(source, res);
    _checkRedirect(source, res);
    _checkLoginRequired(res, stage: 'search');

    final results = await BookListParser.parse(
      source: source,
      body: res.body,
      baseUrl: res.url,
      isSearch: true,
      filter: filter,
      shouldBreak: shouldBreak,
    );

    return results;
  }

  /// 探索書籍 (對標 exploreBookAwait)
  static Future<List<SearchBook>> exploreBookAwait(
    BookSource source,
    String url, {
    int? page = 1,
    CancelToken? cancelToken,
  }) async {
    final analyzeUrl = await AnalyzeUrl.create(url, source: source, page: page);
    var res = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
    res = _runLoginCheckJs(source, res);
    _checkRedirect(source, res);
    _checkLoginRequired(res, stage: 'explore');

    return BookListParser.parse(
      source: source,
      body: res.body,
      baseUrl: res.url,
      isSearch: false,
    );
  }

  /// 獲取書籍資訊 (對標 getBookInfoAwait)
  static Future<Book> getBookInfoAwait(
    BookSource source,
    Book book, {
    bool canReName = true,
    CancelToken? cancelToken,
  }) async {
    if (book.infoHtml != null && book.infoHtml!.isNotEmpty) {
      final parsed = await BookInfoParser.parse(
        source: source,
        book: book,
        body: book.infoHtml!,
        baseUrl: book.bookUrl,
      );
      parsed.infoHtml = book.infoHtml;
      if (parsed.tocUrl.isEmpty || parsed.tocUrl == parsed.bookUrl) {
        parsed.tocHtml = book.infoHtml;
      }
      return parsed;
    }

    final analyzeUrl = await AnalyzeUrl.create(
      book.bookUrl,
      source: source,
      ruleData: book,
    );
    var res = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
    res = _runLoginCheckJs(source, res, ruleData: book);
    _checkRedirect(source, res);
    _checkLoginRequired(res, stage: 'detail');

    final parsed = await BookInfoParser.parse(
      source: source,
      book: book,
      body: res.body,
      baseUrl: res.url,
    );
    parsed.infoHtml = res.body;
    if (parsed.tocUrl.isEmpty || parsed.tocUrl == parsed.bookUrl) {
      parsed.tocHtml = res.body;
    }
    return parsed;
  }

  /// 獲取目錄列表 (對標 getChapterListAwait / BookChapterList.analyzeChapterList)
  /// 支援 nextTocUrl 多頁目錄自動翻頁、isReverse、去重、formatJs、並發抓取
  static Future<List<BookChapter>> getChapterListAwait(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    final effectivePageConcurrency = pageConcurrency ?? _pageConcurrency;
    final rule = AnalyzeRule(source: source, ruleData: book);
    try {
      await rule.preUpdateToc();

      final allChapters = <BookChapter>[];
      final visitedUrls = <String>{};
      var isReverse = false;
      // tocUrl 為空時以 bookUrl 作為備用 (對標 Android 邏輯)
      final initialUrl = book.tocUrl.isNotEmpty ? book.tocUrl : book.bookUrl;

      // 1. 抓取首頁目錄
      visitedUrls.add(initialUrl);
      final firstRes = await _loadInitialTocResponse(
        source: source,
        book: book,
        initialUrl: initialUrl,
        cancelToken: cancelToken,
      );

      final firstResult = await ChapterListParser.parse(
        source: source,
        book: book,
        body: firstRes.body,
        baseUrl: firstRes.url,
        maxChapters: chapterLimit,
      );
      isReverse = firstResult.isReverse;
      allChapters.addAll(firstResult.chapters);

      if (chapterLimit == null || allChapters.length < chapterLimit) {
        if (firstResult.nextUrls.length > 1) {
          // 多 nextUrl → 並發抓取剩餘頁 (對標 Android mapAsync)
          final pending =
              firstResult.nextUrls
                  .where((u) => visitedUrls.add(u))
                  .take(_maxTocPages - 1)
                  .toList();
          final responses = await _fetchParallel(
            pending,
            source,
            book,
            stage: 'toc',
            allowPartial: true,
            concurrency: effectivePageConcurrency,
            cancelToken: cancelToken,
          );
          for (var i = 0; i < responses.length; i++) {
            if (chapterLimit != null && allChapters.length >= chapterLimit) {
              break;
            }
            final res = responses[i];
            if (res == null) continue;
            final pageResult = await ChapterListParser.parse(
              source: source,
              book: book,
              body: res.body,
              baseUrl: res.url,
              maxChapters:
                  chapterLimit == null
                      ? null
                      : chapterLimit - allChapters.length,
            );
            allChapters.addAll(pageResult.chapters);
            // 並發模式下忽略二級 nextUrls (對標 Android getNextPageUrl=false)
          }
        } else {
          // 單 nextUrl → daisy chain 循序抓取
          String? currentUrl =
              firstResult.nextUrls.isNotEmpty
                  ? firstResult.nextUrls.first
                  : null;
          for (
            var pageNum = 1;
            pageNum < _maxTocPages && currentUrl != null;
            pageNum++
          ) {
            if (chapterLimit != null && allChapters.length >= chapterLimit) {
              break;
            }
            if (!visitedUrls.add(currentUrl)) break;

            final analyzeUrl = await AnalyzeUrl.create(
              currentUrl,
              source: source,
              ruleData: book,
            );
            var res = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
            res = _runLoginCheckJs(source, res, ruleData: book);
            _checkRedirect(source, res);
            _checkLoginRequired(res, stage: 'toc');

            final result = await ChapterListParser.parse(
              source: source,
              book: book,
              body: res.body,
              baseUrl: res.url,
              maxChapters:
                  chapterLimit == null
                      ? null
                      : (chapterLimit - allChapters.length),
            );
            allChapters.addAll(result.chapters);
            currentUrl =
                result.nextUrls.isNotEmpty ? result.nextUrls.first : null;
          }
        }
      }

      // isReverse == false → Android 會將整列表 reverse (預設來源為逆序)
      // isReverse == true  → 來源已是順序，保持不變
      if (!isReverse && allChapters.length > 1) {
        final reversed = allChapters.reversed.toList();
        allChapters
          ..clear()
          ..addAll(reversed);
      }

      // 依 url 去重並保持順序 (對標 Android LinkedHashSet(chapterList))
      final seen = <String>{};
      final deduped = <BookChapter>[];
      for (final c in allChapters) {
        if (seen.add(c.url)) deduped.add(c);
      }

      // formatJs (對標 Android BookChapterList.formatJs)
      final formatJs = source.ruleToc?.formatJs;
      if (formatJs != null && formatJs.isNotEmpty) {
        for (var i = 0; i < deduped.length; i++) {
          final ch = deduped[i];
          AnalyzeRule? fmtRule;
          try {
            // 透過 AnalyzeRule 的 evalJS 管道執行 formatJs，
            // 以 chapter title 作為 result 傳入，方便 JS 存取原標題。
            // 同時以 evalJS 內部機制注入 index / title 作為全域變數。
            fmtRule = AnalyzeRule(
              source: source,
              ruleData: book,
            ).setChapter(ch);
            fmtRule.page = i + 1;
            final newTitle = await fmtRule.evalJSAsync(formatJs, ch.title);
            if (newTitle != null && newTitle.toString().isNotEmpty) {
              deduped[i] = ch.copyWith(title: newTitle.toString());
            }
          } catch (_) {
            // 格式化失敗則保留原標題
          } finally {
            fmtRule?.dispose();
          }
        }
      }

      // legado 會在書源規則歸一後，再依 book.reverseToc 決定最終顯示順序。
      // 預設 reverseToc=false，因此會再 reverse 一次，讓大多數來源維持正序。
      final reverseToc = book.readConfig?.reverseToc ?? false;
      if (!reverseToc && deduped.length > 1) {
        final finalOrder = deduped.reversed.toList();
        deduped
          ..clear()
          ..addAll(finalOrder);
      }

      // 重新編號所有章節
      for (var i = 0; i < deduped.length; i++) {
        deduped[i] = deduped[i].copyWith(index: i);
      }

      // 從既有的 DB 資料回填 wordCount (對標 Android BookChapterList.getWordCount)
      await _fillWordCount(deduped, book);

      return deduped;
    } finally {
      rule.dispose();
    }
  }

  /// 獲取正文內容 (對標 getContentAwait / BookContent.analyzeContent)
  /// 支援 nextContentUrl 多頁正文自動翻頁、並發抓取
  static Future<String> getContentAwait(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    final effectivePageConcurrency = pageConcurrency ?? _pageConcurrency;
    final contentParts = <String>[];
    final visitedUrls = <String>{};
    String? lastBaseUrl;

    // 1. 抓取首頁正文
    visitedUrls.add(chapter.url);
    final firstAnalyzeUrl = await AnalyzeUrl.create(
      chapter.url,
      source: source,
      ruleData: book,
    );
    var firstRes = await firstAnalyzeUrl.getStrResponse(
      cancelToken: cancelToken,
    );
    firstRes = _runLoginCheckJs(source, firstRes, ruleData: book);
    _checkRedirect(source, firstRes);
    _checkLoginRequired(firstRes, stage: 'content');

    final firstResult = await ContentParser.parse(
      source: source,
      book: book,
      chapter: chapter,
      body: firstRes.body,
      baseUrl: firstRes.url,
      nextChapterUrl: nextChapterUrl,
    );
    if (firstResult.content.isNotEmpty) {
      contentParts.add(firstResult.content);
    }
    lastBaseUrl = firstRes.url;

    if (firstResult.nextUrls.length > 1) {
      // 多 nextUrl → 並發抓取 (對標 Android BookContent mapAsync)
      final pending =
          firstResult.nextUrls
              .where((u) => visitedUrls.add(u))
              .take(_maxContentPages - 1)
              .toList();
      final responses = await _fetchParallel(
        pending,
        source,
        book,
        stage: 'content',
        allowPartial: false,
        concurrency: effectivePageConcurrency,
        cancelToken: cancelToken,
      );
      for (var i = 0; i < responses.length; i++) {
        final res = responses[i];
        if (res == null) continue;
        final pageResult = await ContentParser.parse(
          source: source,
          book: book,
          chapter: chapter,
          body: res.body,
          baseUrl: res.url,
          nextChapterUrl: nextChapterUrl,
        );
        if (pageResult.content.isNotEmpty) {
          contentParts.add(pageResult.content);
        }
        lastBaseUrl = res.url;
      }
    } else {
      // 單 nextUrl → daisy chain 循序抓取
      String? currentUrl =
          firstResult.nextUrls.isNotEmpty ? firstResult.nextUrls.first : null;
      for (
        var pageNum = 1;
        pageNum < _maxContentPages && currentUrl != null;
        pageNum++
      ) {
        if (!visitedUrls.add(currentUrl)) break;

        final analyzeUrl = await AnalyzeUrl.create(
          currentUrl,
          source: source,
          ruleData: book,
        );
        var res = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
        res = _runLoginCheckJs(source, res, ruleData: book);
        _checkRedirect(source, res);
        _checkLoginRequired(res, stage: 'content');

        final result = await ContentParser.parse(
          source: source,
          book: book,
          chapter: chapter,
          body: res.body,
          baseUrl: res.url,
          nextChapterUrl: nextChapterUrl,
        );
        if (result.content.isNotEmpty) {
          contentParts.add(result.content);
        }
        lastBaseUrl = res.url;
        currentUrl = result.nextUrls.isNotEmpty ? result.nextUrls.first : null;
      }
    }

    // 合併並執行最終 replaceRegex 清理 (對標 Android BookContent 尾段)
    final joined = contentParts.join('\n');
    return ContentParser.finalizeContent(
      source: source,
      book: book,
      chapter: chapter,
      contentStr: joined,
      baseUrl: lastBaseUrl,
    );
  }

  /// 執行登入檢查 JS Hook (統一抽取)
  static StrResponse _runLoginCheckJs(
    BookSource source,
    StrResponse res, {
    dynamic ruleData,
  }) {
    final checkJs = source.loginCheckJs;
    if (checkJs != null && checkJs.isNotEmpty) {
      final rule = AnalyzeRule(source: source, ruleData: ruleData);
      try {
        final evalRes = rule.evalJS(checkJs, res);
        if (evalRes is StrResponse) {
          return evalRes;
        }
      } finally {
        rule.dispose();
      }
    }
    return res;
  }

  /// 重定向檢查 (對標 Android WebBook.checkRedirect)
  static void _checkRedirect(BookSource source, StrResponse res) {
    if (res.isRedirect) {
      AppLog.d('WebBook: 偵測到重定向 → ${res.url}');
    }
  }

  static void _checkLoginRequired(StrResponse res, {required String stage}) {
    final normalized = '${res.url}\n${res.body}'.trim().toLowerCase();
    if (normalized.isEmpty) return;
    if (!_looksLikeLoginRequired(normalized)) return;
    throw LoginCheckException(_loginRequiredMessage(stage), sourceUrl: res.url);
  }

  static bool _looksLikeLoginRequired(String normalized) {
    return normalized.contains('permissionlimit') ||
        normalized.contains('loginrequired') ||
        normalized.contains('需要你登录后阅读') ||
        normalized.contains('需要你登入後閱讀') ||
        normalized.contains('登录后阅读') ||
        normalized.contains('登入後閱讀') ||
        normalized.contains('請先登錄') ||
        normalized.contains('请先登录');
  }

  static String _loginRequiredMessage(String stage) {
    switch (stage) {
      case 'content':
        return '正文需要登入後閱讀';
      case 'toc':
        return '目錄需要登入後閱讀';
      case 'detail':
        return '詳情需要登入後閱讀';
      default:
        return '書源需要登入後使用';
    }
  }

  /// 以有上限的並發抓取多個 URL 並依輸入順序回傳 StrResponse
  /// (對標 Android flow.mapAsync(threadCount))
  static Future<List<StrResponse?>> _fetchParallel(
    List<String> urls,
    BookSource source,
    Book book, {
    required String stage,
    required bool allowPartial,
    int concurrency = _pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    if (urls.isEmpty) return const [];
    final sem = _Semaphore(concurrency);
    final futures =
        urls.map((url) async {
          await sem.acquire();
          try {
            final analyzeUrl = await AnalyzeUrl.create(
              url,
              source: source,
              ruleData: book,
            );
            var res = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
            res = _runLoginCheckJs(source, res, ruleData: book);
            _checkRedirect(source, res);
            _checkLoginRequired(res, stage: stage);
            return res;
          } catch (e) {
            AppLog.e('WebBook: 並發抓取失敗 $url: $e');
            if (!allowPartial) rethrow;
            return null;
          } finally {
            sem.release();
          }
        }).toList();
    return Future.wait(futures);
  }

  static Future<StrResponse> _loadInitialTocResponse({
    required BookSource source,
    required Book book,
    required String initialUrl,
    CancelToken? cancelToken,
  }) async {
    final cachedBody =
        (book.tocHtml != null && book.tocHtml!.isNotEmpty)
            ? book.tocHtml
            : (initialUrl == book.bookUrl &&
                book.infoHtml != null &&
                book.infoHtml!.isNotEmpty)
            ? book.infoHtml
            : null;
    if (cachedBody != null && cachedBody.isNotEmpty) {
      return StrResponse(
        url: initialUrl,
        body: cachedBody,
        headers: const <String, List<String>>{},
        raw: Response(
          requestOptions: RequestOptions(path: initialUrl),
          data: cachedBody,
        ),
      );
    }

    final analyzeUrl = await AnalyzeUrl.create(
      initialUrl,
      source: source,
      ruleData: book,
    );
    var res = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
    res = _runLoginCheckJs(source, res, ruleData: book);
    _checkRedirect(source, res);
    _checkLoginRequired(res, stage: 'toc');
    return res;
  }

  /// 以檔名為鍵，從 DAO 讀回既有章節的 wordCount
  /// (對標 Android BookChapterList.getWordCount)
  static Future<void> _fillWordCount(List<BookChapter> list, Book book) async {
    try {
      final dao = getIt<ChapterDao>();
      final existing = await dao.getByBook(book.bookUrl);
      if (existing.isEmpty) return;
      final wordCountMap = <String, String?>{
        for (final e in existing)
          if (e.wordCount != null && e.wordCount!.isNotEmpty)
            e.getFileName(): e.wordCount,
      };
      if (wordCountMap.isEmpty) return;
      for (var i = 0; i < list.length; i++) {
        final wc = wordCountMap[list[i].getFileName()];
        if (wc != null && wc.isNotEmpty && list[i].wordCount == null) {
          list[i] = list[i].copyWith(wordCount: wc);
        }
      }
    } catch (e) {
      AppLog.e('WebBook: 回填 wordCount 失敗: $e');
    }
  }
}

/// 簡易信號量 (Semaphore) — 用於限制並發上限
class _Semaphore {
  _Semaphore(this._max);
  final int _max;
  int _current = 0;
  final Queue<Completer<void>> _waiters = Queue();

  Future<void> acquire() {
    if (_current < _max) {
      _current++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else if (_current > 0) {
      _current--;
    }
  }
}

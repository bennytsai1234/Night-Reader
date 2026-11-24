import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/js/legacy_js_syntax.dart';
import 'package:night_reader/core/engine/rule_data_fields.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/engine/web_book/login_wall.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/network/str_response.dart';

/// WebBook - 書源抓取業務調度 (對標 Android model/webBook/WebBook.kt)
///
/// 抓取與解析在呼叫它的 isolate 執行，平常是書源 isolate（`SourceIsolate`，
/// ADR 0028；呼叫端經過 `BookSourceService`）。規則的 JS 會經由 `java.*` 用到
/// 網路、資料庫與 Cookie。
class WebBook {
  WebBook._();

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

    final analyzeUrl = AnalyzeUrl(
      searchUrl,
      source: source,
      key: key,
      page: page,
    );

    var res = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
    res = runLoginCheckJs(analyzeUrl, res);
    _checkRedirect(source, res);

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
    final analyzeUrl = AnalyzeUrl(url, source: source, page: page);
    var res = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
    res = runLoginCheckJs(analyzeUrl, res);
    _checkRedirect(source, res);

    final results = await BookListParser.parse(
      source: source,
      body: res.body,
      baseUrl: res.url,
      isSearch: false,
    );
    return results;
  }

  /// 獲取書籍資訊 (對標 getBookInfoAwait)
  static Future<Book> getBookInfoAwait(
    BookSource source,
    Book book, {
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

    final analyzeUrl = AnalyzeUrl(book.bookUrl, source: source, ruleData: book);
    var res = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
    res = runLoginCheckJs(analyzeUrl, res);
    _checkRedirect(source, res);

    final parsed = await BookInfoParser.parse(
      source: source,
      book: book,
      body: res.body,
      baseUrl: book.bookUrl,
      redirectUrl: res.url,
    );
    parsed.infoHtml = res.body;
    if (parsed.tocUrl.isEmpty || parsed.tocUrl == parsed.bookUrl) {
      parsed.tocHtml = res.body;
    }
    return parsed;
  }

  /// 獲取目錄列表 (對標 getChapterListAwait / BookChapterList.analyzeChapterList)
  /// 支援 nextTocUrl 多頁目錄自動翻頁、isReverse、去重、formatJs、並發抓取
  ///
  /// 並發抓取的目錄分頁預設略過抓不到的頁，先給出能讀的部分；[requireComplete]
  /// 時任一頁失敗就整個失敗，給要拿結果整份替換已存目錄的呼叫端用。
  static Future<List<BookChapter>> getChapterListAwait(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
    bool requireComplete = false,
  }) async {
    final effectivePageConcurrency = pageConcurrency ?? _pageConcurrency;
    final rule = AnalyzeRule(source: source, ruleData: book);
    try {
      // 預整理 JS 呼叫了 java.refreshTocUrl()：重讀書籍詳情，目錄從新的
      // 目錄網址抓（同 Legado）。剛讀過詳情的書帶著詳情頁，直接重新解析。
      // 結果寫回同一本書：呼叫端照這本書抄回規則改過的欄位與變數。
      if (rule.preUpdateToc()) {
        final refreshed = await getBookInfoAwait(
          source,
          book,
          cancelToken: cancelToken,
        );
        for (final field in bookRuleFields.values) {
          field.write(book, field.read(refreshed));
        }
        book
          ..infoHtml = refreshed.infoHtml
          ..tocHtml = refreshed.tocHtml;
      }

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
        baseUrl: initialUrl,
        redirectUrl: firstRes.url,
        maxChapters: chapterLimit,
      );
      LoginWall.checkToc(
        firstRes,
        empty: firstResult.chapters.isEmpty && firstResult.nextUrls.isEmpty,
      );
      isReverse = firstResult.isReverse;
      allChapters.addAll(firstResult.chapters);

      if (chapterLimit == null || allChapters.length < chapterLimit) {
        if (firstResult.nextUrls.length > 1) {
          // 多 nextUrl → 並發抓取剩餘頁 (對標 Android mapAsync)
          final pending = firstResult.nextUrls
              .where((u) => visitedUrls.add(u))
              .toList();
          final responses = await _fetchParallel(
            pending,
            source,
            book,
            allowPartial: !requireComplete,
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
              baseUrl: pending[i],
              redirectUrl: res.url,
              maxChapters: chapterLimit == null
                  ? null
                  : chapterLimit - allChapters.length,
            );
            // 要整份目錄時，後面哪一頁被登入牆擋住就整份失敗；其他時候照
            // 抓不到的頁略過，先給讀得到的部分。
            if (requireComplete) {
              LoginWall.checkToc(res, empty: pageResult.chapters.isEmpty);
            }
            allChapters.addAll(pageResult.chapters);
            // 並發模式下忽略二級 nextUrls (對標 Android getNextPageUrl=false)
          }
        } else {
          // 單 nextUrl → daisy chain 循序抓取，同 Legado 不限頁數：抓到沒有
          // 下一頁、或下一頁抓過了為止。
          String? currentUrl = firstResult.nextUrls.isNotEmpty
              ? firstResult.nextUrls.first
              : null;
          while (currentUrl != null) {
            if (chapterLimit != null && allChapters.length >= chapterLimit) {
              break;
            }
            if (!visitedUrls.add(currentUrl)) break;

            final analyzeUrl = AnalyzeUrl(
              currentUrl,
              source: source,
              ruleData: book,
            );
            var res = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
            res = runLoginCheckJs(analyzeUrl, res);
            _checkRedirect(source, res);

            final result = await ChapterListParser.parse(
              source: source,
              book: book,
              body: res.body,
              baseUrl: currentUrl,
              redirectUrl: res.url,
              maxChapters: chapterLimit == null
                  ? null
                  : (chapterLimit - allChapters.length),
            );
            if (requireComplete) {
              LoginWall.checkToc(res, empty: result.chapters.isEmpty);
            }
            allChapters.addAll(result.chapters);
            currentUrl = result.nextUrls.isNotEmpty
                ? result.nextUrls.first
                : null;
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

      // A title is a label, not content identity. Different URLs remain
      // distinct until the source provides evidence that they are duplicates;
      // guessing from adjacent names can irreversibly delete real chapters.

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

      _formatTitles(source, book, deduped);

      // 從既有的 DB 資料回填 wordCount (對標 Android BookChapterList.getWordCount)
      await _fillWordCount(deduped, book);

      return deduped;
    } finally {
      rule.dispose();
    }
  }

  /// 目錄的 `formatJs`，同 Legado `BookChapterList.analyzeChapterList`：目錄
  /// 排成最後的順序、編好號之後逐章跑，`index` 從 1 起、`title` 是原章名、
  /// `chapter` 是這一章，`gInt` 是整份目錄共用、從 0 起的計數。傳回值不是
  /// 空的就是新的章名；某一章出錯時那一章留著原章名。
  ///
  /// `index`、`gInt` 宣告成包住書源程式的區域變數，再用 `eval` 跑書源的程式：
  /// 規則 JS 結束時會清掉新增的全域變數，`gInt` 照這樣一章一章傳下去。
  static void _formatTitles(
    BookSource source,
    Book book,
    List<BookChapter> chapters,
  ) {
    final formatJs = source.ruleToc?.formatJs;
    if (formatJs == null || formatJs.trim().isEmpty) return;
    final code = jsonEncode(LegacyJsSyntax.normalize(formatJs));
    final rule = AnalyzeRule(source: source, ruleData: book);
    try {
      Object? gInt = 0;
      for (var i = 0; i < chapters.length; i++) {
        final chapter = chapters[i];
        try {
          // `page` 是夜讀原本給的序號（Legado 沒有這個變數），照舊給。
          rule
            ..setChapter(chapter)
            ..page = i + 1;
          final out = rule.evalJS(
            'var index = ${i + 1}; var gInt = ${jsonEncode(gInt)};'
            ' var __lrTitle = eval($code);'
            ' JSON.stringify([__lrTitle == null ? null : String(__lrTitle), gInt])',
            chapter.title,
          );
          final [title, counter] = jsonDecode('$out') as List;
          gInt = counter;
          if (title is String && title.isNotEmpty) {
            chapters[i] = chapter.copyWith(title: title);
          }
        } on AppException catch (error, stackTrace) {
          AppLog.e(
            '目錄 formatJs 規則失敗，保留原標題',
            error: error,
            stackTrace: stackTrace,
          );
        } on TimeoutException catch (error, stackTrace) {
          AppLog.e(
            '目錄 formatJs 執行逾時，保留原標題',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    } finally {
      rule.dispose();
    }
  }

  /// 重定向檢查 (對標 Android WebBook.checkRedirect)
  static void _checkRedirect(BookSource source, StrResponse res) {
    if (res.isRedirect) {
      AppLog.d('WebBook: 偵測到重定向 → ${res.url}');
    }
  }

  /// 以有上限的並發抓取多個 URL 並依輸入順序回傳 StrResponse
  /// (對標 Android flow.mapAsync(threadCount))
  static Future<List<StrResponse?>> _fetchParallel(
    List<String> urls,
    BookSource source,
    Book book, {
    required bool allowPartial,
    int concurrency = _pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    if (urls.isEmpty) return const [];
    final sem = _Semaphore(concurrency);
    final futures = urls.map((url) async {
      await sem.acquire();
      try {
        final analyzeUrl = AnalyzeUrl(url, source: source, ruleData: book);
        var res = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
        res = runLoginCheckJs(analyzeUrl, res);
        _checkRedirect(source, res);
        return res;
      } on DioException catch (error, stackTrace) {
        if (CancelToken.isCancel(error)) rethrow;
        AppLog.e(
          'WebBook: 並發網路抓取失敗 $url',
          error: error,
          stackTrace: stackTrace,
        );
        if (!allowPartial) rethrow;
        return null;
      } on AppException catch (error, stackTrace) {
        AppLog.e(
          'WebBook: 並發書源資料取得失敗 $url',
          error: error,
          stackTrace: stackTrace,
        );
        if (!allowPartial) rethrow;
        return null;
      } on TimeoutException catch (error, stackTrace) {
        AppLog.e(
          'WebBook: 並發書源資料取得逾時 $url',
          error: error,
          stackTrace: stackTrace,
        );
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
    final cachedBody = (book.tocHtml != null && book.tocHtml!.isNotEmpty)
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
          requestOptions: StrResponse.requestFor(initialUrl),
          data: cachedBody,
        ),
      );
    }

    final analyzeUrl = AnalyzeUrl(initialUrl, source: source, ruleData: book);
    var res = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
    res = runLoginCheckJs(analyzeUrl, res);
    _checkRedirect(source, res);
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

import 'dart:collection';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/web_book/content_parser.dart';
import 'package:night_reader/core/engine/web_book/login_wall.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/source/source_interaction.dart';

/// 正文完整性優先的抓取器。
///
/// 所有 nextContentUrl 都必須完整走完才回傳成功；多個下一頁會以有限併發抓取，
/// 任一頁失敗即讓整章失敗，避免把半章寫入快取。
final class CompleteContentFetcher {
  CompleteContentFetcher._();

  /// 照 Legado：下一頁網址出現過、或就是下一章（[_storedNextChapterUrl]）
  /// 就停。Legado 沒有頁數上限；夜讀的書架自動下載沒人看著，規則一直給新
  /// 網址時會抓不完，留一個正常章節碰不到的上限（2026-11-13 环安小说网一章
  /// 110 到 121 頁，ADR 0072）。
  static const int _maxPages = 1000;
  static const int _defaultPageConcurrency = 4;

  static Future<String> fetch(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    final stopAt = (nextChapterUrl == null || nextChapterUrl.isEmpty)
        ? await _storedNextChapterUrl(book, chapter)
        : nextChapterUrl;
    final contentParts = <String>[];
    final queuedUrls = <String>{chapter.url};
    final pendingUrls = ListQueue<String>()..add(chapter.url);
    final concurrency = math.max(1, pageConcurrency ?? _defaultPageConcurrency);
    String? firstRedirectUrl;
    var fetchedPages = 0;

    while (pendingUrls.isNotEmpty) {
      final remainingPages = _maxPages - fetchedPages;
      if (remainingPages <= 0) {
        throw SourceException(
          '正文分頁超過 $_maxPages 頁，拒絕保存可能不完整的章節',
          sourceUrl: pendingUrls.first,
        );
      }

      final batchSize = math.min(
        math.min(concurrency, pendingUrls.length),
        remainingPages,
      );
      final batchUrls = <String>[
        for (var i = 0; i < batchSize; i++) pendingUrls.removeFirst(),
      ];
      final pages = await Future.wait(
        batchUrls.map(
          (url) => _fetchPage(
            source,
            book,
            chapter,
            url,
            nextChapterUrl: stopAt,
            cancelToken: cancelToken,
          ),
        ),
      );

      fetchedPages += pages.length;
      for (final page in pages) {
        if (page.content.isNotEmpty) contentParts.add(page.content);
        firstRedirectUrl ??= page.baseUrl;
        for (final nextUrl in page.nextUrls) {
          if (queuedUrls.add(nextUrl)) pendingUrls.add(nextUrl);
        }
      }
    }

    final joined = contentParts.join('\n');
    final content = await ContentParser.finalizeContent(
      source: source,
      book: book,
      chapter: chapter,
      contentStr: joined,
      // 同 Legado BookContent 尾段：baseUrl 是章節網址、redirectUrl 是第一頁
      // 轉址後的網址，不是最後一頁的。
      baseUrl: chapter.url,
      redirectUrl: firstRedirectUrl,
    );
    LoginWall.checkContent(null, content);
    return content;
  }

  /// 沒給下一章網址時（書架自動下載、漫畫、有聲書），同 Legado `BookContent`
  /// 查這本書存著的目錄：下一章，沒有就第一章。「下一頁」規則抓到下一章的
  /// 連結時靠它停在本章，不把後面整本接進來。不在書架上的書沒有存目錄。
  static Future<String?> _storedNextChapterUrl(
    Book book,
    BookChapter chapter,
  ) async {
    if (!getIt.isRegistered<ChapterDao>()) return null;
    final chapters = getIt<ChapterDao>();
    try {
      return (await chapters.getChapter(
            book.bookUrl,
            chapter.index + 1,
          ))?.url ??
          (await chapters.getChapter(book.bookUrl, 0))?.url;
    } on Object catch (error) {
      // 停點只是多一道擋：讀不到目錄就照沒有停點抓，不讓這一章因此失敗。
      AppLog.w('正文：讀不到存著的目錄當停點：$error');
      return null;
    }
  }

  /// 抓一頁正文。這一頁的書源程式要使用者驗證而被擋下、這一頁因此失敗或
  /// 是空的，整章照「需要在網頁上驗證」失敗（ADR 0038），和登入牆一樣不存
  /// 半章。
  static Future<_FetchedContentPage> _fetchPage(
    BookSource source,
    Book book,
    BookChapter chapter,
    String url, {
    String? nextChapterUrl,
    CancelToken? cancelToken,
  }) => SourceInteraction.watchVerification(
    () => _fetchPageContent(
      source,
      book,
      chapter,
      url,
      nextChapterUrl: nextChapterUrl,
      cancelToken: cancelToken,
    ),
    gotNothing: (page) => page.content.trim().isEmpty,
    cancelToken: cancelToken,
  );

  static Future<_FetchedContentPage> _fetchPageContent(
    BookSource source,
    Book book,
    BookChapter chapter,
    String url, {
    String? nextChapterUrl,
    CancelToken? cancelToken,
  }) async {
    // 同 Legado `WebBook.getContentAwait`：章節網址那一頁照正文規則的
    // `webJs`、`sourceRegex` 抓（網址開了 webView 才用得到），也從它取章名
    // （`title`）；下一頁照一般的請求抓。
    final firstPage = url == chapter.url;
    final contentRule = source.ruleContent;
    final analyzeUrl = AnalyzeUrl(url, source: source, ruleData: book);
    var response = await analyzeUrl.getStrResponse(
      cancelToken: cancelToken,
      jsStr: firstPage ? contentRule?.webJs : null,
      sourceRegex: firstPage ? contentRule?.sourceRegex : null,
    );
    response = runLoginCheckJs(analyzeUrl, response);

    final result = await ContentParser.parse(
      source: source,
      book: book,
      chapter: chapter,
      body: response.body,
      baseUrl: url,
      redirectUrl: response.url,
      nextChapterUrl: nextChapterUrl,
      readTitle: firstPage,
    );
    // 任何一頁被登入牆擋住，整章失敗，不存半章。
    LoginWall.checkContent(response, result.content);
    return _FetchedContentPage(
      content: result.content,
      nextUrls: result.nextUrls,
      baseUrl: response.url,
    );
  }
}

class _FetchedContentPage {
  const _FetchedContentPage({
    required this.content,
    required this.nextUrls,
    required this.baseUrl,
  });

  final String content;
  final List<String> nextUrls;
  final String baseUrl;
}

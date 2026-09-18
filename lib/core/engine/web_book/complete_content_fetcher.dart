import 'dart:collection';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/web_book/content_parser.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/network/str_response.dart';

/// 正文完整性優先的抓取器。
///
/// 所有 nextContentUrl 都必須完整走完才回傳成功；多個下一頁會以有限併發抓取，
/// 任一頁失敗即讓整章失敗，避免把半章寫入快取。
final class CompleteContentFetcher {
  CompleteContentFetcher._();

  static const int _maxPages = 100;
  static const int _defaultPageConcurrency = 4;

  static Future<String> fetch(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    final contentParts = <String>[];
    final queuedUrls = <String>{chapter.url};
    final pendingUrls = ListQueue<String>()..add(chapter.url);
    final concurrency = math.max(1, pageConcurrency ?? _defaultPageConcurrency);
    String? lastBaseUrl;
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
            nextChapterUrl: nextChapterUrl,
            cancelToken: cancelToken,
          ),
        ),
      );

      fetchedPages += pages.length;
      for (final page in pages) {
        if (page.content.isNotEmpty) contentParts.add(page.content);
        lastBaseUrl = page.baseUrl;
        for (final nextUrl in page.nextUrls) {
          if (queuedUrls.add(nextUrl)) pendingUrls.add(nextUrl);
        }
      }
    }

    final joined = contentParts.join('\n');
    return ContentParser.finalizeContent(
      source: source,
      book: book,
      chapter: chapter,
      contentStr: joined,
      baseUrl: lastBaseUrl,
    );
  }

  static Future<_FetchedContentPage> _fetchPage(
    BookSource source,
    Book book,
    BookChapter chapter,
    String url, {
    String? nextChapterUrl,
    CancelToken? cancelToken,
  }) async {
    final analyzeUrl = await AnalyzeUrl.create(
      url,
      source: source,
      ruleData: book,
    );
    var response = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
    response = _runLoginCheckJs(source, response, ruleData: book);
    _checkLoginRequired(response);

    final result = await ContentParser.parse(
      source: source,
      book: book,
      chapter: chapter,
      body: response.body,
      baseUrl: response.url,
      nextChapterUrl: nextChapterUrl,
    );
    return _FetchedContentPage(
      content: result.content,
      nextUrls: result.nextUrls,
      baseUrl: response.url,
    );
  }

  static StrResponse _runLoginCheckJs(
    BookSource source,
    StrResponse response, {
    dynamic ruleData,
  }) {
    final checkJs = source.loginCheckJs;
    if (checkJs == null || checkJs.isEmpty) return response;
    final rule = AnalyzeRule(source: source, ruleData: ruleData);
    try {
      final evaluated = rule.evalJS(checkJs, response);
      return evaluated is StrResponse ? evaluated : response;
    } finally {
      rule.dispose();
    }
  }

  static void _checkLoginRequired(StrResponse response) {
    final normalized = '${response.url}\n${response.body}'.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final requiresLogin =
        normalized.contains('permissionlimit') ||
        normalized.contains('loginrequired') ||
        normalized.contains('需要你登录后阅读') ||
        normalized.contains('需要你登入後閱讀') ||
        normalized.contains('登录后阅读') ||
        normalized.contains('登入後閱讀') ||
        normalized.contains('請先登錄') ||
        normalized.contains('请先登录');
    if (requiresLogin) {
      throw LoginCheckException('正文需要登入後閱讀', sourceUrl: response.url);
    }
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

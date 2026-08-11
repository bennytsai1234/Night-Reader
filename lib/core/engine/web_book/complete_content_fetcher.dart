import 'dart:collection';

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
/// 舊流程到達固定頁數上限時會直接把已抓到的前半段當成功正文回傳；
/// 這裡改成只在 nextContentUrl 真正走完時才回傳成功。若仍有下一頁但已
/// 達安全上限，直接失敗，讓上層重試／顯示失敗，不把半章寫入快取。
final class CompleteContentFetcher {
  CompleteContentFetcher._();

  static const int _maxPages = 100;

  static Future<String> fetch(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    CancelToken? cancelToken,
  }) async {
    final contentParts = <String>[];
    final visitedUrls = <String>{};
    final pendingUrls = ListQueue<String>()..add(chapter.url);
    String? lastBaseUrl;
    var fetchedPages = 0;

    while (pendingUrls.isNotEmpty) {
      if (fetchedPages >= _maxPages) {
        throw SourceException(
          '正文分頁超過 $_maxPages 頁，拒絕保存可能不完整的章節',
          sourceUrl: pendingUrls.first,
        );
      }

      final currentUrl = pendingUrls.removeFirst();
      if (!visitedUrls.add(currentUrl)) continue;

      final analyzeUrl = await AnalyzeUrl.create(
        currentUrl,
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
      fetchedPages += 1;
      if (result.content.isNotEmpty) contentParts.add(result.content);
      lastBaseUrl = response.url;

      for (final nextUrl in result.nextUrls) {
        if (!visitedUrls.contains(nextUrl)) pendingUrls.add(nextUrl);
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

import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/utils/html_formatter.dart';
import 'package:night_reader/core/utils/network_utils.dart';

/// 正文解析結果
class ContentResult {
  final String content;

  /// 下一頁正文 URL 清單 (對標 Android BookContent.analyzeContent 返回的 nextUrlList)
  /// - 長度 0：沒有下一頁
  /// - 長度 1：daisy-chain
  /// - 長度 > 1：可並發
  final List<String> nextUrls;

  const ContentResult({required this.content, this.nextUrls = const []});
}

class ContentParser {
  /// 解析正文頁，返回正文內容與下一頁 URL
  /// (對標 Android BookContent.analyzeContent)
  static Future<ContentResult> parse({
    required BookSource source,
    Book? book,
    BookChapter? chapter,
    required String body,
    required String baseUrl,
    String? redirectUrl,
    String? nextChapterUrl,
    bool keepImages = false,
  }) async {
    // [baseUrl] 是請求這一頁的網址，[redirectUrl] 是網站轉址後回應的網址
    // （同 Legado）；沒給時是同一個。
    final pageUrl = redirectUrl ?? baseUrl;
    final rule = AnalyzeRule(source: source, ruleData: book)
        .setContent(body, baseUrl: baseUrl, redirectUrl: pageUrl)
        .setChapter(chapter)
        .setNextChapterUrl(nextChapterUrl);

    try {
      final contentRule = source.ruleContent;
      if (contentRule == null) return const ContentResult(content: '');

      var content = rule.getString(contentRule.content ?? '', unescape: false);

      if (content.contains('&')) {
        content = AnalyzeRuleBase.htmlUnescape.convert(content);
      }
      // 閱讀用的正文只留文字；書源校驗要看正文是不是圖片才判斷得出漫畫源
      // （ADR 0051），所以可以要求留下圖片。
      content = keepImages
          ? HtmlFormatter.formatKeepImg(content, redirectUrl: pageUrl)
          : HtmlFormatter.format(content);

      final nextUrls = <String>[];
      if (contentRule.nextContentUrl != null &&
          contentRule.nextContentUrl!.isNotEmpty) {
        final list = rule.getStringList(
          contentRule.nextContentUrl!,
          isUrl: true,
        );
        for (final u in list) {
          if (u.isEmpty || u == pageUrl) continue;
          if (nextChapterUrl != null) {
            final absNext = NetworkUtils.getAbsoluteURL(pageUrl, u);
            final absChapter = NetworkUtils.getAbsoluteURL(
              pageUrl,
              nextChapterUrl,
            );
            if (absNext == absChapter) continue;
          }
          nextUrls.add(u);
        }
      }

      return ContentResult(content: content, nextUrls: nextUrls);
    } finally {
      rule.dispose();
    }
  }

  /// 多頁正文合併後的最終替換清理 (對標 Android BookContent.analyzeContent 尾段)
  /// replaceRegex 走 AnalyzeRule.getString，內嵌的 @js: / {{js}} 照樣執行
  static Future<String> finalizeContent({
    required BookSource source,
    Book? book,
    BookChapter? chapter,
    required String contentStr,
    String? baseUrl,
    String? redirectUrl,
  }) async {
    if (contentStr.trim().isEmpty) return '';
    final replaceRegex = source.ruleContent?.replaceRegex;
    if (replaceRegex == null || replaceRegex.isEmpty) return contentStr;

    // 拆行 trim (對標 Android LFRegex split+trim)
    var str = contentStr
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .join('\n');

    try {
      final rule = AnalyzeRule(source: source, ruleData: book)
          .setContent(str, baseUrl: baseUrl, redirectUrl: redirectUrl)
          .setChapter(chapter);
      try {
        str = rule.getString(replaceRegex);
      } finally {
        rule.dispose();
      }
    } on ParsingException catch (error, stackTrace) {
      // replaceRegex 是外部書源規則；規則本身失敗可退回未替換正文，
      // 但保留完整診斷。其他未知錯誤不得在 acquisition boundary 被吞掉。
      AppLog.e(
        '正文 replaceRegex 規則解析失敗，保留未替換正文',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (str.trim().isEmpty) return '';

    // 段落縮排 (對標 Android "　　$it" join)
    str = str.split(RegExp(r'\r?\n')).map((e) => '　　$e').join('\n');
    return str;
  }
}

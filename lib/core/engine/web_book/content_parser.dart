import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
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

  /// 正文規則的 `title` 從這一頁取到的章名（[ContentParser.parse] 的
  /// `readTitle`）；沒取到是 null。
  final String? title;

  const ContentResult({
    required this.content,
    this.nextUrls = const [],
    this.title,
  });
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
    bool readTitle = false,
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
      final title = readTitle ? _readTitle(rule, contentRule) : null;

      var content = rule.getString(contentRule.content ?? '', unescape: false);
      // 先清標籤再解實體（同 Legado `BookContent`）：倒過來的話，原文寫著的
      // `&lt;span&gt;` 先變成 `<span>`，再被當成標籤刪掉。
      content = HtmlFormatter.formatKeepImg(content, redirectUrl: pageUrl);
      if (content.contains('&')) {
        content = AnalyzeRuleBase.htmlUnescape.convert(content);
      }

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

      return ContentResult(content: content, nextUrls: nextUrls, title: title);
    } finally {
      rule.dispose();
    }
  }

  /// 正文規則的 `title`：從正文頁取章名（同 Legado `BookContent`），算出
  /// 空白或規則出錯時是 null。
  static String? _readTitle(AnalyzeRule rule, ContentRule contentRule) {
    final titleRule = contentRule.title;
    if (titleRule == null || titleRule.trim().isEmpty) return null;
    try {
      final title = rule.getString(titleRule);
      return title.trim().isEmpty ? null : title;
    } on Exception catch (error, stackTrace) {
      AppLog.e('正文的章名規則失敗，留著原本的章名', error: error, stackTrace: stackTrace);
      return null;
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

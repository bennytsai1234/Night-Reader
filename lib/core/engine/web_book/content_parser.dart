import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/core/engine/analyze_rule.dart';
import 'package:reader/core/utils/html_formatter.dart';
import 'package:reader/core/utils/network_utils.dart';

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
    String? nextChapterUrl,
  }) async {
    final rule = AnalyzeRule(source: source, ruleData: book)
        .setContent(body, baseUrl: baseUrl)
        .setChapter(chapter)
        .setNextChapterUrl(nextChapterUrl);

    try {
      final contentRule = source.ruleContent;
      if (contentRule == null) return ContentResult(content: body);

      var content = await rule.getStringAsync(
        contentRule.content ?? '',
        unescape: false,
      );

      content = HtmlFormatter.formatKeepImg(content, baseUrl: baseUrl);

      if (content.contains('&')) {
        content = AnalyzeRuleBase.htmlUnescape.convert(content);
      }

      final nextUrls = <String>[];
      if (contentRule.nextContentUrl != null &&
          contentRule.nextContentUrl!.isNotEmpty) {
        final list = await rule.getStringListAsync(
          contentRule.nextContentUrl!,
          isUrl: true,
        );
        for (final u in list) {
          if (u.isEmpty || u == baseUrl) continue;
          if (nextChapterUrl != null) {
            final absNext = NetworkUtils.getAbsoluteURL(baseUrl, u);
            final absChapter = NetworkUtils.getAbsoluteURL(
              baseUrl,
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
  /// replaceRegex 走 AnalyzeRule.getStringAsync 以支援內嵌 @js: / {{js}} 等表達式
  static Future<String> finalizeContent({
    required BookSource source,
    Book? book,
    BookChapter? chapter,
    required String contentStr,
    String? baseUrl,
  }) async {
    final replaceRegex = source.ruleContent?.replaceRegex;
    if (replaceRegex == null || replaceRegex.isEmpty) return contentStr;

    // 拆行 trim (對標 Android LFRegex split+trim)
    var str = contentStr
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .join('\n');

    try {
      final rule = AnalyzeRule(
        source: source,
        ruleData: book,
      ).setContent(str, baseUrl: baseUrl).setChapter(chapter);
      try {
        str = await rule.getStringAsync(replaceRegex);
      } finally {
        rule.dispose();
      }
    } catch (_) {
      // 若規則解析失敗則保留 trim 後的原文
    }

    // 段落縮排 (對標 Android "　　$it" join)
    str = str.split(RegExp(r'\r?\n')).map((e) => '　　$e').join('\n');
    return str;
  }
}

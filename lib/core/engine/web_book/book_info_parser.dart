import 'package:html/parser.dart' as html_parser;
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/engine/analyze_rule.dart';
import 'package:reader/core/utils/network_utils.dart';

class BookInfoParser {
  static Future<Book> parse({
    required BookSource source,
    required Book book,
    required String body,
    required String baseUrl,
  }) async {
    final infoRule = source.ruleBookInfo;
    if (infoRule == null) return book;

    final rule = AnalyzeRule(
      source: source,
      ruleData: book,
    ).setContent(body, baseUrl: baseUrl);

    try {
      // 執行 init 規則 (對標 Android BookInfoRule.init)
      // init 規則用於頁面預處理，例如 Ajax 載入或 JS 解密
      if (infoRule.init != null && infoRule.init!.isNotEmpty) {
        final initResult = await rule.getElementAsync(infoRule.init!);
        final hasInitResult =
            initResult != null &&
            (initResult is! String || initResult.trim().isNotEmpty);
        if (hasInitResult) {
          // init 規則的結果替換為新的解析內容
          rule.setContent(initResult, baseUrl: baseUrl);
        }
      }

      final name = _format(await rule.getStringAsync(infoRule.name ?? ''));
      final author = _format(await rule.getStringAsync(infoRule.author ?? ''));

      final tocUrl = await rule.getStringAsync(
        infoRule.tocUrl ?? '',
        isUrl: true,
      );
      final kind = (await rule.getStringListAsync(
        infoRule.kind ?? '',
      )).join(',');
      final coverUrl = await rule.getStringAsync(
        infoRule.coverUrl ?? '',
        isUrl: true,
      );
      final intro = await rule.getStringAsync(infoRule.intro ?? '');
      final latestChapterTitle = await rule.getStringAsync(
        infoRule.lastChapter ?? '',
      );
      final normalizedTocUrl = _resolveFallbackTocUrl(
        tocUrl: tocUrl,
        body: body,
        baseUrl: baseUrl,
        bookUrl: book.bookUrl,
      );

      return book.copyWith(
        name: name.isEmpty ? book.name : name,
        author: author.isEmpty ? book.author : author,
        kind: kind.isEmpty ? book.kind : kind,
        coverUrl: coverUrl.isEmpty ? book.coverUrl : coverUrl,
        intro: intro.isEmpty ? book.intro : intro,
        latestChapterTitle:
            latestChapterTitle.isEmpty
                ? book.latestChapterTitle
                : latestChapterTitle,
        // tocUrl: 若規則解析結果為空，以 bookUrl 作為預設目錄頁 (對標 Android 邏輯)
        tocUrl: normalizedTocUrl,
      );
    } finally {
      rule.dispose();
    }
  }

  static String _format(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _resolveFallbackTocUrl({
    required String tocUrl,
    required String body,
    required String baseUrl,
    required String bookUrl,
  }) {
    if (tocUrl.isNotEmpty && tocUrl != bookUrl) {
      return tocUrl;
    }

    final document = html_parser.parse(body);
    for (final anchor in document.querySelectorAll('a[href]')) {
      final text = anchor.text.trim();
      if (!_looksLikeTocLinkText(text)) {
        continue;
      }
      final href = anchor.attributes['href']?.trim() ?? '';
      if (href.isEmpty) {
        continue;
      }
      final resolved = NetworkUtils.getAbsoluteURL(baseUrl, href);
      if (resolved.isNotEmpty) {
        return resolved;
      }
    }
    return bookUrl;
  }

  static bool _looksLikeTocLinkText(String text) {
    if (text.isEmpty) {
      return false;
    }
    return text.contains('章节目录') ||
        text.contains('章節目錄') ||
        text == '目录' ||
        text == '目錄';
  }
}

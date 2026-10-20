import 'package:html/parser.dart' as html_parser;
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/utils/network_utils.dart';
import 'package:night_reader/core/utils/string_utils.dart';

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
      final kind = (await rule.getStringListAsync(infoRule.kind ?? ''))
          .join(',');
      final coverUrl = coverUrlFrom(
        await rule.getStringAsync(infoRule.coverUrl ?? ''),
        baseUrl,
      );
      final intro = await rule.getStringAsync(infoRule.intro ?? '');
      final latestChapterTitle = await rule.getStringAsync(
        infoRule.lastChapter ?? '',
      );
      final wordCount = StringUtils.wordCountFormat(
        await rule.getStringAsync(infoRule.wordCount ?? ''),
      );
      final normalizedTocUrl = _resolveFallbackTocUrl(
        tocUrl: tocUrl,
        body: body,
        baseUrl: baseUrl,
        bookUrl: book.bookUrl,
      );

      // 書架上的書名與作者以使用者看到（可能改過）的為準，除非書源規則
      // 宣告 canReName（同 legado）；搜尋結果進詳情時仍以詳情頁為準。
      final keepNames =
          book.isInBookshelf &&
          (infoRule.canReName == null || infoRule.canReName!.trim().isEmpty);
      String pick(String parsed, String current) =>
          parsed.isEmpty || (keepNames && current.isNotEmpty)
          ? current
          : parsed;

      return book.copyWith(
        name: pick(name, book.name),
        author: pick(author, book.author),
        kind: kind.isEmpty ? book.kind : kind,
        coverUrl: coverUrl.isEmpty ? book.coverUrl : coverUrl,
        intro: intro.isEmpty ? book.intro : intro,
        latestChapterTitle: latestChapterTitle.isEmpty
            ? book.latestChapterTitle
            : latestChapterTitle,
        wordCount: wordCount.isEmpty ? book.wordCount : wordCount,
        // tocUrl: 若規則解析結果為空，以 bookUrl 作為預設目錄頁 (對標 Android 邏輯)
        tocUrl: normalizedTocUrl,
      );
    } finally {
      rule.dispose();
    }
  }

  static String _format(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// 封面規則的結果（不帶 `isUrl` 讀出）補成完整網址；抓到好幾個時取第一
  /// 個，沒抓到時是空的。不帶 `isUrl`：那會在沒抓到時改回傳頁面網址（書籍
  /// 與目錄網址要這樣），封面就成了一張載不出來的網頁，清單或書籍詳情原本
  /// 有的封面也被它蓋掉。同 Legado 讀封面的做法。
  static String coverUrlFrom(String raw, String baseUrl) {
    for (final line in raw.split('\n')) {
      final url = line.trim();
      if (url.isNotEmpty) return NetworkUtils.getAbsoluteURL(baseUrl, url);
    }
    return '';
  }

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

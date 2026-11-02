import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/web_book/book_info_parser.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/engine/web_book/content_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';

import '../../test_helper.dart';

/// 網址規則（書籍網址、目錄網址、正文網址）沒有結果時用請求的網址
/// （`baseUrl`），不是網站轉址後回應的網址（`redirectUrl`）；相對網址才用
/// `redirectUrl` 補。同 Legado：`AnalyzeRule.getString(isUrl)` 的
/// `baseUrl ?: ""` 與 `getAbsoluteURL(redirectUrl, str)`；詳情、目錄、正文
/// 解析時 `baseUrl` 是請求的網址、`redirectUrl` 是 `res.url`（`WebBook.kt`）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  // 書籍網址帶網址選項（POST 的內容）：轉址後的 `res.url` 沒有這些選項，
  // 拿它當目錄網址就變成一個不帶內容的 GET。
  const requested = 'https://u.test/book,{"method":"POST","body":"id=7"}';
  const responded = 'https://u.test/book/7/';

  final source = BookSource.fromJson({
    'bookSourceName': '網址規則',
    'bookSourceUrl': 'https://u.test',
    'ruleBookInfo': {'name': 'h1@text', 'tocUrl': 'class.toc@href'},
    'ruleToc': {
      'chapterList': 'tag.li',
      'chapterName': 'tag.a@text',
      'chapterUrl': 'tag.a@href',
      'nextTocUrl': 'class.next@href',
    },
    'ruleContent': {'content': 'id.c@text', 'nextContentUrl': 'class.n@href'},
  });
  final book = Book(bookUrl: requested, origin: 'https://u.test');

  test('網址規則沒有結果時是請求的網址，有相對網址時用轉址後的補', () {
    AnalyzeRule at(String html) => AnalyzeRule().setContent(
      html,
      baseUrl: requested,
      redirectUrl: responded,
    );

    expect(at('<p>x</p>').getString('class.toc@href', isUrl: true), requested);
    expect(at('<p>x</p>').getString('@js:" "', isUrl: true), requested);
    expect(
      at('<a class="toc" href="list.html">目錄</a>')
          .getString('class.toc@href', isUrl: true),
      'https://u.test/book/7/list.html',
    );
    // 沒給轉址後的網址時兩個一樣
    expect(
      AnalyzeRule()
          .setContent('<p/>', baseUrl: 'https://u.test/a')
          .getString('class.toc@href', isUrl: true),
      'https://u.test/a',
    );
  });

  test('詳情頁：目錄網址規則沒有結果，目錄網址是詳情頁自己的網址', () async {
    final parsed = await BookInfoParser.parse(
      source: source,
      book: book,
      body: '<h1>書名</h1>',
      baseUrl: requested,
      redirectUrl: responded,
    );
    expect(parsed.name, '書名');
    expect(parsed.tocUrl, requested);
  });

  test('目錄：章節沒有網址時用目錄的網址，相對網址用轉址後的補', () async {
    final result = await ChapterListParser.parse(
      source: source,
      book: book,
      body:
          '<ul><li><a>卷一</a></li><li><a href="1.html">第一章</a></li></ul>'
          '<a class="next" href="p2.html">下一頁</a>',
      baseUrl: 'https://u.test/toc,{"method":"POST"}',
      redirectUrl: 'https://u.test/toc/',
    );
    expect(result.chapters.map((c) => c.url), [
      'https://u.test/toc,{"method":"POST"}',
      'https://u.test/toc/1.html',
    ]);
    expect(result.chapters.first.baseUrl, 'https://u.test/toc/');
    expect(result.nextUrls, ['https://u.test/toc/p2.html']);
  });

  test('正文：下一頁網址用轉址後的補', () async {
    final result = await ContentParser.parse(
      source: source,
      book: book,
      chapter: BookChapter(url: 'https://u.test/c/1', title: '第一章'),
      body: '<div id="c">字</div><a class="n" href="2.html">下一頁</a>',
      baseUrl: 'https://u.test/c/1',
      redirectUrl: 'https://u.test/read/1/',
    );
    expect(result.nextUrls, ['https://u.test/read/1/2.html']);
  });

  test('正文最後的替換規則看到的是章節網址，相對網址用第一頁轉址後的補', () async {
    final replacing = BookSource.fromJson({
      'bookSourceName': '替換規則',
      'bookSourceUrl': 'https://u.test',
      'ruleContent': {
        'content': 'id.c@text',
        'replaceRegex': '@js:result + "|" + baseUrl',
      },
    });
    final content = await ContentParser.finalizeContent(
      source: replacing,
      book: book,
      chapter: BookChapter(url: 'https://u.test/12.html', title: '一'),
      contentStr: '正文',
      baseUrl: 'https://u.test/12.html',
      redirectUrl: 'https://www.u.test/12.html',
    );
    expect(content, endsWith('正文|https://u.test/12.html'));
  });
}

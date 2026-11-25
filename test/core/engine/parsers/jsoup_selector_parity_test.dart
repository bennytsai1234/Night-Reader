import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import '../../../test_helper.dart';

/// 預設規則與 CSS 選擇器照 Legado（`AnalyzeByJSoup`）與它用的 Jsoup 1.16.2。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  AnalyzeRule rule(String html) =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://site.test'))
          .setContent(html, baseUrl: 'https://site.test/toc');

  Future<List<String>> toc(String html, Map<String, String> ruleToc) async {
    final chapters = (await ChapterListParser.parse(
      source: BookSource.fromJson({
        'bookSourceName': '選擇器',
        'bookSourceUrl': 'https://site.test',
        'ruleToc': ruleToc,
      }),
      book: Book(
        bookUrl: 'https://site.test/toc',
        tocUrl: 'https://site.test/toc',
        origin: 'https://site.test',
      ),
      body: html,
      baseUrl: 'https://site.test/toc',
    )).chapters;
    return [for (final c in chapters) '${c.title}|${c.url}'];
  }

  const three =
      '<div><a href="/1">第一章</a><a href="/2">第二章</a><a href="/3">第三章</a></div>';

  test('方括號裡的幾個索引照寫的順序取', () {
    expect(rule(three).getStringList('tag.a[0,1]@text'), ['第一章', '第二章']);
    expect(rule(three).getStringList('tag.a[-1,0]@text'), ['第三章', '第一章']);
    expect(rule(three).getStringList('tag.a[0:1,2]@text'), [
      '第一章',
      '第二章',
      '第三章',
    ]);
    expect(rule(three).getStringList('tag.a[!0]@text'), ['第二章', '第三章']);
    expect(rule(three).getStringList('tag.a.1@text'), ['第二章']);
  });

  test(':has 只看底下的元素，不算自己', () {
    const html =
        '<section><div class="chapter"><div>正文</div></div><div class="chapter">廣告</div></section>';
    expect(rule(html).getStringList('@css:.chapter:has(div)@text'), ['正文']);
    expect(
      rule('<p><a href="/1">一</a></p>').getElements('@css:a:has(a)'),
      isEmpty,
    );
  });

  test('[屬性~=正則] 一律是正則，正則裡的方括號不算結尾', () async {
    const html = '<a href="/chapter/1">第一章</a><a href="/about">關於</a>';
    expect(
      await toc(html, {
        'chapterList': '@css:a[href~=chapter]',
        'chapterName': 'text',
        'chapterUrl': 'href',
      }),
      ['第一章|https://site.test/chapter/1'],
    );
    expect(
      await toc(html, {
        'chapterList': '@css:a[href~=/chapter/[0-9]+]',
        'chapterName': 'text',
        'chapterUrl': 'href',
      }),
      ['第一章|https://site.test/chapter/1'],
    );
  });

  test('[屬性~=正則] 沒有這個屬性就不算，有但是空的算', () {
    const html =
        '<a data-url="/1">第一章</a><a href="/home">首頁</a><a data-url="">空</a>';
    expect(rule(html).getStringList('@css:a[data-url~=.*]@text'), ['第一章', '空']);
    expect(rule(html).getStringList(r'@css:a[data-url~=^$]@text'), ['空']);
  });

  test('[屬性=值] 不分大小寫、不看頭尾空白', () {
    const html =
        '<a data-kind="CHAPTER" href="/1">一</a><a data-kind=" chapter " href="/2">二</a>'
        '<a data-kind="chapter-preview" href="/3">三</a>';
    expect(rule(html).getStringList('@css:a[data-kind=chapter]@text'), [
      '一',
      '二',
    ]);
    expect(
      rule('<a data-kind="CHAPTER">一</a>')
          .getStringList('@css:a[data-kind=chapter]@text'),
      ['一'],
    );
  });

  test('text. 在自己的文字裡找：跨文字節點、不分大小寫', () {
    expect(
      rule('<div><a href="/1">第一<i></i>章</a></div>')
          .getStringList('text.第一章@text'),
      ['第一章'],
    );
    expect(
      rule('<div><a href="/1">Chapter 1</a></div>')
          .getStringList('text.chapter@text'),
      ['Chapter 1'],
    );
    // 字只在子元素裡：只選到 <b>，父元素自己的文字沒有。
    expect(
      rule('<div><p class="p"><b class="b">第一章</b></p></div>')
          .getStringList('text.第一章@class'),
      ['b'],
    );
  });

  test('id. 收齊每個同 ID 的元素', () {
    const html =
        '<div><a id="chapter" href="/1">第一章</a><a id="chapter" href="/2">第二章</a></div>';
    expect(rule(html).getStringList('id.chapter@text'), ['第一章', '第二章']);
  });

  test('@abs:屬性 照 Jsoup：完整網址照原樣，相對的照 <base>，沒有基準是空的', () {
    expect(
      rule('<a href="https://site.test/chapter/1">一</a>')
          .getString('a@abs:href'),
      'https://site.test/chapter/1',
    );
    expect(
      rule(
        '<html><head><base href="https://cdn.test/b/"></head><body><img src="x.png"></body></html>',
      ).getString('img@abs:src'),
      'https://cdn.test/b/x.png',
    );
    expect(rule('<a href="/chapter/1">一</a>').getString('a@abs:href'), '');
    expect(
      rule('<div><base href="https://x.test/"><a href="b">b</a></div>')
          .getString('a@abs:href'),
      'https://x.test/b',
    );
  });

  test('屬性相等配上別的屬性條件照常選得到，不會卡住', () {
    const html =
        '<a data-type="chapter" href="/chapter/1">一</a><a data-type="CHAPTER " href="/2">二</a>'
        '<a data-type="chapter">沒有網址</a><a href="/x">x</a>';
    expect(rule(html).getStringList('@css:a[data-type=chapter][href]@text'), [
      '一',
      '二',
    ]);
    expect(
      rule(html).getStringList('@css:a[href=/chapter/1][data-type]@text'),
      ['一'],
    );
  });

  test(':has 以正在檢查的元素為界，逗號分開的幾組有一組成立就算', () {
    const html =
        '<section><div class="d1"><a href="/1">一</a></div></section>'
        '<div class="d2"><section><a href="/2">二</a></section></div>'
        '<div class="d3"><a href="/3">三</a></div>';
    expect(rule(html).getStringList('@css:div:has(section a)@class'), ['d2']);
    expect(rule(html).getStringList('@css:div:has(> p, a)@class'), [
      'd1',
      'd2',
      'd3',
    ]);
  });

  test('[屬性~="…"] 的引號也是正則的一部分（同 Jsoup）', () {
    const html = '<a class="chapter listed">一</a>';
    expect(rule(html).getStringList('@css:a[class~="chapter"]@text'), isEmpty);
    expect(rule(html).getStringList('@css:a[class~=chapter]@text'), ['一']);
  });

  test('@abs: 的空網址照 <base> 是基準本身', () {
    expect(
      rule(
        '<html><head><base href="https://cdn.test/b/"></head><body><a href="">a</a></body></html>',
      ).getString('a@abs:href'),
      'https://cdn.test/b/',
    );
  });
}

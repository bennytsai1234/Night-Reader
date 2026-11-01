import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/engine/web_book/content_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';

import '../../../test_helper.dart';

const _page = '''
<html><head><title>  第一章 山雨欲來 </title></head><body>
<div class="list">
  <a href="/book/1.html" class="ch first">第一章</a>
  <a href="/book/2.html" class="ch">第二章</a>
  <a href="https://other.test/3.html" class="ch">Third CHAPTER</a>
</div>
<div id="content"><p>一段<b>正文</b></p><p>第二段</p>ㄅ<br>ㄆ<script>var x = 1;</script></div>
</body></html>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();
  final skip = quickJsUnavailableReason();

  /// 用 AnalyzeRule 跑一段規則 JS，`result` 是頁面。
  Future<dynamic> run(String js) async {
    final rule = AnalyzeRule(
      source: BookSource(bookSourceUrl: 'https://site.test'),
    )..setContent(_page, baseUrl: 'https://site.test/book/');
    return rule.evalJS(js, _page);
  }

  test('Jsoup.parse gives a real document', () async {
    expect(
      await run('''
        var doc = org.jsoup.Jsoup.parse(result, 'https://site.test/book/');
        var links = doc.select('div.list a.ch');
        [links.size(), links.get(0).text(), links.first().attr('abs:href'),
         links.last().absUrl('href'), links.eachText().join('/'),
         doc.title()].join('|')
      '''),
      '3|第一章|https://site.test/book/1.html|https://other.test/3.html|'
      '第一章/第二章/Third CHAPTER|第一章 山雨欲來',
    );
  }, skip: skip);

  test('Packages.org.jsoup and element navigation', () async {
    expect(
      await run('''
        var doc = Packages.org.jsoup.Jsoup.parse(result);
        var first = doc.selectFirst('a.first');
        var out = [];
        out.push(first.nextElementSibling().text());
        out.push(first.parent().className());
        out.push(first.parent().children().size());
        out.push(first.hasClass('ch'), first.is('a.first'));
        out.push(doc.select('a').filter(function(a) { return a.text().indexOf('章') >= 0; }).length);
        var texts = [];
        doc.select('a').forEach(function(a) { texts.push(a.text()); });
        out.push(texts.length);
        out.join('|')
      '''),
      '第二章|list|3|true|true|2|3',
    );
  }, skip: skip);

  test('text follows Jsoup: spaces between blocks, br and no script', () async {
    expect(
      await run('''
        var c = org.jsoup.Jsoup.parse(result).getElementById('content');
        [c.text(), c.ownText(), c.select('p').first().text()].join('|')
      '''),
      '一段正文 第二段 ㄅ ㄆ|ㄅ ㄆ|一段正文',
    );
  }, skip: skip);

  test('Jsoup pseudo selectors', () async {
    expect(
      await run('''
        var doc = org.jsoup.Jsoup.parse(result);
        [doc.select('a:eq(1)').text(), doc.select('a:lt(2)').size(),
         doc.select('a:gt(0)').size(), doc.select('a:contains(third)').size(),
         doc.select('a:matches(第.章)').size(), doc.select('div:has(> a)').size(),
         doc.select('div:containsData(var x)').attr('id')].join('|')
      '''),
      '第二章|2|2|1|2|1|content',
    );
  }, skip: skip);

  test('unquoted attribute values work like Jsoup (台灣小說網)', () async {
    expect(
      await run('''
        var d = Packages.org.jsoup.Jsoup.parse(String(result));
        var n = d.select('div.list a[href^=/book/]');
        [n.size(), n.text(), n.attr('href')].join('|')
      '''),
      '2|第一章 第二章|/book/1.html',
    );
  }, skip: skip);

  test('changes stay in the same tree', () async {
    expect(
      await run('''
        var doc = org.jsoup.Jsoup.parse(result);
        var list = doc.selectFirst('.list');
        var copy = list.clone();
        copy.select('a.first').remove();
        list.selectFirst('a').attr('data-x', '1');
        [copy.select('a').size(), list.select('a').size(),
         doc.select('a[data-x]').size(), list.selectFirst('a').outerHtml()].join('|')
      '''),
      '2|3|1|<a href="/book/1.html" class="ch first" data-x="1">第一章</a>',
    );
  }, skip: skip);

  // 每一項的答案是真的 Jsoup 1.15.3 跑出來的。
  test('edge cases match Jsoup 1.15.3', () async {
    expect(
      await run(r'''
        var J = org.jsoup.Jsoup, out = [];
        out.push(J.parse('<div id=a> </div><div id=b></div>').select('div:empty').size());
        var rows = J.parse('<div class=intro>i</div><div class=row>1</div><div class=row>2</div>');
        out.push(rows.select('.row:eq(0)').size(), rows.select('.row:eq(1)').text());
        var t = J.parse('<div class=author>作者：<br>張三</div><div class=x><p>甲</p><p>乙</p>丙<span>丁</span></div><script>var x=1;</script><p id=w>A<br>B</p>');
        out.push(t.select('.author').text(), t.select('.author').first().ownText(),
          t.select('.x').text(), t.select('script').first().text(),
          t.select('script').first().data(), t.select('#w').first().wholeText());
        var box = J.parse('<div class=box>x</div>').selectFirst('div');
        out.push(box.select('.box:contains(x)').size(), box.select(':root').size(),
          box.clone().is('div'));
        out.push(J.parse('<a HREF=1>A</a>').selectFirst('a').attr('HREF'));
        out.push(J.parse('<div id=a><section><p><a>X</a></p></section></div>').select('div:has(> p a)').size());
        out.push(J.parse('<p>Alpha</p>').select('p:matches((?i)alpha)').size());
        var doc = J.parse('<p>X</p>');
        out.push(doc.children().first().tagName(), doc.childrenSize(),
          doc.selectFirst('p').ownerDocument().equals(doc));
        out.push(J.parse("<base href='https://cdn.test/books/'><a href='1'>A</a>", 'https://site.test/path/')
          .selectFirst('a').attr('abs:href'));
        var rm = J.parse("<div><a href='1'>A</a></div>", 'https://site.test/path/');
        var link = rm.selectFirst('a');
        rm.body().empty();
        out.push(link.absUrl('href'));
        var ren = J.parse('<div id=x>hello</div>').selectFirst('#x');
        var ren2 = ren.tagName('p');
        out.push((ren === ren2) + ' ' + ren.tagName() + ' ' + ren.text());
        out.push(J.parse('<div><span>a</span><span>b</span></div>').text());
        out.join('|')
      '''),
      [
        1,
        0,
        '1',
        '作者： 張三',
        '作者： 張三',
        '甲 乙 丙丁',
        '',
        'var x=1;',
        'A\nB',
        1,
        1,
        true,
        '1',
        0,
        1,
        'html',
        1,
        true,
        'https://cdn.test/books/1',
        'https://site.test/path/1',
        'true p hello',
        'ab',
      ].join('|'),
    );
  }, skip: skip);

  test('errors from Jsoup can be caught like in Rhino', () async {
    expect(
      await run('''
        var doc = org.jsoup.Jsoup.parse(result);
        try { doc.select('a').get(9); 'no error'; } catch (e) { 'caught'; }
      '''),
      'caught',
    );
  }, skip: skip);

  test('java.getElements returns Jsoup elements (搬山人)', () async {
    // 搬山人的正文規則：java.setContent 後用 java.getElements 拿整頁，
    // 再 select、clone、remove，最後交回段落的 outerHtml。
    final source = BookSource.fromJson({
      'bookSourceName': '搬山人',
      'bookSourceUrl': 'https://www.banshanren.com',
      'ruleContent': {
        'content': r'''@js:var pageUrl = String(baseUrl);
function inspectPage(markup) {
    java.setContent(String(markup), pageUrl);
    var documents = java.getElements('@css:html');
    if (documents.size() === 0) throw new Error('没有取得网页');
    var doc = documents.get(0);
    var chapterBox = doc.select('.chapter_box').first();
    var paragraphs = doc.select('.chapter_content_box > p');
    var code = chapterBox === null ? '' : String(chapterBox.attr('data-code'));
    return {paragraphs: paragraphs, count: paragraphs.size(), code: code};
}
var state = inspectPage(result);
if (state.count === 0) throw new Error('网页未提供正文段落');
var clean = state.paragraphs.clone();
clean.select('span[onclick^=togglePostComment]').remove();
String(clean.outerHtml());''',
      },
    });
    const chapterHtml = '''
<html><body><div class="chapter_box" data-code="0">
<div class="chapter_content_box">
<p>第一段<span onclick="togglePostComment(1)">3</span></p>
<p>第二段</p>
</div></div></body></html>''';
    final content = await ContentParser.parse(
      source: source,
      book: Book(
        bookUrl: 'https://www.banshanren.com/novel/x',
        origin: 'https://www.banshanren.com',
        name: '搬山人',
      ),
      chapter: BookChapter(
        url: 'https://www.banshanren.com/novel/x/1',
        title: '第一章',
        index: 0,
      ),
      body: chapterHtml,
      baseUrl: 'https://www.banshanren.com/novel/x/1',
    );

    expect(content.content, contains('第一段'));
    expect(content.content, contains('第二段'));
    expect(content.content, isNot(contains('3')));
  }, skip: skip);

  test('an empty CSS result is Elements, an empty JSON list is an array', () {
    final html = AnalyzeRule()..setContent(_page, baseUrl: 'https://site.test');
    expect(html.getElements('tag.missing<js>result.select("a")</js>'), isEmpty);

    final json = AnalyzeRule()..setContent('{"items":[]}');
    expect(
      json.getElements(r'$.items<js>result.push("c"); String(result)</js>'),
      ['c'],
    );
  }, skip: skip);

  test('a list rule hands JS Jsoup elements (小红书)', () async {
    // 小红书的目錄規則：選到的章節排成網頁打亂前的順序，再 select 出連結。
    final source = BookSource.fromJson({
      'bookSourceName': '小红书',
      'bookSourceUrl': 'https://site.test',
      'ruleToc': {
        'chapterList':
            'class.ch\n<js>\n'
            'result.sort((a, b) => a.attr("data-x") - b.attr("data-x"));\n'
            'result.select("a");\n</js>',
        'chapterName': 'text',
        'chapterUrl': 'href',
      },
    });
    const tocHtml = '''
<html><body>
<div class="ch" data-x="2"><a href="/2.html">第二章</a></div>
<div class="ch" data-x="1"><a href="/1.html">第一章</a></div>
</body></html>''';
    final result = await ChapterListParser.parse(
      source: source,
      book: Book(
        bookUrl: 'https://site.test/book',
        origin: 'https://site.test',
        name: '書',
      ),
      body: tocHtml,
      baseUrl: 'https://site.test/book/',
    );

    expect(result.chapters.map((c) => c.title), ['第一章', '第二章']);
    expect(result.chapters.first.url, 'https://site.test/1.html');
  }, skip: skip);
}

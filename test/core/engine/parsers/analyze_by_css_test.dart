import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:night_reader/core/engine/parsers/analyze_by_css.dart';
import 'package:night_reader/core/engine/parsers/css/analyze_by_css_support.dart';

void main() {
  group('AnalyzeByCss Tests', () {
    const htmlStr = '''
    <html>
      <body>
        <div id="content">
          <ul class="bookList">
            <li class="item">
              <a href="book1.html" title="Book 1">Chapter 1</a>
              <span class="author">Author A</span>
            </li>
            <li class="item">
              <a href="book2.html" title="Book 2">Chapter 2</a>
              <span class="author">Author B</span>
            </li>
            <li class="item">
              <a href="book3.html" title="Book 3">Chapter 3</a>
              <span class="author">Author C</span>
            </li>
          </ul>
          <div class="footer">Footer Text <!-- hidden comment --> <span>Extra</span></div>
        </div>
      </body>
    </html>
    ''';

    late AnalyzeByCss analyzer;

    setUp(() {
      analyzer = AnalyzeByCss(htmlStr);
    });

    test('1. Standard CSS selector via @CSS:', () {
      final titles = analyzer.getStringList('@CSS:li.item a@text');
      expect(titles, ['Chapter 1', 'Chapter 2', 'Chapter 3']);
    });

    test('2. Legado custom syntax tag.class@attr', () {
      final titles = analyzer.getStringList('li.item@tag.a@text');
      expect(titles, ['Chapter 1', 'Chapter 2', 'Chapter 3']);

      final hrefs = analyzer.getStringList('li.item@tag.a@href');
      expect(hrefs, ['book1.html', 'book2.html', 'book3.html']);
    });

    test('3. Index selection using .index', () {
      // First item
      expect(analyzer.getString('li.item.0@tag.a@text'), 'Chapter 1');
      // Last item
      expect(analyzer.getString('li.item.-1@tag.a@text'), 'Chapter 3');
    });

    test('4. Index selection using !index (User requirement: selection)', () {
      expect(analyzer.getStringList('li.item!0@tag.a@text'), [
        'Chapter 2',
        'Chapter 3',
      ]);
      expect(analyzer.getStringList('li.item!1@tag.a@text'), [
        'Chapter 1',
        'Chapter 3',
      ]);
    });

    test('5. Range selection [start:end]', () {
      final titles = analyzer.getStringList('li.item[0:1]@tag.a@text');
      expect(titles, ['Chapter 1', 'Chapter 2']);
    });

    test('6. Special attributes: text, html, ownText', () {
      // text includes all child text
      expect(analyzer.getString('.footer@text'), 'Footer Text Extra');
      // ownText only includes direct text nodes
      expect(analyzer.getString('.footer@ownText'), 'Footer Text');
      // html includes outer html
      expect(
        analyzer.getString('.footer@html'),
        contains('<div class="footer">'),
      );
    });

    test('7. Logical && operator', () {
      final result = analyzer.getString('.author.0@text && .author.1@text');
      expect(result, 'Author A\nAuthor B');
    });

    test('8. Logical || operator (fallback)', () {
      expect(
        analyzer.getString('.none@text || .footer@ownText'),
        'Footer Text',
      );
    });

    test('9. ElementsSingle ! exclusion removes specified indexes', () {
      final doc = html_parser.parse(
        '<div><p>A</p><p>B</p><p>C</p><p>D</p></div>',
      );
      final container = doc.querySelector('div')!;
      final single = ElementsSingle();

      final result = single.getElementsSingle(container, 'tag.p!0');
      expect(result.map((e) => e.text).toList(), ['B', 'C', 'D']);
    });

    test('10. Bracket exclusion [!...] removes multiple indexes', () {
      final doc = html_parser.parse(
        '<div><p>A</p><p>B</p><p>C</p><p>D</p></div>',
      );
      final container = doc.querySelector('div')!;
      final single = ElementsSingle();

      final result = single.getElementsSingle(container, 'tag.p[!0,2]');
      expect(result.map((e) => e.text).toList(), ['B', 'D']);
    });

    test('11. html strips script and style tags', () {
      final doc = html_parser.parse(
        '<div><p>Hello</p><script>alert(1)</script><style>.x{}</style><span>World</span></div>',
      );
      final helper = AnalyzeByCss(doc.documentElement!.outerHtml);
      final result = helper.getResultLast(doc.querySelectorAll('div'), 'html');

      expect(result, hasLength(1));
      expect(result.first.contains('<script>'), false);
      expect(result.first.contains('<style>'), false);
      expect(result.first.contains('Hello'), true);
      expect(result.first.contains('World'), true);
    });

    test('11b. html combines multiple matched elements into one string', () {
      final helper = AnalyzeByCss('''
        <div class="con"><p>第一段</p></div>
        <div class="con"><p>第二段</p></div>
        ''');

      final result = helper.getStringList('.con@html');

      expect(result, hasLength(1));
      expect(result.first, contains('第一段'));
      expect(result.first, contains('第二段'));
    });

    test('12. textNodes joins direct text nodes per element', () {
      final doc = html_parser.parse(
        '<div>First<br>Second<span>Skip</span>Third</div>',
      );
      final helper = AnalyzeByCss(doc.documentElement!.outerHtml);
      final result = helper.getResultLast(
        doc.querySelectorAll('div'),
        'textNodes',
      );

      expect(result, ['First\nSecond\nThird']);
    });

    test('13. Current element can match itself in tag selector', () {
      final doc = html_parser.parse('<a href="/chapter/1">Chapter 1</a>');
      final anchor = doc.querySelector('a')!;
      final helper = AnalyzeByCss(anchor);

      expect(helper.getString('a@text'), 'Chapter 1');
      expect(helper.getString('a@href'), '/chapter/1');
    });

    test('13b. Root html element can match itself in legacy selector mode', () {
      final helper = AnalyzeByCss(htmlStr);

      expect(helper.getElements('html'), hasLength(1));
      expect(helper.getString('html@text'), contains('Chapter 1'));
    });

    test('14. :contains selector works in direct CSS mode', () {
      final helper = AnalyzeByCss('''
        <div class="pager">
          <a href="/prev">上一章</a>
          <a href="/next">下一章</a>
        </div>
        ''');

      expect(helper.getString('@CSS:.pager a:contains(下一章)@href'), '/next');
    });

    test('15. :contains selector works in tag-prefixed legado syntax', () {
      final helper = AnalyzeByCss('''
        <p class="text-center padding-large">
          <a href="/prev">上一章</a>
          <a href="/next">下一章</a>
        </p>
        ''');

      expect(
        helper.getString(
          'p.text-center.padding-large@tag.a:contains(下一章)@href',
        ),
        '/next',
      );
    });

    test('16. unquoted attribute selectors are normalized compatibly', () {
      final helper = AnalyzeByCss('''
        <div style="text-indent: 2em;">正文内容</div>
        ''');

      expect(helper.getString('div[style=text-indent: 2em;]@text'), '正文内容');
    });

    test('17. :has(:contains()) works with adjacent sibling selectors', () {
      final helper = AnalyzeByCss('''
        <div class="info-chapters-title"><strong>《示例书》正文</strong></div>
        <div class="info-chapters">
          <a href="/chapter/1">第一章</a>
          <a href="/chapter/2">第二章</a>
        </div>
        <div class="info-chapters-title"><strong>《示例书》番外</strong></div>
        <div class="info-chapters">
          <a href="/extra/1">番外一</a>
        </div>
        ''');

      expect(
        helper.getStringList(
          '@CSS:.info-chapters-title:has(:contains(正文)) + .info-chapters a@text',
        ),
        ['第一章', '第二章'],
      );
    });

    test('18. :not(:has()) filters selector matches compatibly', () {
      final helper = AnalyzeByCss('''
        <div class="section with-link"><a href="/a">A</a></div>
        <div class="section plain"><span>B</span></div>
        ''');

      expect(helper.getString('@CSS:.section:not(:has(a))@text'), 'B');
    });

    test('19. nth-of-type with sibling combinator matches TOC anchors', () {
      final helper = AnalyzeByCss('''
        <div id="list">
          <dl>
            <dt>最新章节</dt>
            <a href="/latest"><dd>第784章 一声感慨</dd></a>
            <dt>目录章节</dt>
            <a href="/1"><dd>第1章 搬砖系统致富</dd></a>
            <a href="/2"><dd>第2章 降薪</dd></a>
          </dl>
        </div>
        ''');

      expect(helper.getStringList('#list@dt:nth-of-type(2)~a@href'), [
        '/1',
        '/2',
      ]);
    });

    test('20. nth-child and eq pseudos match Jsoup-style structure rules', () {
      final helper = AnalyzeByCss('''
        <ul class="stats">
          <li><span>一</span></li>
          <li><span>二</span></li>
          <li><span>三</span></li>
        </ul>
        ''');

      expect(
        helper.getStringList('@CSS:.stats > li:nth-child(n+2) span@text'),
        ['二', '三'],
      );
      expect(helper.getString('@CSS:.stats > li:eq(1) span@text'), '二');
    });

    test('21. regex attribute selectors match legado-style href patterns', () {
      final helper = AnalyzeByCss('''
        <div class="chapters">
          <a href="/read/1001">第一章</a>
          <a href="/read/1002">第二章</a>
          <a href="/book/1003">不是章节</a>
        </div>
        ''');

      expect(helper.getStringList('@CSS:a[href~=/read/\\d+]@text'), [
        '第一章',
        '第二章',
      ]);
    });
  });
}

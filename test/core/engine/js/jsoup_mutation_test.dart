import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/web_book/chapter_list_parser.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../../test_helper.dart';

/// 規則 JS 用 Jsoup 改元素、走訪節點。預期值都是 Legado 帶的 Jsoup 1.16.2
/// 跑同一段操作印出來的（排版關掉，夜讀的 HTML 輸出不排版）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();
  final skip = quickJsUnavailableReason();

  /// 跑一段規則 JS；`tags(清單)` 把節點寫成 `p#id` 或 `#text`。
  Future<dynamic> run(String js) async =>
      AnalyzeRule(source: BookSource(bookSourceUrl: 'https://site.test'))
          .evalJS('''
    function tags(list) {
      return list.map(function(n) {
        var name = n.nodeName();
        return name.charAt(0) === '#' ? name : n.tagName() + (n.id() ? '#' + n.id() : '');
      }).join(',');
    }
    $js
  ''', '');

  test(
    'createElement, appendChild, appendText and replaceWith (话本小说)',
    () async {
      expect(
        await run('''
        var doc = org.jsoup.Jsoup.parse('<div id=c><span class=t>x</span><span class=t>y</span></div>');
        doc.select('span.t').forEach(function(t) {
          var p = doc.createElement('p');
          var img = doc.createElement('img');
          img.attr('src', 'a.png');
          p.appendChild(img);
          p.appendText('名：' + t.text());
          t.replaceWith(p);
        });
        doc.getElementById('c').html()
      '''),
        '<p><img src="a.png">名：x</p><p><img src="a.png">名：y</p>',
      );
    },
    skip: skip,
  );

  test(
    'appendChild takes a clone and leaves the original (GAYRB腐漫画)',
    () async {
      expect(
        await run('''
        var d = org.jsoup.Jsoup.parse('<ul id=list><li>1</li><li>2</li></ul>');
        var w = d.createElement('div');
        w.appendChild(d.getElementById('list').clone());
        [w.select('li').size(), d.select('#list').size()].join('|')
      '''),
        '2|1',
      );
    },
    skip: skip,
  );

  test('a created link outside the page becomes a chapter (禁忌书屋)', () async {
    final source = BookSource.fromJson({
      'bookSourceName': '禁忌书屋',
      'bookSourceUrl': 'https://x.test',
      'ruleToc': {
        'chapterList':
            '<js>var list = []; var doc = org.jsoup.Jsoup.parse(result);'
            "var a = doc.createElement('a'); a.attr('href', baseUrl);"
            "a.text('第1章'); var t = doc.select('h1').first();"
            'if (t) a.text(t.text()); list.push(a);'
            "var b = doc.createElement('a'); b.attr('href', '/c/2');"
            "b.text('第2章'); list.push(b); result = list;</js>",
        'chapterName': 'text',
        'chapterUrl': 'href',
      },
    });
    final result = await ChapterListParser.parse(
      source: source,
      book: Book(
        bookUrl: 'https://x.test/t/1',
        origin: 'https://x.test',
        name: '書',
      ),
      body: '<html><body><h1>標題</h1></body></html>',
      baseUrl: 'https://x.test/t/1',
    );

    expect(result.chapters.map((c) => c.title), ['標題', '第2章']);
    expect(result.chapters.map((c) => c.url), [
      'https://x.test/t/1',
      'https://x.test/c/2',
    ]);
  }, skip: skip);

  test('siblings, indexes, closest and attribute lookups', () async {
    expect(
      await run('''
        var d = org.jsoup.Jsoup.parse('<div id=r><p id=a>A</p><p id=b>B</p><p id=c>C</p><p id=d>D</p></div>');
        var r = d.getElementById('r');
        [tags(d.getElementById('b').nextElementSiblings()),
         tags(d.getElementById('c').previousElementSiblings()),
         d.getElementById('c').firstElementSibling().id(),
         tags(r.getElementsByIndexEquals(1)),
         tags(r.getElementsByIndexLessThan(1)),
         tags(r.getElementsByIndexGreaterThan(1)),
         tags(r.getElementsByAttributeValueNot('id', 'a')),
         d.getElementById('a').closest('div').id(),
         d.getElementById('a').closest('p').id(),
         tags(d.select('#a, #b').nextAll()),
         tags(d.select('#c').prevAll()),
         tags(d.select('#a, #b').next('#c')),
         tags(d.getElementById('b').siblingNodes()),
         d.getElementById('c').siblingIndex()].join(' ')
      '''),
      'p#c,p#d p#b,p#a a p#b p#a p#c,p#d div#r,p#b,p#c,p#d r a '
      'p#b,p#c,p#d,p#c,p#d p#b,p#a p#c p#a,p#c,p#d 2',
    );
    expect(
      await run('''
        [tags(org.jsoup.Jsoup.parse('<div><p data-a=1>1</p><p data-b=2>2</p><p x=3>3</p></div>')
           .body().getElementsByAttributeStarting('data-')),
         tags(org.jsoup.Jsoup.parse("<a id=a1 href='/book/1'>1</a><a id=a2 href='/x'>2</a>")
           .getElementsByAttributeValueMatching('href', 'book/\\\\d')),
         tags(org.jsoup.Jsoup.parse('<p id=p1>第1章<b>x</b></p><p id=p2>序</p>')
           .getElementsMatchingOwnText('第\\\\d章'))].join(' ')
      '''),
      'p,p a#a1 p#p1',
    );
  }, skip: skip);

  test('moving and inserting children', () async {
    expect(
      await run('''
        var d = org.jsoup.Jsoup.parse('<div id=r><p id=a>A</p><p id=b>B</p><p id=c>C</p><p id=d>D</p></div>');
        var r = d.getElementById('r');
        var out = [];
        r.insertChildren(0, d.getElementById('d'));
        out.push(tags(r.children()));
        r.prependChild(d.getElementById('c'));
        out.push(tags(r.children()));
        var added = r.appendElement('SPAN');
        out.push(added.tagName() + '|' + tags(r.children()));
        r.insertChildren(-1, new org.jsoup.nodes.TextNode('t'));
        out.push(r.outerHtml());
        out.join(' ')
      '''),
      'p#d,p#a,p#b,p#c p#c,p#d,p#a,p#b span|p#c,p#d,p#a,p#b,span '
      '<div id="r"><p id="c">C</p><p id="d">D</p><p id="a">A</p><p id="b">B</p>'
      '<span></span>t</div>',
    );
  }, skip: skip);

  test('wrap and splitText', () async {
    expect(
      await run('''
        var w = org.jsoup.Jsoup.parse('<p>x</p>');
        w.selectFirst('p').wrap('<div class=a><b></b></div><i>rest</i>');
        var s = org.jsoup.Jsoup.parse('<p>Hello world</p>');
        var text = s.selectFirst('p').childNode(0);
        var tail = text.splitText(5);
        [w.body().html(), text.getWholeText() + '|' + tail.getWholeText() + '|' +
          s.selectFirst('p').childNodeSize()].join(' ')
      '''),
      '<div class="a"><b><p>x</p></b></div><i>rest</i> Hello| world|2',
    );
  }, skip: skip);

  test('traverse, forEach, forEachNode and filter', () async {
    expect(
      await run('''
        var div = org.jsoup.Jsoup.parse('<div><p>a<b>b</b></p>c</div>').body().child(0);
        var order = '';
        div.traverse(new org.jsoup.select.NodeVisitor({
          head: function(node, depth) { order += '+' + node.nodeName() + depth; },
          tail: function(node, depth) { order += '-' + node.nodeName(); }
        }));
        var each = '', eachNode = '';
        div.forEach(function(e) { each += e.tagName() + ','; });
        div.forEachNode({ accept: function(n) { eachNode += n.nodeName() + ','; } });
        var f = org.jsoup.Jsoup.parse('<div><p>keep</p><span>drop</span><p>keep2</p></div>');
        f.body().child(0).filter({
          head: function(node, depth) {
            return node.nodeName() == 'span'
              ? org.jsoup.select.NodeFilter.FilterResult.REMOVE
              : org.jsoup.select.NodeFilter.FilterResult.CONTINUE;
          }
        });
        [order, each, eachNode, f.body().html()].join(' ')
      '''),
      '+div0+p1+#text2-#text+b2+#text3-#text-b-p+#text1-#text-div div,p,b, '
      'div,p,#text,b,#text,#text, <div><p>keep</p><p>keep2</p></div>',
    );
  }, skip: skip);

  test('text, data, comments and the rest', () async {
    expect(
      await run('''
        var wo = org.jsoup.Jsoup.parse('<p>a  b<br>c<i>d</i> e</p>');
        var ti = org.jsoup.Jsoup.parse('<p>x</p>');
        ti.title('新標題');
        var tx = org.jsoup.Jsoup.parse('<p>a</p>');
        tx.text('body text');
        var sc = org.jsoup.Jsoup.parse('<div class=a id=b><p>x</p></div>').selectFirst('div');
        var comment = org.jsoup.Jsoup.parse('<p><!--hello--></p>').selectFirst('p').childNode(0);
        var missing;
        try { org.jsoup.Jsoup.parse('<p>x</p>').expectFirst('b'); } catch (e) { missing = e.message; }
        [wo.selectFirst('p').wholeOwnText().replace('\\n', '\\\\n'),
         wo.selectFirst('p').isBlock() + '|' + wo.selectFirst('i').isBlock(),
         tags(org.jsoup.Jsoup.parse('<div><p id=x>1</p><p id=y>2</p></div>').selectXpath("//p[@id='y']")),
         org.jsoup.nodes.TextNode.createFromEncoded('a &amp; b &lt;').getWholeText(),
         ti.title() + '|' + ti.select('head title').size(),
         sc.shallowClone().outerHtml(),
         sc.childNodesCopy()[0].outerHtml(),
         org.jsoup.Jsoup.parse('<script>var a=1;</script>').selectFirst('script').dataNodes()[0].getWholeData(),
         org.jsoup.Jsoup.parse('<p>x</p>').expectFirst('p').text(),
         missing,
         tx.html(),
         org.jsoup.Jsoup.parse('<p>x</p>').selectFirst('p').hasSameValue(
           org.jsoup.Jsoup.parse('<p>x</p>').selectFirst('p')),
         comment.getData() + '|' + comment.isXmlDeclaration(),
         org.jsoup.Jsoup.parse('<div><!--a--><p>x</p><!--b--></div>').select('div').comments().length
        ].join(' ~ ')
      '''),
      [
        r'a  b\nc e',
        'true|false',
        'p#y',
        'a & b <',
        '新標題|1',
        '<div class="a" id="b"></div>',
        '<p>x</p>',
        'var a=1;',
        'x',
        "No elements matched the query 'b' in the document.",
        '<html><head></head><body>body text</body></html>',
        'true',
        'hello|false',
        '2',
      ].join(' ~ '),
    );
  }, skip: skip);
}

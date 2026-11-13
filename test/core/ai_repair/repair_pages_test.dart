import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/repair_pages.dart';

const _toc = '''
<html><head><script>var x = 1;</script></head><body>
<div class="chapter-list">
  <div class="chapter-row hb-chapter-item"><span class="col-title"><a href="/book/1/1.html">第一章 開局</a></span></div>
  <div class="chapter-row hb-chapter-item"><span class="col-title"><a href="/book/1/2.html">第二章 夜雨</a></span></div>
</div>
<img class="j-lazy" src="/lazy.png" data-original="https://img.example/real.jpg">
</body></html>''';

void main() {
  test('every response with a page gets a number the AI can point at', () {
    final pages = RepairPages();
    final lines = pages.add(
      [
        'POST https://site.example/search/ 送出：q=1',
        '  ← https://site.example/search/ 200，10 字：<p>…',
      ],
      [
        (line: 'POST https://site.example/search/ 送出：q=1', body: null),
        (line: '  ← https://site.example/search/ 200，10 字：<p>…', body: _toc),
      ],
    );

    expect(lines.last, '  ← 頁 1｜https://site.example/search/ 200，10 字：<p>…');
    expect(pages[1]?.url, 'https://site.example/search/');
    expect(pages[1]?.body, _toc);
    expect(pages[2], isNull);
    expect(pages.add(['  ← https://site.example/ 200'], const []), [
      '  ← https://site.example/ 200',
    ], reason: '對不上的不登記');
  });

  test('the same address with the same page points back at the first one '
      'instead of sending it again', () {
    final pages = RepairPages();
    const line = '  ← https://site.example/1.html 200，40 位元組，精簡後 20 字：<p>正文…';
    final lines = pages.add(
      [line, line, line],
      [
        (line: line, body: _toc),
        (line: line, body: _toc),
        (line: line, body: '$_toc<p>新的</p>'),
      ],
    );

    expect(lines[0], contains('頁 1｜'));
    expect(
      lines[1],
      '  ← 頁 1｜https://site.example/1.html 200，40 位元組，精簡後 20 字：'
      '和頁 1 一樣（網址與內容都相同），內容不再重複',
    );
    expect(lines[2], contains('頁 2｜'), reason: '內容不同是另一頁');
    expect(pages.length, 2);
  });

  test('find gives the selector path and the element of each match', () {
    final found = findInPage(_toc, '第一章');

    expect(found, startsWith('共 1 處，這裡給第 1–1 處\n'));
    expect(
      found,
      contains(
        'div.chapter-list > div.chapter-row.hb-chapter-item > '
        'span.col-title > a',
      ),
    );
    expect(found, contains('<a href="/book/1/1.html">第一章 開局</a>'));
  });

  test('find also looks in attribute values, and in pages that are not '
      'HTML', () {
    expect(
      findInPage(_toc, 'real.jpg'),
      contains('img.j-lazy（在屬性 data-original 裡）'),
    );
    expect(
      findInPage('{"list":[{"name":"夜讀"}]}', '夜讀'),
      contains('"name":"夜讀"'),
    );
    expect(findInPage(_toc, '不在這裡'), '沒有找到');
  });

  test('find takes a regex, falls back to plain text when it does not '
      'compile, and says how to get the rest', () {
    final many =
        '<ul>${[for (var i = 1; i <= 12; i++) '<li>第$i章</li>'].join()}</ul>';
    final first = findInPage(many, r'第\d+章');
    expect(first, startsWith('共 12 處，這裡給第 1–10 處；從 "from":10 接著拿'));
    expect(findInPage(many, r'第\d+章', from: 10), contains('11. ul > li'));

    final literal = findInPage('<p>StatusCode(404)</p>', 'StatusCode(');
    expect(literal, startsWith('（不是合法的正則，照純文字找）共 1 處'));
  });

  test('read gives a range of the digested page, or of the raw page with '
      'scripts', () async {
    const page = RepairPage(3, 'https://site.example/', _toc);

    final digested = await readRepairPage(page, from: 0, length: 60);
    expect(digested, startsWith('# 頁 3（精簡後）第 0–60 字，共 '));
    expect(digested, isNot(contains('var x')));

    final raw = await readRepairPage(page, raw: true);
    expect(raw, contains('<script>var x = 1;</script>'));
    expect(raw, contains('共 ${_toc.length} 字'));
  });
}

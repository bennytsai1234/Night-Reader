import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/opening_facts.dart';
import 'package:night_reader/core/ai_repair/repair_pages.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/models/book_source.dart';

SourceProbeReport _probe(String header, String body) => SourceProbeReport(
  logs: const [],
  requests: [
    'http://m.site.example/s?q=x',
    '  ← http://m.site.example/s?q=x 200 $header，900 位元組：…',
  ],
  pages: [
    (line: 'http://m.site.example/s?q=x', body: null),
    (line: '  ← http://m.site.example/s?q=x 200 $header', body: body),
  ],
);

void main() {
  group('搜尋的編碼', () {
    BookSource source(String searchUrl) => BookSource(
      bookSourceUrl: 'http://m.site.example',
      searchUrl: searchUrl,
    );

    test('書源用 GBK 送、網站宣告 UTF-8 時寫出來', () {
      // 2026-11-13 QQ文学网。
      expect(
        searchCharsetFact(
          source('/s?q={{key}},{"charset": "gbk"}'),
          _probe('text/html; charset=UTF-8', '<html></html>'),
        ),
        allOf(contains('網址寫了 gbk'), contains('utf-8')),
      );
    });

    test('沒寫編碼時照 UTF-8 送，網站宣告 GBK 也寫；宣告在 meta 也認', () {
      expect(
        searchCharsetFact(
          source('/s?q={{key}}'),
          _probe('text/html', '<meta charset="gb2312"><p>x</p>'),
        ),
        allOf(contains('網址沒寫編碼，照 UTF-8'), contains('gb2312')),
      );
    });

    test('同一類的編碼不算不同', () {
      expect(
        searchCharsetFact(
          source('/s?q={{key}},{"charset":"GB2312"}'),
          _probe('text/html; charset=GBK', '<p>x</p>'),
        ),
        isNull,
      );
      expect(
        searchCharsetFact(
          source('/s?q={{key}}'),
          _probe('text/html; charset=utf8', '<p>x</p>'),
        ),
        isNull,
      );
    });
  });

  test('開場的網頁連到的別的網域照次數列，同一個網站的子網域不算', () {
    // 2026-11-13 肉肉屋：封面圖在姊妹站的網域。
    final fact = otherDomainsFact(
      BookSource(bookSourceUrl: 'https://www.rourou.example'),
      _probe(
        'text/html',
        '<img src="https://img.sister.example/a.jpg">'
            '<img src="https://img.sister.example/b.jpg">'
            '<a href="https://m.rourou.example/x">手機版</a>'
            '<a href="/book/1">書</a>'
            '<script>uaredirect("https://m.mirror.example/book/1");</script>',
      ),
    );
    expect(fact, contains('img.sister.example 2'));
    expect(fact, contains('m.mirror.example 1'));
    expect(fact, isNot(contains('rourou.example')));
  });

  test('網址不同、內容一字不差的頁面標出是哪一頁', () {
    final pages = RepairPages();
    const body = '<html><script>location.replace(x)</script></html>';
    final lines = pages.add(
      [
        '  ← http://a.example/ 200 text/html，2191 位元組：…',
        '  ← http://a.example/list 200 text/html，2191 位元組：…',
      ],
      [
        (line: '  ← http://a.example/ 200', body: body),
        (line: '  ← http://a.example/list 200', body: body),
      ],
    );
    expect(lines.first, isNot(contains('一字不差')));
    expect(lines.last, contains('（內容和頁 1 一字不差）'));
  });

  test('試抓可以從發現頁開始，照 exploreUrl 的寫法交給除錯', () {
    expect(
      probeStart('explore', keyword: '', url: '/sort/{{page}}.html'),
      '::/sort/{{page}}.html',
    );
  });
}

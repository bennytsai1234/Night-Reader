import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/opening_facts.dart';
import 'package:night_reader/core/ai_repair/repair_pages.dart';
import 'package:night_reader/core/ai_repair/source_probe.dart';
import 'package:night_reader/core/models/book_source.dart';

/// 「我的」照 UTF-8 與 GBK 編碼的樣子。
const _utf8Key = '%E6%88%91%E7%9A%84';
const _gbkKey = '%CE%D2%B5%C4';

/// 從搜尋開始的試抓：搜尋請求把關鍵字編成 [sentKey]，網站回 [header]。
/// [redirectFirst] 時先回一個宣告 UTF-8 的 302，再轉到結果頁。
SourceProbeReport _probe(
  String header,
  String body, {
  String sentKey = _utf8Key,
  bool redirectFirst = false,
}) => SourceProbeReport(
  logs: const [(10, '⇒開始搜尋關鍵字: 我的')],
  requests: [
    'POST http://m.site.example/s 送出：searchkey=$sentKey',
    if (redirectFirst) ...[
      '  ← http://m.site.example/s 302 text/html; charset=utf-8，0 位元組',
      'http://m.site.example/result（轉址）',
      '  ← http://m.site.example/result 200 $header，900 位元組：…',
    ] else
      '  ← http://m.site.example/s 200 $header，900 位元組：…',
    'http://m.site.example/book/1',
    '  ← http://m.site.example/book/1 200 text/html; charset=big5，900 位元組：…',
  ],
  pages: [
    (
      line: redirectFirst
          ? '  ← http://m.site.example/result 200 $header'
          : '  ← http://m.site.example/s 200 $header',
      body: body,
    ),
  ],
);

void main() {
  group('搜尋的編碼', () {
    final source = BookSource(bookSourceUrl: 'http://m.site.example');

    test('照試抓實際送出的編碼比：送 GBK、網站宣告 UTF-8 時寫出來', () {
      // 2026-11-13 QQ文学网。不管規則怎麼寫（寬鬆的選項、JS 組網址），看的
      // 是請求裡關鍵字被編成哪一種。
      expect(
        searchCharsetFact(
          source,
          _probe('text/html; charset=UTF-8', '<html></html>', sentKey: _gbkKey),
        ),
        allOf(contains('照 gbk 送「我的」'), contains('utf-8')),
      );
    });

    test('送 UTF-8、網站在 meta 宣告 GBK 也寫；宣告帶引號與空白也認', () {
      expect(
        searchCharsetFact(
          source,
          _probe('text/html', '<meta charset = "gb2312"><p>x</p>'),
        ),
        allOf(contains('照 utf-8 送'), contains('gb2312')),
      );
      expect(
        searchCharsetFact(
          source,
          _probe('text/html; charset="GBK"', '<p>x</p>'),
        ),
        contains('gbk'),
      );
    });

    test('同一類的編碼不算不同；看的是搜尋跟著轉址之後的結果頁', () {
      expect(
        searchCharsetFact(
          source,
          _probe('text/html; charset=GB2312', '<p>x</p>', sentKey: _gbkKey),
        ),
        isNull,
      );
      expect(
        searchCharsetFact(
          source,
          _probe(
            'text/html; charset=gbk',
            '<p>x</p>',
            sentKey: _gbkKey,
            redirectFirst: true,
          ),
        ),
        isNull,
        reason: '302 宣告的 UTF-8 不算，結果頁是 GBK',
      );
    });

    test('不是從搜尋開始、或關鍵字對不上時不寫', () {
      expect(
        searchCharsetFact(
          source,
          const SourceProbeReport(
            logs: [],
            requests: ['  ← x 200 charset=gbk'],
          ),
        ),
        isNull,
      );
    });
  });

  test('開場的網頁連到的別的網域照次數列，同一個網站的子網域不算', () {
    // 2026-11-13 肉肉屋：封面圖在姊妹站的網域。
    final fact = otherDomainsFact(
      BookSource(bookSourceUrl: 'https://www.site.example'),
      _probe(
        'text/html',
        '<img src="https://img.sister.example/a.jpg">'
            '<img src="https://img.sister.example/b.jpg">'
            '<a href="https://m2.site.example/x">手機版</a>'
            '<a href="/book/1">書</a>'
            '<script>uaredirect("https://m.mirror.example/book/1");</script>'
            '<p>Powered by 免费小说网（https://www.footer.example）</p>',
      ),
    );
    expect(fact, contains('img.sister.example 2'));
    expect(fact, contains('m.mirror.example 1'));
    expect(fact, contains('www.footer.example 1'), reason: '文字裡寫出的網址也算');
    expect(fact, isNot(contains('site.example 1')));
    expect(fact, isNot(contains('m2.site.example')));
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

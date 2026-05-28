import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/parsers/analyze_by_xpath.dart';

void main() {
  group('AnalyzeByXPath Tests', () {
    const html = '''
      <html>
        <body>
          <div id="test">
            <ul class="list">
              <li>Item 1</li>
              <li>Item 2</li>
            </ul>
            <a href="https://example.com" title="Example">Link</a>
          </div>
        </body>
      </html>
    ''';

    test('getElements - select nodes', () {
      final analyzer = AnalyzeByXPath(html);
      final elements = analyzer.getElements('//li');
      expect(elements.length, 2);
      expect(elements[0].text, 'Item 1');
    });

    test('getStringList - select attributes', () {
      final analyzer = AnalyzeByXPath(html);
      final hrefs = analyzer.getStringList('//a/@href');
      expect(hrefs, ['https://example.com']);
    });

    test('getStringList - select text', () {
      final analyzer = AnalyzeByXPath(html);
      final texts = analyzer.getStringList('//li/text()');
      expect(texts, ['Item 1', 'Item 2']);
    });

    test('getString - join with newline', () {
      final analyzer = AnalyzeByXPath(html);
      final result = analyzer.getString('//li/text()');
      expect(result, 'Item 1\nItem 2');
    });

    test('getStringList - returns outerHtml for element nodes', () {
      final analyzer = AnalyzeByXPath(html);
      final result = analyzer.getStringList('//li');
      expect(result.first, '<li>Item 1</li>');
    });

    test('Logical && operator', () {
      final analyzer = AnalyzeByXPath(html);
      final result = analyzer.getString('//li[1]/text() && //li[2]/text()');
      expect(result, 'Item 1\nItem 2');
    });

    test('Table tag auto-completion', () {
      // Test the _prepareHtml logic
      const tableFragment = '<td>Data</td>';
      final analyzer = AnalyzeByXPath(tableFragment);
      final result = analyzer.getString('//td/text()');
      expect(result, 'Data');
    });

    test('custom functions allText/textNodes/ownText/html', () {
      const richHtml =
          '<div class="content">Direct <span>Nested</span> Tail</div>';
      final analyzer = AnalyzeByXPath(richHtml);

      expect(analyzer.getString('//div/allText()'), 'Direct Nested Tail');
      expect(analyzer.getString('//div/textNodes()'), 'Direct\nTail');
      expect(analyzer.getString('//div/ownText()'), 'Direct Tail');
      expect(
        analyzer.getString('//div/html()'),
        '<div class="content">Direct <span>Nested</span> Tail</div>',
      );
      expect(
        analyzer.getString('//div/outerHtml()'),
        '<div class="content">Direct <span>Nested</span> Tail</div>',
      );
    });

    test('multi-class exact @class predicates are normalized compatibly', () {
      const searchHtml = '''
        <div class="one-row">
          <div class="col-md-3 col-sm-6 col-xs-6 home-truyendecu">
            <div class="each_truyen">
              <a href="/novel62406/"><img src="/cover.webp" alt="双燕归林"" itemprop="image" /></a>
            </div>
            <h3 itemprop="name">双燕归林</h3>
          </div>
        </div>
      ''';
      final analyzer = AnalyzeByXPath(searchHtml);

      final elements = analyzer.getElements(
        '//div[@class="one-row"]/div[@class="col-md-3 col-sm-6 col-xs-6 home-truyendecu"]',
      );

      expect(elements.length, 1);
      expect(elements.first.text, contains('双燕归林'));
    });

    test(
      'live-like broken search page still extracts book cards and item fields',
      () {
        const searchHtml = '''
          <!DOCTYPE html>
          <html lang="en-US">
            <body>
              <div class="container" id="truyen-slide">
                <h2 class="cate_title">
                  <span class="glyphicon glyphicon-edit"></span> 双燕 相关小说列表
                </h2>
                <div class="main-home">
                  <div class="col-xs-12 col-sm-12 col-md-9 col-truyen-main" style="margin-bottom: 15px">
                    <div class="row">
                      <div class="list list-thumbnail col-xs-12">
                        <div class="row">
                          <div class="one-row">
                            <div class="col-md-3 col-sm-6 col-xs-6 home-truyendecu" itemscope="" itemtype="http://schema.org/Book">
                              <div class="each_truyen">
                                <a href="/novel62406/" title="双燕归林">
                                  <span class="thumb-inside-item">
                                    <span class="hoan-thanh-mau">连载</span>
                                  </span>
                                  <img width="100" height="136" src="https://img.8xsk.top/files/titlepic/bookimgalc50679.webp" class="attachment-image2 size-image2 wp-post-image" alt="双燕归林"" itemprop="image" srcset="https://img.8xsk.top/files/titlepic/bookimgalc50679.webp 100w" />
                                </a>
                              </div>
                              <div class="caption">
                                <a href="/novel62406/" title="T双燕归林" itemprop="url">
                                  <h3 itemprop="name">双燕归林</h3>
                                </a>
                              </div>
                            </div>
                            <div class="col-md-3 col-sm-6 col-xs-6 home-truyendecu" itemscope="" itemtype="http://schema.org/Book">
                              <div class="each_truyen">
                                <a href="/novel2709/" title="黑骑双燕">
                                  <img width="100" height="136" src="https://img.8xsk.top/files/novel/bookimg4003s.jpg" class="attachment-image2 size-image2 wp-post-image" alt="黑骑双燕"" itemprop="image" />
                                </a>
                              </div>
                              <div class="caption">
                                <a href="/novel2709/" title="T黑骑双燕" itemprop="url">
                                  <h3 itemprop="name">黑骑双燕</h3>
                                </a>
                              </div>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </body>
          </html>
        ''';
        final analyzer = AnalyzeByXPath(searchHtml);

        final elements = analyzer.getElements(
          '//div[@class="one-row"]/div[@class="col-md-3 col-sm-6 col-xs-6 home-truyendecu"]',
        );

        expect(elements, hasLength(2));

        final itemAnalyzer = AnalyzeByXPath(elements.first);
        expect(itemAnalyzer.getString('//h3[@itemprop="name"]/text()'), '双燕归林');
        expect(
          itemAnalyzer.getString('//div[@class="each_truyen"]/a/@href'),
          '/novel62406/',
        );
        expect(
          itemAnalyzer.getString('//div[@class="each_truyen"]/a/img/@src'),
          'https://img.8xsk.top/files/titlepic/bookimgalc50679.webp',
        );
      },
    );

    test('element context keeps self-matching absolute xpath selections', () {
      const searchHtml = '''
          <ul class="list">
            <li>
              <a href="/book/1/">Book 1</a>
              <p class="bookname"><a>Book 1</a></p>
            </li>
            <li>
              <a href="/book/2/">Book 2</a>
              <p class="bookname"><a>Book 2</a></p>
            </li>
          </ul>
        ''';
      final analyzer = AnalyzeByXPath(searchHtml);
      final elements = analyzer.getElements('//ul[@class="list"]/li');

      expect(elements, hasLength(2));

      final itemAnalyzer = AnalyzeByXPath(elements.first);
      expect(itemAnalyzer.getString('//li/a[1]/@href'), '/book/1/');
      expect(
        itemAnalyzer.getString('//li/p[@class="bookname"]/a/text()'),
        'Book 1',
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

void main() {
  setupTestDI();
  TestWidgetsFlutterBinding.ensureInitialized();
  final quickJsSkip = quickJsUnavailableReason();

  group('AnalyzeUrl 解析書源網址範本', () {
    test('搜尋關鍵字預設以 UTF-8 編碼代入 {{key}}', () {
      final analyzeUrl = AnalyzeUrl(
        'https://example.com/search?q={{key}}&p={{page}}',
        key: '西遊記',
        page: 2,
      );

      expect(
        analyzeUrl.url,
        'https://example.com/search?q=%E8%A5%BF%E9%81%8A%E8%A8%98&p=2',
      );
      expect(analyzeUrl.method, 'GET');
    });

    test('選項指定 GBK 時關鍵字以 GBK 位元組編碼', () {
      final analyzeUrl = AnalyzeUrl(
        'https://example.com/s?q={{key}},{"charset":"gbk"}',
        key: '西游',
      );

      expect(analyzeUrl.url, 'https://example.com/s?q=%CE%F7%D3%CE');
      expect(analyzeUrl.charset, 'gbk');
    });

    test('<a,b,c> 依頁碼取對應項目，超過範圍時取最後一項', () {
      const rule = 'https://example.com/list<,_2,_3>.html';

      expect(AnalyzeUrl(rule, page: 1).url, 'https://example.com/list.html');
      expect(AnalyzeUrl(rule, page: 2).url, 'https://example.com/list_2.html');
      expect(AnalyzeUrl(rule, page: 9).url, 'https://example.com/list_3.html');
    });

    test('逗號後的 JSON 選項設定方法、內文、標頭與 WebView', () {
      final analyzeUrl = AnalyzeUrl(
        'https://example.com/search, {"method":"post","body":"kw={{key}}",'
        '"headers":{"Referer":"https://example.com/"},"webView":true}',
        key: 'a b',
      );

      expect(analyzeUrl.url, 'https://example.com/search');
      expect(analyzeUrl.method, 'POST');
      expect(analyzeUrl.body, 'kw=a%20b');
      expect(analyzeUrl.headerMap['Referer'], 'https://example.com/');
      expect(analyzeUrl.useWebView, isTrue);
    });

    test('相對路徑以 baseUrl 解析，沒有 baseUrl 時用書源網址', () {
      expect(
        AnalyzeUrl(
          '/book/1.html',
          baseUrl: 'https://example.com/list/page.html',
        ).url,
        'https://example.com/book/1.html',
      );
      expect(
        AnalyzeUrl(
          'chapter/2.html',
          source: BookSource(bookSourceUrl: 'https://example.com/novel/'),
        ).url,
        'https://example.com/novel/chapter/2.html',
      );
    });

    test('書源的 header 先注入，網址選項的同名標頭覆寫它', () {
      final analyzeUrl = AnalyzeUrl(
        'https://example.com/a,{"headers":{"User-Agent":"rule"}}',
        source: BookSource(
          bookSourceUrl: 'https://example.com',
          header: '{"User-Agent":"source","X-Token":"t"}',
        ),
      );

      expect(analyzeUrl.headerMap['User-Agent'], 'rule');
      expect(analyzeUrl.headerMap['X-Token'], 't');
    });

    test('{{}} 內的 JS 運算式以頁碼求值', () {
      final analyzeUrl = AnalyzeUrl(
        'https://example.com/list?offset={{(page-1)*20}}',
        page: 3,
      );

      expect(analyzeUrl.url, 'https://example.com/list?offset=40');
    }, skip: quickJsSkip);
  });
}

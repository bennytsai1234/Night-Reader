import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/models/book_source.dart';

import '../../test_helper.dart';

void main() {
  setupTestDI();
  TestWidgetsFlutterBinding.ensureInitialized();
  final quickJsSkip = quickJsUnavailableReason();

  group('AnalyzeUrl 解析書源網址範本', () {
    // 同 Legado：{{key}} 代入原文（java.url 看到的），送出時才編碼查詢參數。
    test('搜尋關鍵字代入原文，送出時以 UTF-8 編碼', () {
      final analyzeUrl = AnalyzeUrl(
        'https://example.com/search?q={{key}}&p={{page}}',
        key: '西遊記',
        page: 2,
      );

      expect(analyzeUrl.url, 'https://example.com/search?q=西遊記&p=2');
      expect(
        analyzeUrl.requestUrl,
        'https://example.com/search?q=%E8%A5%BF%E9%81%8A%E8%A8%98&p=2',
      );
      expect(analyzeUrl.method, 'GET');
    });

    test('選項指定 GBK 時查詢參數以 GBK 位元組編碼', () {
      final analyzeUrl = AnalyzeUrl(
        'https://example.com/s?q={{key}},{"charset":"gbk"}',
        key: '西游',
      );

      expect(analyzeUrl.requestUrl, 'https://example.com/s?q=%CE%F7%D3%CE');
      expect(analyzeUrl.charset, 'gbk');
    });

    test('已經編碼過的查詢參數照原樣送出', () {
      expect(
        AnalyzeUrl('https://example.com/s?q=%E8%A5%BF&a=1|2').requestUrl,
        'https://example.com/s?q=%E8%A5%BF&a=1|2',
      );
    });

    test('POST 表單照 Java URLEncoder 編碼，JSON 內文照原文', () {
      final form = AnalyzeUrl(
        'https://example.com/s,{"method":"post","body":"kw={{key}}&t=1"}',
        key: '西 遊',
      );
      expect(form.body, 'kw=西 遊&t=1');
      expect(form.requestBody, 'kw=%E8%A5%BF+%E9%81%8A&t=1');
      expect(
        form.requestHeaders['Content-Type'],
        'application/x-www-form-urlencoded',
      );

      final gbk = AnalyzeUrl(
        'https://example.com/s,{"method":"POST","body":"kw={{key}}",'
        '"charset":"gbk"}',
        key: '西游',
      );
      expect(gbk.requestBody, 'kw=%CE%F7%D3%CE');

      final json = AnalyzeUrl(
        'https://example.com/api,{"method":"POST",'
        '"body":{"keyword":"{{key}}","page":{{page}}}}',
        key: '西遊',
        page: 2,
      );
      expect(json.requestBody, '{"keyword":"西遊","page":2}');
      expect(
        json.requestHeaders['Content-Type'],
        'application/json; charset=UTF-8',
      );

      final typed = AnalyzeUrl(
        'https://example.com/api,{"method":"POST","body":"a b",'
        '"headers":{"content-type":"text/plain"}}',
      );
      expect(typed.requestBody, 'a b');
      expect(typed.requestHeaders.containsKey('Content-Type'), isFalse);
    });

    test('網址選項照 Legado 讀：標頭可以是 JSON 文字、webView 看真假值', () {
      final analyzeUrl = AnalyzeUrl(
        'https://example.com/a,{"headers":"{\\"X-A\\":\\"1\\"}",'
        '"webView":"false","retry":"2","type":"zip","serverID":7,'
        '"webViewDelayTime":-5}',
      );
      expect(analyzeUrl.headerMap['X-A'], '1');
      expect(analyzeUrl.useWebView, isFalse);
      expect(analyzeUrl.retry, 2);
      expect(analyzeUrl.type, 'zip');
      expect(analyzeUrl.serverID, 7);
      expect(analyzeUrl.webViewDelayTime, 0);

      expect(
        AnalyzeUrl('https://example.com/a,{"webView":1}').useWebView,
        isTrue,
      );
      expect(
        AnalyzeUrl('https://example.com/a,{"method":"put"}').method,
        'GET',
      );
    });

    test('data: 網址直接解出位元組', () async {
      final bytes = await AnalyzeUrl(
        'data:application/octet-stream;base64,5aSc6K6A',
      ).getByteArray();
      expect(utf8.decode(bytes), '夜讀');
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
      expect(analyzeUrl.body, 'kw=a b');
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

    // Legado 網址裡的 JS：java 是這個請求，看得到書源標頭；JS 前面的文字
    // 取代目前結果，`@result` 換成目前結果。
    test('網址裡的 JS 拿到這個請求', () {
      final analyzeUrl = AnalyzeUrl(
        'https://example.com/a<js>result + "?t=" + '
        'java.headerMap.get("X-Token") + "&p=" + java.isPost()</js>',
        source: BookSource(
          bookSourceUrl: 'https://example.com',
          header: '{"X-Token":"t1"}',
        ),
      );
      expect(analyzeUrl.url, 'https://example.com/a?t=t1&p=false');

      // java.headerMap 就是這個請求的標頭：網址 JS 改了，送出時就帶著。
      final signed = AnalyzeUrl(
        'https://example.com/s,{"js":"java.headerMap.put(\'X-Sign\', \'abc\'); result"}',
      );
      expect(signed.headerMap['X-Sign'], 'abc');
      expect(signed.url, 'https://example.com/s');

      expect(
        AnalyzeUrl(
          'https://example.com/tts?t={{speakText + "!"}}&s={{speakSpeed * 2}}',
          speakText: '夜讀',
          speakSpeed: 5,
        ).url,
        'https://example.com/tts?t=夜讀!&s=10',
      );

      final replaced = AnalyzeUrl('@js:"https://example.com/b"\n');
      expect(replaced.url, 'https://example.com/b');
    }, skip: quickJsSkip);
  });
}

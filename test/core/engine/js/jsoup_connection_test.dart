import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../support/source_isolate_harness.dart';
import '../../../test_helper.dart';

/// 規則 JS 的 `org.jsoup.Jsoup.connect(…)`。送出的網址、內文與標頭，和錯誤
/// 訊息，都是 Legado 帶的 Jsoup 1.16.2 對同一個本機伺服器跑出來的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = quickJsUnavailableReason();
  final isolates = SourceIsolateHarness();
  late HttpServer server;
  late String baseUrl;

  setUpAll(() async {
    await isolates.start();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final response = request.response;
      response.headers.set('Set-Cookie', 'sid=abc; Path=/');
      switch (request.uri.path) {
        case '/missing':
          response.statusCode = HttpStatus.notFound;
          response.headers.contentType = ContentType.html;
        case '/json':
          response.headers.set('Content-Type', 'application/json');
        case '/gbk':
          // 標頭沒寫字元集，網頁的 <meta> 寫 GBK。
          response.headers.set('Content-Type', 'text/html');
          response.add([
            ...ascii.encode('<html><head><meta charset="gbk"></head><body>'),
            0xD2, 0xB9, 0xB6, 0xC1, // 夜读
            ...ascii.encode('</body></html>'),
          ]);
          await response.close();
          return;
        default:
          response.headers.contentType = ContentType.html;
      }
      if (request.method != 'HEAD') {
        response.write(
          '${request.method} ${request.uri} body=$body '
          'ct=${request.headers.value('content-type')} '
          'cookie=${request.headers['cookie']} '
          'ua=${request.headers.value('user-agent')} '
          'x=${request.headers['x-a']}',
        );
      }
      await response.close();
    });
  });
  tearDownAll(() async {
    await server.close(force: true);
    await isolates.stop();
  });

  Future<String> run(String js) => evaluateInSourceIsolate(js);
  const ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/79.0.3945.130 Safari/537.36';

  test('GET puts the form data in the URL', () async {
    expect(
      await run(
        "org.jsoup.Jsoup.connect('$baseUrl/a?x=1').data('k', '中 文')"
        ".data('b', '2').execute().body()",
      ),
      'GET /a?x=1&k=%E4%B8%AD+%E6%96%87&b=2 body= ct=null cookie=null '
      'ua=$ua x=null',
    );
  }, skip: skip);

  test('POST sends the form data, or the request body with the data in the '
      'URL', () async {
    expect(
      await run(
        "org.jsoup.Jsoup.connect('$baseUrl/p').data('k', '中 文')"
        '.method(org.jsoup.Connection.Method.POST).execute().body()',
      ),
      'POST /p body=k=%E4%B8%AD+%E6%96%87 '
      'ct=application/x-www-form-urlencoded; charset=UTF-8 cookie=null '
      'ua=$ua x=null',
    );
    expect(
      await run(
        "org.jsoup.Jsoup.connect('$baseUrl/p').requestBody('{\"a\":1}')"
        ".data('q', '1').header('Content-Type', 'application/json')"
        '.method(org.jsoup.Connection.Method.POST).execute().body()',
      ),
      'POST /p?q=1 body={"a":1} ct=application/json cookie=null ua=$ua x=null',
    );
  }, skip: skip);

  test('DELETE with the cookie and headers the source gives (Aff)', () async {
    // Jsoup 送兩個 Cookie 標頭（b=2、a=1），這裡併成一個，伺服器看到的一樣。
    expect(
      await run(
        "org.jsoup.Jsoup.connect('$baseUrl/d')"
        '.method(org.jsoup.Connection.Method.DELETE)'
        ".header('Cookie', 'a=1').cookie('b', '2').header('X-A', '1')"
        '.execute().body()',
      ),
      'DELETE /d body= ct=application/x-www-form-urlencoded; charset=UTF-8 '
      'cookie=[a=1; b=2] ua=$ua x=[1]',
    );
  }, skip: skip);

  test(
    'HTTP errors throw unless ignored (禁漫天堂 checks lines with HEAD)',
    () async {
      expect(
        await run('''
        var message;
        try { org.jsoup.Jsoup.connect('$baseUrl/missing').execute(); }
        catch (e) { message = e.message; }
        var r = org.jsoup.Jsoup.connect('$baseUrl/missing')
          .method(org.jsoup.Connection.Method.HEAD).timeout(10000)
          .ignoreHttpErrors(true).execute();
        [message, r.statusCode(), r.statusMessage(), r.body().length].join('|')
      '''),
        'HTTP error fetching URL. Status=404, URL=[$baseUrl/missing]|404|'
        'Not Found|0',
      );
    },
    skip: skip,
  );

  test('non-text responses throw unless ignored (禁忌书屋 reads JSON)', () async {
    expect(
      await run('''
        var message;
        try { org.jsoup.Jsoup.connect('$baseUrl/json').execute(); }
        catch (e) { message = e.message; }
        var r = org.jsoup.Jsoup.connect('$baseUrl/json').ignoreContentType(true).execute();
        [message, r.contentType(), String(r.charset()), r.cookie('sid'),
         r.header('content-type'), r.body().indexOf('GET /json') === 0].join('|')
      '''),
      'Unhandled content type. Must be text/*, application/xml, or '
      'application/*+xml|application/json|null|abc|application/json|true',
    );
  }, skip: skip);

  test(
    'get() parses the page; parse() reads the charset from <meta>',
    () async {
      expect(
        await run('''
        var page = org.jsoup.Jsoup.connect('$baseUrl/g').userAgent('UA/1').get();
        var gbk = org.jsoup.Jsoup.connect('$baseUrl/gbk').execute();
        [page.body().text(), gbk.parse().body().text(), gbk.charset()].join('|')
      '''),
        'GET /g body= ct=null cookie=null ua=UA/1 x=null|夜读|GBK',
      );
    },
    skip: skip,
  );
}

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/js/js_response.dart';
import 'package:night_reader/core/engine/web_book/login_check.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/network/redirects.dart';
import 'package:night_reader/core/network/str_response.dart';

import '../../../test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();
  final skip = quickJsUnavailableReason();

  final response = StrResponse(
    url: 'https://www.site.test/search/我的世界/1',
    body: '<div class="book">我的世界</div>',
    headers: const {
      'content-type': ['text/html'],
    },
    raw: Response(
      requestOptions: RequestOptions(path: 'https://www.site.test/search/1'),
      statusCode: 200,
      statusMessage: 'OK',
    ),
  );

  StrResponse check(String loginCheckJs) => runLoginCheckJs(
    AnalyzeUrl(
      '/search/{{key}}/{{page}}',
      key: '我的世界',
      page: 2,
      source: BookSource(
        bookSourceUrl: 'https://www.site.test',
        loginCheckJs: loginCheckJs,
      ),
    ),
    response,
  );

  // Legado 用這次請求（AnalyzeUrl.evalJS）跑登入檢查，這些值都在。
  test('loginCheckJs sees the request key, page and site', () {
    final checked = check('''
      if (key != '我的世界') throw 'key ' + key;
      if (page != 2) throw 'page ' + page;
      if (baseUrl != 'https://www.site.test') throw 'baseUrl ' + baseUrl;
      result
    ''');

    expect(checked, same(response));
  }, skip: skip);

  // 冷冷文学這類書源的登入檢查：把 result 當成 Legado 的 StrResponse 讀，
  // 沒問題就原樣傳回。以前交給它的是一段文字，`result.body()` 就出錯。
  test('loginCheckJs reads the response like Legado and passes it on', () {
    final checked = check('''
      var body = result.body();
      if (result.code() != 200 || body.indexOf('请登录') >= 0) {
        throw '需要登录';
      }
      if (result.url().indexOf('/search/') < 0) throw 'wrong url';
      if (result.headers()['content-type'][0] != 'text/html') throw 'headers';
      result
    ''');

    expect(checked, same(response));
  }, skip: skip);

  // Legado 內建的朗讀設定就這樣寫：headers() 是 OkHttp 的 Headers。
  test('headers() and errorBody() work like OkHttp in Legado', () {
    final checked = check('''
      var headers = result.headers();
      if (headers.get('Content-Type') != 'text/html') throw 'get';
      if (headers.get('x-missing') !== null) throw 'missing';
      if (headers.values('content-type').size() != 1) throw 'values';
      if (headers.names().get(0) != 'content-type') throw 'names';
      if (result.raw().headers().get('CONTENT-TYPE') != 'text/html') throw 'raw';
      if (result.errorBody() !== null) throw 'errorBody';
      var failed = buildHttpResponse({ code: 403, body: '请登录', headers: {} });
      if (failed.errorBody().string() != '请登录') throw 'failed errorBody';
      result
    ''');

    expect(checked, same(response));
  }, skip: skip);

  test('a response the check builds replaces the fetched one', () {
    final checked = check('''
      buildHttpResponse({
        url: 'https://www.site.test/after-login',
        body: '重抓的內容',
        code: 200,
        headers: {}
      })
    ''');

    expect(checked, isNot(same(response)));
    expect(checked.url, 'https://www.site.test/after-login');
    expect(checked.body, '重抓的內容');
  }, skip: skip);

  test('anything else keeps the fetched response', () {
    expect(check('result.body().length'), same(response));
  }, skip: skip);

  group('responses in other rule results', () {
    AnalyzeRule rule() =>
        AnalyzeRule(source: BookSource(bookSourceUrl: 'https://www.site.test'));

    test('fields a rule adds to a response are kept', () {
      final result = rule().evalJS('''
        var r = buildHttpResponse({ url: 'https://www.site.test/1', body: 'x' });
        r.name = '書名';
        [r]
      ''', null);

      expect(result, [containsPair('name', '書名')]);
    }, skip: skip);

    test('a response inside an object reaches the next rule', () {
      final analyzer = rule();
      final wrapped = analyzer.evalJS('({reply: result})', response);
      expect((wrapped as Map)['reply'], same(response));

      expect(analyzer.evalJS('result.reply.body()', wrapped), response.body);
    }, skip: skip);
  });

  test('a rebuilt response keeps redirects the HTTP client followed', () {
    final redirected = StrResponse(
      url: 'https://www.site.test/new',
      body: '',
      headers: const {},
      raw: Response(
        requestOptions: RequestOptions(path: 'https://www.site.test/old'),
        statusCode: 200,
        redirects: [RedirectRecord(302, 'GET', Uri.parse('/new'))],
      ),
    );

    final rebuilt = responseFromJs(responseToJs(redirected));

    expect(rebuilt.isRedirect, isTrue);
    expect(rebuilt.raw.redirectedUris, [
      Uri.parse('https://www.site.test/new'),
    ]);
  });

  test('a failing check says it was the login check', () {
    expect(
      () => check('result.notAMethod()'),
      throwsA(
        isA<ParsingException>()
            .having((e) => e.message, 'message', contains('登入檢查'))
            .having((e) => e.url, 'url', response.url),
      ),
    );
  }, skip: skip);
}

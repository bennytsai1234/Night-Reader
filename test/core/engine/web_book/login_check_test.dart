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
import 'package:night_reader/core/services/cache_manager.dart';

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

  group('LoginWall', () {
    StrResponse page(String body) => StrResponse(
      url: 'https://www.site.test/book/1',
      body: body,
      headers: const {},
      raw: Response(
        requestOptions: RequestOptions(path: 'https://www.site.test/book/1'),
        statusCode: 200,
      ),
    );
    const headerLink = '<header><a href="/login">請先登錄</a></header>';

    // 網站頁首的登入連結不讓解析得出內容的頁面失敗（ADR 0038）。
    test('a login link on a page that parses is not a wall', () {
      final linked = page('$headerLink<ul><li>第一章</li></ul>');

      expect(() => LoginWall.checkToc(linked, empty: false), returnsNormally);
      expect(
        () => LoginWall.checkContent(linked, '第一章的正文' * 50),
        returnsNormally,
      );
    });

    test('an empty page that looks like a login page is a wall', () {
      final login = page(headerLink);

      expect(
        () => LoginWall.checkToc(login, empty: true),
        throwsA(
          isA<LoginCheckException>().having(
            (e) => e.message,
            'message',
            '目錄需要登入後閱讀',
          ),
        ),
      );
      expect(
        () => LoginWall.checkContent(login, ' '),
        throwsA(isA<LoginCheckException>()),
      );
    });

    test('an empty page elsewhere is not explained as a wall', () {
      final missing = page('<p>沒有這本書</p>');

      expect(() => LoginWall.checkToc(missing, empty: true), returnsNormally);
      expect(() => LoginWall.checkContent(missing, ''), returnsNormally);
    });

    // 付費或要登入的章節常在正文區塊只放一句登入提示；第一頁免費、後面幾頁
    // 才要登入時，每一頁都要判斷，不能因為第一頁夠長就把半章當成一整章。
    test('a page whose content is only a login prompt is a wall', () {
      final prompt = page('<div id="content">請先登錄後閱讀</div>');

      expect(
        () => LoginWall.checkContent(prompt, '請先登錄後閱讀'),
        throwsA(
          isA<LoginCheckException>().having(
            (e) => LoginCheckException.describes(e.message),
            'describes',
            isTrue,
          ),
        ),
      );
      expect(
        () => LoginWall.checkContent(null, '請先登錄後閱讀'),
        throwsA(isA<LoginCheckException>()),
      );
    });
  });

  group('login header', () {
    final source = BookSource(
      bookSourceUrl: 'https://header.site.test',
      loginUrl: '/login',
      header: '{"User-Agent": "Reader", "Authorization": "none"}',
    );
    tearDown(() => CacheManager().deleteMemory(source.loginHeaderCacheKey));

    // 同 Legado：登入標頭跟著每次請求送出，蓋過書源 header，網址選項再蓋過它。
    test('goes with every request of a source that has login', () {
      CacheManager().putMemory(
        source.loginHeaderCacheKey,
        '{"Authorization": "Bearer abc", "X-Token": "t"}',
      );

      final plain = AnalyzeUrl('/book/1', source: source);
      expect(plain.headerMap['User-Agent'], 'Reader');
      expect(plain.headerMap['Authorization'], 'Bearer abc');
      expect(plain.headerMap['X-Token'], 't');

      final withOption = AnalyzeUrl(
        '/book/1,{"headers": {"X-Token": "from-url"}}',
        source: source,
      );
      expect(withOption.headerMap['X-Token'], 'from-url');
    }, skip: skip);

    test('is not looked up for sources without login', () {
      final noLogin = BookSource(bookSourceUrl: 'https://header.site.test');
      CacheManager().putMemory(noLogin.loginHeaderCacheKey, '{"X-Token": "t"}');

      expect(AnalyzeUrl('/book/1', source: noLogin).headerMap, isEmpty);
    }, skip: skip);
  });
}

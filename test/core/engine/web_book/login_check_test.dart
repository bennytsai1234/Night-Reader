import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/login_check.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book_source.dart';
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
    BookSource(
      bookSourceUrl: 'https://www.site.test',
      loginCheckJs: loginCheckJs,
    ),
    response,
  );

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

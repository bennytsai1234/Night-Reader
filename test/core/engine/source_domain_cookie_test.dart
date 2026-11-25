import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/cookie_store.dart';

import '../../test_helper.dart';

/// 書源的 Cookie 照書源網址的網域存（Legado `AnalyzeUrl.domain` 是
/// `getSubDomain(source.getKey())`）：書源打別的網域時，登入存下的 Cookie
/// 照樣送出。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupTestDI();

  setUp(() async {
    await CookieStore().removeCookie('https://www.novel.test');
    await CookieStore().removeCookie('https://api.other.test');
  });

  BookSource source() => BookSource(
    bookSourceUrl: 'https://www.novel.test',
    bookSourceName: 'Cookie',
  );

  test('打別的網域時帶著書源網域存的 Cookie', () async {
    await CookieStore().setCookie('https://www.novel.test', 'sid=login');
    final request = await AnalyzeUrl(
      'https://api.other.test/search?k=1',
      source: source(),
    ).playbackRequest();
    expect(request.headers['Cookie'], contains('sid=login'));
  });

  test('請求網域自己存的與規則給的照樣送，規則給的同名優先', () async {
    await CookieStore().setCookie('https://www.novel.test', 'sid=login; a=1');
    await CookieStore().setCookie('https://api.other.test', 'cf=pass');
    final request = await AnalyzeUrl(
      'https://api.other.test/s,{"headers":{"Cookie":"a=2"}}',
      source: source(),
    ).playbackRequest();
    final cookie = CookieStore().cookieToMap(request.headers['Cookie']!);
    expect(cookie, {'sid': 'login', 'a': '2', 'cf': 'pass'});
  });

  test('登入標頭裡的 Cookie 併進書源原本存的，不整個蓋掉', () async {
    await CookieStore().setCookie('https://www.novel.test', 'old=1; sid=x');
    await source().putLoginHeader('{"Cookie":"sid=new"}');
    final stored = CookieStore().cookieToMap(
      await CookieStore().getCookie('https://www.novel.test'),
    );
    expect(stored, {'old': '1', 'sid': 'new'});
  });

  test('兩邊同名時請求網域的優先；只有一邊有時照原字串送', () async {
    await CookieStore().setCookie('https://www.novel.test', 'sid=source');
    await CookieStore().setCookie('https://api.other.test', 'sid=api');
    final both = await AnalyzeUrl(
      'https://api.other.test/s',
      source: source(),
    ).playbackRequest();
    expect(CookieStore().cookieToMap(both.headers['Cookie']!), {'sid': 'api'});

    await CookieStore().removeCookie('https://api.other.test');
    final onlySource = await AnalyzeUrl(
      'https://api.other.test/s',
      source: source(),
    ).playbackRequest();
    expect(onlySource.headers['Cookie'], 'sid=source');
  });

  test('同一個請求再送一次時，網站這期間更新的 Cookie 不被上次的蓋掉', () async {
    await CookieStore().setCookie('https://www.novel.test', 'sid=old');
    final analyzeUrl = AnalyzeUrl(
      'https://api.other.test/s,{"headers":{"Cookie":"a=1"}}',
      source: source(),
    );
    await analyzeUrl.playbackRequest();
    await CookieStore().setCookie('https://www.novel.test', 'sid=new');
    final again = await analyzeUrl.playbackRequest();
    expect(CookieStore().cookieToMap(again.headers['Cookie']!), {
      'sid': 'new',
      'a': '1',
    });
  });

  test('外來的網址不帶書源的 Cookie 與登入標頭', () async {
    await CookieStore().setCookie('https://www.novel.test', 'sid=login');
    final s = source();
    await s.putLoginHeader('{"Authorization":"Bearer t"}');
    addTearDown(s.removeLoginHeader);

    final request = await AnalyzeUrl(
      'https://api.other.test/search?k=1',
      source: s,
      loginHeaders: false,
      sourceCookie: false,
    ).playbackRequest();

    expect(request.headers['Cookie'], isNull);
    expect(request.headers['Authorization'], isNull);
  });

  test('登入標頭存的 Cookie 登出後清乾淨', () async {
    await CookieStore().setCookie('https://www.novel.test', 'old=1');
    final s = source();
    await s.putLoginHeader('{"Cookie":"sid=new"}');
    await s.clearLoginData();
    expect(await CookieStore().getCookie('https://www.novel.test'), isEmpty);
  });
}

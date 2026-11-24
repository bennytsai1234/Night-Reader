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
}

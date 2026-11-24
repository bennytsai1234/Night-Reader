import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/backstage_webview.dart';
import 'package:night_reader/core/network/cookie_store.dart';

/// 背景網頁載完一頁：瀏覽器裡那一頁的 Cookie 存進書源（同 Legado
/// `BackstageWebView.setCookie`），之後不開網頁的請求帶得到。
void main() {
  tearDown(() => CookieStore().clearAll());

  test('the cookies the page wrote are saved under the source', () async {
    Uri? asked;
    await BackstageWebView.saveCookies(
      'https://www.site.test',
      'https://www.site.test/book/1',
      read: (uri) async {
        asked = uri;
        return 'jsl=abc; sid=1';
      },
    );

    expect(asked, Uri.parse('https://www.site.test/book/1'));
    expect(
      await CookieStore().getCookie('https://www.site.test'),
      'jsl=abc; sid=1',
    );
  });

  test('a page with no cookies leaves the stored ones alone', () async {
    await CookieStore().setCookie('https://www.site.test', 'sid=1');

    await BackstageWebView.saveCookies(
      'https://www.site.test',
      'https://www.site.test/',
      read: (_) async => null,
    );

    expect(await CookieStore().getCookie('https://www.site.test'), 'sid=1');
  });
}

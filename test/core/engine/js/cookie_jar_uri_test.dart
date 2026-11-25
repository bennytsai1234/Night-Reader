import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/utils/network_utils.dart';

/// 規則 JS 讀、清網站寫的 Cookie 時查 Cookie 罐用的網址：和送出請求時同一個
/// 主機，Cookie 罐才查得到（同 Legado 的 Cookie API 收網址或網域）。
void main() {
  test('中文網域照送出請求時換成 punycode', () {
    expect(
      NetworkUtils.cookieJarUri('https://小說.example/search?q=1')?.host,
      'xn--yeto89h.example',
    );
  });

  test('只給網域時當成那個網域', () {
    final uri = NetworkUtils.cookieJarUri('source.example');
    expect(uri?.host, 'source.example');
    expect(uri?.scheme, 'https');
  });

  test('書源網址的 # 註記去掉，沒有主機的不查', () {
    expect(
      NetworkUtils.cookieJarUri('https://a.example/#手機版')?.host,
      'a.example',
    );
    expect(NetworkUtils.cookieJarUri(''), isNull);
    expect(NetworkUtils.cookieJarUri('#只有註記'), isNull);
  });
}

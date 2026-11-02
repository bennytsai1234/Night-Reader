import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/utils/network_utils.dart';

/// 書源網址照 Legado 組（java.net.URL 與 OkHttp HttpUrl 的行為）。
void main() {
  group('getAbsoluteURL', () {
    // 品书斋的書源網址是「https://www.pinshuzhai.com 」（結尾多一格）。
    test('base 網址頭尾的空白不算', () {
      expect(
        NetworkUtils.getAbsoluteURL(
          'https://www.pinshuzhai.com ',
          'page/1?s=我的',
        ),
        'https://www.pinshuzhai.com/page/1?s=%E6%88%91%E7%9A%84',
      );
    });
  });

  group('toAsciiHost', () {
    // 預期值取自 Python 的 `'永远的神'.encode('idna')`。
    test('中文網域換成 punycode，路徑、埠號與帳號照舊', () {
      expect(
        NetworkUtils.toAsciiHost('https://永远的神.com/s.php?q=我'),
        'https://xn--5rwq3tukc919a.com/s.php?q=我',
      );
      expect(
        NetworkUtils.toAsciiHost('http://u:p@八叉书库.example.com:8080/a'),
        'http://u:p@xn--1jq76e79by0r.example.com:8080/a',
      );
    });

    // Dart 組相對網址時先把中文主機名百分比編碼。
    test('百分比編碼過的中文主機名也換成 punycode', () {
      final absolute = NetworkUtils.getAbsoluteURL(
        'https://永远的神.com/books/',
        '../search',
      );
      expect(
        NetworkUtils.toAsciiHost(absolute),
        'https://xn--5rwq3tukc919a.com/search',
      );
    });

    test('ASCII 網域與不是網址的照舊', () {
      for (final url in [
        'https://www.example.com/中文路徑',
        'https://www.example.com/%E4%B8%AD',
        'https://[2001:db8::1]:8443/a',
        'https://xn--5rwq3tukc919a.com/a',
        'data:;base64,5aSc',
        '/relative/path',
      ]) {
        expect(NetworkUtils.toAsciiHost(url), url);
      }
    });
  });
}

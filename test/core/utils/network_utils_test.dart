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

    // 同 OkHttp 照 UTS #46（非過渡）對應。預期值取自 Node 的
    // `url.domainToASCII`（照 WHATWG／UTS #46 實作，和夜讀的程式無關）。
    test('照 UTS #46 對應再換：全形、組合重音、該忽略的字、ß', () {
      expect(
        NetworkUtils.toAsciiHost('https://\u{3f2}.gr/a'),
        'https://xn--4xa.gr/a',
      );
      expect(
        NetworkUtils.toAsciiHost('https://a\u{34f}b.com/a'),
        'https://ab.com/a',
      );
      expect(
        NetworkUtils.toAsciiHost('https://Straße.de/a'),
        'https://xn--strae-oqa.de/a',
      );
      expect(
        NetworkUtils.toAsciiHost('https://例子.中国/a'),
        'https://xn--fsqu00a.xn--fiqs8s/a',
      );
      expect(
        NetworkUtils.toAsciiHost('https://ＥＸＡＭＰＬＥ.com/a'),
        'https://example.com/a',
      );
      expect(
        NetworkUtils.toAsciiHost('https://e\u{301}.com/a'),
        'https://xn--9ca.com/a',
      );
      expect(
        NetworkUtils.toAsciiHost('https://\u{e9}.com/a'),
        'https://xn--9ca.com/a',
      );
      expect(
        NetworkUtils.toAsciiHost('https://例子．ＣＯＭ/a'),
        'https://xn--fsqu00a.com/a',
      );
    });

    // 全形的「＠」「／」「：」與不換行空白對應成網址的分隔符或空白，不是合法
    // 主機名（Node 也交出空字串）：照原樣送，不會被拼成另一個主機、路徑或埠號。
    test('換出來不是合法主機名時照原樣', () {
      for (final url in [
        'https://example.com＠other.invalid/a',
        'https://example.com／other/a',
        'https://example.com：8080/a',
        'https://a\u{a0}b.com/a',
      ]) {
        expect(NetworkUtils.toAsciiHost(url), url);
      }
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

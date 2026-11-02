import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/utils/network_utils.dart';
import 'package:night_reader/core/utils/public_suffix.dart';

void main() {
  group('registrableDomain', () {
    // 取自公共字尾表官方的測試（test_psl.txt）。
    final cases = <String, String?>{
      'com': null,
      'example.com': 'example.com',
      'a.b.example.com': 'example.com',
      'example': null,
      'b.example.example': 'example.example',
      // 一般規則
      'jp': null,
      'www.test.jp': 'test.jp',
      'ac.jp': null,
      'test.ac.jp': 'test.ac.jp',
      'ide.kyoto.jp': null,
      'a.b.ide.kyoto.jp': 'b.ide.kyoto.jp',
      // 萬用與例外
      'c.kobe.jp': null,
      'a.b.c.kobe.jp': 'b.c.kobe.jp',
      'city.kobe.jp': 'city.kobe.jp',
      'www.city.kobe.jp': 'city.kobe.jp',
      'ck': null,
      'test.ck': null,
      'a.b.test.ck': 'b.test.ck',
      'www.www.ck': 'www.ck',
      // 非 ASCII
      'www.食狮.公司.cn': '食狮.公司.cn',
      '公司.cn': null,
      'www.食狮.中国': '食狮.中国',
      // 私人網域那一段也收（同 OkHttp）
      'foo.github.io': 'foo.github.io',
      'github.io': null,
      // 大小寫、結尾的點
      'WWW.Example.COM': 'example.com',
      'www.example.com.': 'example.com',
    };
    cases.forEach((host, expected) {
      test('$host → $expected', () {
        expect(registrableDomain(host), expected);
      });
    });
  });

  group('NetworkUtils.getSubDomain', () {
    test('sites sharing a two-part suffix get separate domains', () {
      expect(
        NetworkUtils.getSubDomain('https://www.biquge.com.cn/book/1'),
        'biquge.com.cn',
      );
      expect(NetworkUtils.getSubDomain('https://m.a.ne.jp/'), 'a.ne.jp');
      expect(NetworkUtils.getSubDomain('https://b.ne.jp/'), 'b.ne.jp');
      expect(NetworkUtils.getSubDomain('https://x.idv.tw/'), 'x.idv.tw');
    });

    test('IP addresses stay whole', () {
      expect(
        NetworkUtils.getSubDomain('http://192.168.1.10:8080/a'),
        '192.168.1.10',
      );
      expect(NetworkUtils.getSubDomain('http://10.0.1.10/'), '10.0.1.10');
      expect(NetworkUtils.getSubDomain('http://[::1]:1122/'), '::1');
    });

    test('a host that is itself a public suffix is kept', () {
      expect(NetworkUtils.getSubDomain('http://localhost:1122/'), 'localhost');
    });

    test('non-ASCII hosts', () {
      expect(NetworkUtils.getSubDomain('http://www.例子.中国/'), '例子.中国');
      // 大寫的非 ASCII 字：Uri.host 只把 ASCII 轉小寫，「Ø」留成 %C3%98。
      expect(NetworkUtils.getSubDomain('https://a.ANDØY.no/'), 'a.andøy.no');
      expect(NetworkUtils.getSubDomain('https://b.andøy.no/'), 'b.andøy.no');
    });

    test('a host that is not valid UTF-8 is kept, not thrown', () {
      expect(NetworkUtils.getSubDomain('https://%FF.com/'), '%FF.com');
    });

    test('anything other than an http(s) URL is kept as is', () {
      expect(NetworkUtils.getSubDomain('legado://import'), 'legado://import');
      expect(NetworkUtils.getSubDomain('example.com'), 'example.com');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/utils/html_formatter.dart';

String keepImg(String html, {String? redirectUrl}) =>
    HtmlFormatter.formatKeepImg(html, redirectUrl: redirectUrl);

void main() {
  group('formatKeepImg 挑圖片網址', () {
    const real =
        'https://www.zhangzs.com/wp-content/uploads/2026/11/d4b01eccgy1iiysbisyddj210o27o7uh.jpg';
    const placeholder =
        'http://www.zhangzs.com/wp-content/themes/justnews.bak/themer/assets/images/lazy.png';

    test('懶載入的圖取 data-original，不取 src 的佔位圖（涨姿势）', () {
      expect(
        keepImg(
          '<figure class="wp-block-image"><img class="j-lazy" '
          'src="$placeholder" data-original="$real"/></figure>',
        ),
        '<img src="$real">',
      );
    });

    test('懶載入屬性寫在 src 前面也取懶載入屬性', () {
      expect(
        keepImg('<img data-original="$real" src="$placeholder">'),
        '<img src="$real">',
      );
      expect(
        keepImg('<img data-src="a.jpg" src="lazy.gif">'),
        '<img src="a.jpg">',
      );
      expect(
        keepImg('<img src="lazy.gif" data-lazy-src="a.jpg">'),
        '<img src="a.jpg">',
      );
    });

    test('懶載入屬性是空的就取 src', () {
      expect(
        keepImg('<img src="a.jpg" data-original="">'),
        '<img src="a.jpg">',
      );
    });

    test('名字只是開頭相同的 data-* 不算懶載入屬性', () {
      expect(
        keepImg('<img src="a.jpg" data-original-title="提示">'),
        '<img src="a.jpg">',
      );
      expect(
        keepImg('<img src="a.jpg" data-srcset="b.jpg 2x">'),
        '<img src="a.jpg">',
      );
    });

    test('只有 src、或只有其他 data-* 時照舊', () {
      expect(keepImg('<img alt="x" src="a.jpg">'), '<img src="a.jpg">');
      expect(keepImg('<img data-url="a.jpg">'), '<img src="a.jpg">');
    });

    test('src 帶網址選項時取 src，選項接在補好的網址後面', () {
      expect(
        keepImg(
          '<img src="/a.jpg,{\'headers\':{\'Referer\':\'x\'}}" '
          'data-original="b.jpg">',
          redirectUrl: 'https://site.com/book/1.html',
        ),
        '<img src="https://site.com/a.jpg,{\'headers\':{\'Referer\':\'x\'}}">',
      );
    });

    test('懶載入屬性的網址照頁面網址補成完整網址', () {
      expect(
        keepImg(
          '<img class="j-lazy" src="$placeholder" '
          'data-original="//www.zhangzs.com/a@2x.jpg">',
          redirectUrl: 'http://120.25.175.92/551908.html',
        ),
        '<img src="http://www.zhangzs.com/a@2x.jpg">',
      );
    });
  });
}

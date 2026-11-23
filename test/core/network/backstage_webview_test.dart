import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/backstage_webview.dart';

void main() {
  test('Android 包成 JSON 字串的結果解開，HTML 實體原樣留給規則解析', () {
    const literal = r'"<p>原文寫的是 &amp;lt;span&amp;gt;。<\/p>"';
    expect(
      BackstageWebView.contentOf(literal),
      '<p>原文寫的是 &amp;lt;span&amp;gt;。</p>',
    );

    const escaped = r'"\u003Cp>&quot;引號&quot;\u003C/p>"';
    expect(BackstageWebView.contentOf(escaped), '<p>&quot;引號&quot;</p>');
  });

  test('iOS 直接給的字串原樣交回', () {
    const page = '<div>&lt;div&gt; 與 &amp;amp;</div>';
    expect(BackstageWebView.contentOf(page), page);
  });

  test('資源網址在內容裡找，寫在屬性裡的實體解開才是真的網址', () {
    const page = '<video src="https://v.example/a.m3u8?k=1&amp;t=2"></video>';
    expect(
      BackstageWebView.sourceIn(page, r'src="([^"]+\.m3u8[^"]*)"'),
      'https://v.example/a.m3u8?k=1&t=2',
    );
    expect(BackstageWebView.sourceIn(page, r'\.mp4'), isNull);
  });
}

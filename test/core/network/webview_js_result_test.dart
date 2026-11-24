import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/backstage_webview.dart';
import 'package:night_reader/core/network/webview_js_result.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Android 包成 JSON 字串的結果解開，HTML 實體原樣留給規則解析', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const literal = r'"<p>原文寫的是 &amp;lt;span&amp;gt;。<\/p>"';
    expect(webViewJsResult(literal), '<p>原文寫的是 &amp;lt;span&amp;gt;。</p>');

    const escaped = r'"\u003Cp>&quot;引號&quot;\u003C/p>"';
    expect(webViewJsResult(escaped), '<p>&quot;引號&quot;</p>');
    expect(webViewJsResult(r'"\"甲\""'), '"甲"');
  });

  test('iOS 照原值給：規則 JS 傳回的 JSON 字串不多解一層', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(webViewJsResult('"甲"'), '"甲"');
    const page = '<div>&lt;div&gt; 與 &amp;amp;</div>';
    expect(webViewJsResult(page), page);
  });

  test('資源網址在內容裡找，寫在屬性裡的實體解開才是真的網址', () {
    const page = '<video src="https://v.example/a.m3u8?k=1&amp;t=2"></video>';
    expect(
      BackstageWebView.sourceIn(page, r'src="([^"]+\.m3u8[^"]*)"'),
      'https://v.example/a.m3u8?k=1&t=2',
    );
    expect(BackstageWebView.sourceIn(page, r'\.mp4'), isNull);
  });

  test('等的是網頁載入過、整段符合 sourceRegex 的資源網址（同 Legado）', () {
    const loaded = [
      'https://cdn.test/app.js',
      'https://api.test/chapter?id=1&sign=abc',
      'https://cdn.test/a.m3u8?t=1',
    ];
    expect(
      BackstageWebView.resourceMatching(
        loaded,
        r'https://api\.test/chapter\?.*',
      ),
      'https://api.test/chapter?id=1&sign=abc',
    );
    expect(
      BackstageWebView.resourceMatching(loaded, r'.*\.m3u8.*'),
      'https://cdn.test/a.m3u8?t=1',
    );
    // 整段：只符合一部分不算（Java String.matches）。
    expect(BackstageWebView.resourceMatching(loaded, r'\.m3u8'), isNull);
  });
}

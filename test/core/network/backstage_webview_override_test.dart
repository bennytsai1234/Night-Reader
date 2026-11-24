import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/backstage_webview.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// 背景網頁等網頁跳到某個網址（`java.webViewGetOverrideUrl`、網址選項的
/// `overrideUrlRegex`）：同 Legado 的 `SnifferWebClient`，網頁載完只跑書源給
/// 的 JS，不交回網頁內容；等到符合的跳轉（或逾時）才結束。
void main() {
  late _RecordingWebView webView;

  setUp(() {
    webView = _RecordingWebView();
    WebViewPlatform.instance = webView;
  });

  testWidgets('a redirect that comes two seconds after the page loads is '
      'still caught', (tester) async {
    Map<String, dynamic>? result;
    unawaited(
      BackstageWebView(
        url: 'https://site.test/play',
        overrideUrlRegex: r'.*\.mp3',
      ).getStrResponse().then((value) => result = value),
    );
    await tester.pump();

    webView.pageFinished('https://site.test/play');
    await tester.pump(const Duration(milliseconds: 1500));
    expect(result, isNull, reason: '網頁載完不交回整頁');

    await tester.pump(const Duration(milliseconds: 500));
    webView.navigate('https://cdn.test/1.mp3');
    await tester.pump();
    expect(result?['body'], 'https://cdn.test/1.mp3');

    // 收掉整體 60 秒的計時。
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('the source script runs, and a partial match or a frame does '
      'not end the wait', (tester) async {
    Map<String, dynamic>? result;
    unawaited(
      BackstageWebView(
        url: 'https://site.test/play',
        overrideUrlRegex: r'https://cdn\.test/.*\.mp3',
        javaScript: 'play()',
      ).getStrResponse().then((value) => result = value),
    );
    await tester.pump();

    webView.pageFinished('https://site.test/play');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(webView.ran, ['play()']);

    // 同 Legado 的 matches：整段網址都要符合。
    webView.navigate('https://site.test/go?to=https://cdn.test/1.mp3');
    // iframe 裡的跳轉不算。
    webView.navigate('https://cdn.test/ad.mp3', mainFrame: false);
    await tester.pump();
    expect(result, isNull);

    webView.navigate('https://cdn.test/1.mp3');
    await tester.pump();
    expect(result?['body'], 'https://cdn.test/1.mp3');

    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('with a resource pattern too, an address in the page is taken '
      'as before', (tester) async {
    webView.page = '<audio src="https://cdn.test/2.m3u8"></audio>';
    Map<String, dynamic>? result;
    unawaited(
      BackstageWebView(
        url: 'https://site.test/play',
        overrideUrlRegex: r'.*\.mp3',
        sourceRegex: r'https://cdn\.test/[^"]+\.m3u8',
      ).getStrResponse().then((value) => result = value),
    );
    await tester.pump();

    webView.pageFinished('https://site.test/play');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(result?['body'], 'https://cdn.test/2.m3u8');

    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('without a redirect pattern the page content is returned as '
      'before', (tester) async {
    Map<String, dynamic>? result;
    unawaited(
      BackstageWebView(url: 'https://site.test/book')
          .getStrResponse()
          .then((value) => result = value),
    );
    await tester.pump();

    webView.pageFinished('https://site.test/book');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(result?['body'], '<html>內容</html>');

    await tester.pump(const Duration(seconds: 61));
  });

  // R7：sourceRegex 等網頁真的載入、整段符合的資源網址（Legado
  // onLoadResource）；WebView 套件收不到這個事件，改讀 Resource Timing。
  testWidgets('a resource the page loads later is waited for, and the source '
      'script runs once', (tester) async {
    Map<String, dynamic>? result;
    unawaited(
      BackstageWebView(
        url: 'https://site.test/read',
        sourceRegex: r'https://api\.test/chapter\?.*',
        javaScript: 'load()',
      ).getStrResponse().then((value) => result = value),
    );
    await tester.pump();

    webView.pageFinished('https://site.test/read');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(result, isNull, reason: '還沒載入就不交回網頁內容');

    webView.resources = [
      'https://cdn.test/app.js',
      'https://api.test/chapter?id=1',
    ];
    await tester.pump(const Duration(seconds: 2));
    expect(result?['body'], 'https://api.test/chapter?id=1');
    expect(webView.evaluated, ['load()']);

    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('waiting for a redirect, a matching resource that loads later '
      'ends the wait too', (tester) async {
    Map<String, dynamic>? result;
    unawaited(
      BackstageWebView(
        url: 'https://site.test/play',
        overrideUrlRegex: r'.*\.mp3',
        sourceRegex: r'.*\.m3u8.*',
      ).getStrResponse().then((value) => result = value),
    );
    await tester.pump();

    webView.pageFinished('https://site.test/play');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(result, isNull);

    webView.resources = ['https://cdn.test/a.m3u8?t=1'];
    await tester.pump(const Duration(seconds: 2));
    expect(result?['body'], 'https://cdn.test/a.m3u8?t=1');

    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('an address written in the page is taken at once, as before', (
    tester,
  ) async {
    webView.page = '<video src="https://cdn.test/v.m3u8"></video>';
    Map<String, dynamic>? result;
    unawaited(
      BackstageWebView(
        url: 'https://site.test/watch',
        sourceRegex: r'https://cdn\.test/[^"]+\.m3u8',
      ).getStrResponse().then((value) => result = value),
    );
    await tester.pump();

    webView.pageFinished('https://site.test/watch');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(result?['body'], 'https://cdn.test/v.m3u8');

    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('when nothing matches, the page is returned at the end', (
    tester,
  ) async {
    Map<String, dynamic>? result;
    unawaited(
      BackstageWebView(
        url: 'https://site.test/watch',
        sourceRegex: r'.*\.m3u8',
      ).getStrResponse().then((value) => result = value),
    );
    await tester.pump();

    webView.pageFinished('https://site.test/watch');
    await tester.pump(const Duration(seconds: 10));
    expect(result, isNull, reason: '等的途中不交回');

    await tester.pump(const Duration(seconds: 25));
    expect(result?['body'], '<html>內容</html>');

    await tester.pump(const Duration(seconds: 61));
  });
}

/// 記下網頁載完、跳轉的回呼，測試自己觸發；執行 JS 回一份固定的網頁。
class _RecordingWebView extends WebViewPlatform {
  PageEventCallback? _onPageFinished;
  NavigationRequestCallback? _onNavigationRequest;

  void pageFinished(String url) => _onPageFinished?.call(url);

  /// 書源給的 JS（[BackstageWebView.javaScript]）跑過的。
  final List<String> ran = [];

  /// 網頁內容（`outerHTML`）。
  String page = '<html>內容</html>';

  /// 網頁載入過的資源網址（Resource Timing）。
  List<String> resources = [];

  /// 交回結果的 JS（`runJavaScriptReturningResult`）跑過的，不含讀資源清單。
  final List<String> evaluated = [];

  void navigate(String url, {bool mainFrame = true}) => _onNavigationRequest
      ?.call(NavigationRequest(url: url, isMainFrame: mainFrame));

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _Controller(params, this);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Delegate(params, this);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _Widget(params);
}

class _Widget extends PlatformWebViewWidget {
  _Widget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params, this._web) : super.implementation();

  final _RecordingWebView _web;

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> runJavaScript(String javaScript) async =>
      _web.ran.add(javaScript);

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    // 真的 WebView 把字串結果編成 JSON 字串交回。
    if (javaScript.contains('getEntriesByType')) {
      return jsonEncode(jsonEncode(_web.resources));
    }
    _web.evaluated.add(javaScript);
    return jsonEncode(_web.page);
  }
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params, this._web) : super.implementation();

  final _RecordingWebView _web;

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async =>
      _web._onPageFinished = onPageFinished;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async => _web._onNavigationRequest = onNavigationRequest;

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {}

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {}

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {}

  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback onSslAuthError) async {}
}

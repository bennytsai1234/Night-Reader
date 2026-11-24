import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'package:html_unescape/html_unescape.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/network/cookie_store.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/network/webview_js_result.dart';
import 'package:night_reader/core/network/webview_cloudflare_solver.dart';

class BackstageWebView {
  final String? url;
  final String? html;
  final String? javaScript;
  final String? sourceRegex;
  final String? overrideUrlRegex;
  final Map<String, String>? headerMap;
  final int delayTime;

  /// 書源的 key（[BookSource.getKey]）：網頁每載完一頁，就把那一頁的 Cookie
  /// 存進這個書源（同 Legado `BackstageWebView` 的 `tag`），之後不開網頁的
  /// 請求帶得到網頁程式寫下的 Cookie。null 是不存。
  final String? tag;

  Timer? _timer;

  static Widget? _hiddenWebViewWidget;

  /// 設定後改由它載入：WebView 只能在主 isolate 用，書源 isolate 把這個
  /// 請求（只有網址、HTML 與規則這些資料）交給主 isolate 執行
  /// （ADR 0028）。
  static Future<Map<String, dynamic>> Function(BackstageWebView request)?
  delegate;

  BackstageWebView({
    this.url,
    this.html,
    this.javaScript,
    this.sourceRegex,
    this.overrideUrlRegex,
    this.headerMap,
    this.delayTime = 0,
    this.tag,
  });

  /// 取得隱藏的 WebView 元件 (可以掛在 app 根節點的 Stack 底層)
  static Widget get hiddenWebViewWidget {
    _hiddenWebViewWidget ??= SizedBox(
      width: 1,
      height: 1,
      child: Opacity(
        opacity: 0.0,
        // Placeholder, will be replaced when a request is made
        child: Container(),
      ),
    );
    return _hiddenWebViewWidget!;
  }

  /// 跳轉的網址 [url] 整段符合 [overrideUrlRegex]（同 Legado 的 `matches`）。
  @visibleForTesting
  static bool overrideUrlMatches(String url, String overrideUrlRegex) =>
      RegExp('^(?:$overrideUrlRegex)\$').hasMatch(url);

  /// [sourceRegex] 在網頁內容裡找到的資源網址，有分組時取第一組；沒找到是
  /// null。Legado 等的是網頁真的載入的資源網址，這裡在內容裡找，網址寫在
  /// HTML 屬性裡，實體（`&amp;`）解開才是真的網址。
  @visibleForTesting
  static String? sourceIn(String content, String sourceRegex) {
    final page = HtmlUnescape().convert(content);
    final match = RegExp(sourceRegex).firstMatch(page);
    if (match == null) return null;
    return match.groupCount > 0
        ? (match.group(1) ?? match.group(0) ?? '')
        : (match.group(0) ?? '');
  }

  /// 瀏覽器裡 [pageUrl] 那一頁的 Cookie 存進書源 [tag]（同 Legado：整份換成
  /// 瀏覽器那一份，`CookieStore.setCookie`）。[read] 是測試換掉讀瀏覽器 Cookie
  /// 的那一步。
  @visibleForTesting
  static Future<void> saveCookies(
    String tag,
    String pageUrl, {
    Future<String?> Function(Uri uri) read = WebViewNative.cookies,
  }) async {
    try {
      final uri = Uri.tryParse(pageUrl);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;
      final cookie = await read(uri);
      if (cookie == null || cookie.isEmpty) return;
      await CookieStore().setCookie(tag, cookie);
    } catch (error) {
      // 只記錯誤的種類：資料庫的錯誤訊息會帶出寫入的 Cookie 值。
      AppLog.w('存背景網頁的 Cookie 失敗: ${error.runtimeType}');
    }
  }

  Future<Map<String, dynamic>> getStrResponse() async {
    // 給了 HTML 時網址只當基準網址，沒有載入。
    if ((html ?? '').isEmpty && (url ?? '').isNotEmpty) {
      if (Uri.tryParse(url!) case final uri?) recordRequestUrl('GET', uri);
    }
    final result = await _render();
    recordRenderedPage(result['url'] as String? ?? url, result['body']);
    return result;
  }

  Future<Map<String, dynamic>> _render() async {
    final delegate = BackstageWebView.delegate;
    if (delegate != null) return delegate(this);
    final completer = Completer<Map<String, dynamic>>();

    // Setup WebViewController
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    unawaited(WebViewNative.refreshUserAgent());
    await controller.setBackgroundColor(const Color(0x00000000));

    if (headerMap != null && headerMap!.containsKey('User-Agent')) {
      await controller.setUserAgent(headerMap!['User-Agent']);
    }

    // Android specific settings
    if (controller.platform is AndroidWebViewController) {
      await AndroidWebViewController.enableDebugging(false);
      await (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    var retryCount = 0;
    var isCompleted = false;

    void finish(Map<String, dynamic> result) {
      if (!isCompleted) {
        isCompleted = true;
        _timer?.cancel();
        // Clear webview to release memory
        controller.loadHtmlString('<html></html>');
        completer.complete(result);
      }
    }

    void finishError(dynamic e) {
      if (!isCompleted) {
        isCompleted = true;
        _timer?.cancel();
        controller.loadHtmlString('<html></html>');
        completer.completeError(e);
      }
    }

    await controller.setNavigationDelegate(
      NavigationDelegate(
        // 書源網站的憑證不驗（同書源的連線，見 sourceHttpClient）。
        onSslAuthError: (error) => error.proceed(),
        onPageFinished: (String currentUrl) async {
          if (tag case final key?) unawaited(saveCookies(key, currentUrl));
          if (isCompleted) return;

          await Future.delayed(Duration(milliseconds: 1000 + delayTime));
          if (isCompleted) return;

          // 等網頁跳到某個網址的（[overrideUrlRegex]）：同 Legado 的
          // SnifferWebClient，網頁載完只跑書源給的 JS，不交回網頁內容，
          // 等到符合的跳轉（[onNavigationRequest]）或逾時才結束。跳轉常在
          // 網頁跑了一陣子之後才發生（例如播放頁幾秒後才導向音訊）。
          // 同時有 [sourceRegex] 的，照舊在網頁內容裡找，先到的為準（Legado
          // 兩條路都在 SnifferWebClient 裡、先到先得）。
          if (overrideUrlRegex?.isNotEmpty ?? false) {
            final js = javaScript;
            if (js != null && js.isNotEmpty) {
              unawaited(controller.runJavaScript(js).catchError((_) {}));
            }
            final regex = sourceRegex;
            if (regex != null && regex.isNotEmpty) {
              try {
                final content = webViewJsResult(
                  await controller.runJavaScriptReturningResult(
                    'document.documentElement.outerHTML',
                  ),
                );
                if (sourceIn(content, regex) case final source?) {
                  finish({'body': source, 'url': currentUrl, 'code': 200});
                }
              } catch (_) {
                // 網頁還在換頁、讀不到內容：照樣等跳轉。
              }
            }
            return;
          }

          final jsToRun = javaScript?.isNotEmpty == true
              ? javaScript!
              : 'document.documentElement.outerHTML';

          void evaluateAndCheck() async {
            if (isCompleted) return;
            try {
              final result = await controller.runJavaScriptReturningResult(
                jsToRun,
              );
              if (result.toString().isNotEmpty && result.toString() != 'null') {
                final content = webViewJsResult(result);

                final regex = sourceRegex;
                if (regex != null && regex.isNotEmpty) {
                  if (sourceIn(content, regex) case final source?) {
                    finish({'body': source, 'url': currentUrl, 'code': 200});
                    return;
                  }
                }

                finish({'body': content, 'url': currentUrl, 'code': 200});
                return;
              }
            } catch (e) {
              // ignore JS execution error, retry
            }

            if (retryCount > 30) {
              finishError(Exception('JS execution timeout'));
              return;
            }
            retryCount++;
            _timer = Timer(
              const Duration(milliseconds: 1000),
              evaluateAndCheck,
            );
          }

          evaluateAndCheck();
        },
        onNavigationRequest: (NavigationRequest request) {
          // 同 Legado `shouldOverrideUrlLoading` 的 `matches`：整段網址都要
          // 符合；只看主畫面的跳轉（Android 的外掛本來就只回報主畫面）。
          final pattern = overrideUrlRegex;
          if (pattern != null && pattern.isNotEmpty && request.isMainFrame) {
            if (overrideUrlMatches(request.url, pattern)) {
              finish({'body': request.url, 'url': request.url, 'code': 200});
              return NavigationDecision.prevent;
            }
          }
          return NavigationDecision.navigate;
        },
      ),
    );

    try {
      if (html != null && html!.isNotEmpty) {
        if (url == null || url!.isEmpty) {
          await controller.loadHtmlString(html!);
        } else {
          await controller.loadHtmlString(html!, baseUrl: url);
        }
      } else if (url != null) {
        await controller.loadRequest(Uri.parse(url!), headers: headerMap ?? {});
      } else {
        finishError(Exception('No URL or HTML provided'));
      }

      // Mount to UI to actually render and execute JS
      _hiddenWebViewWidget = SizedBox(
        width: 1,
        height: 1,
        child: Opacity(
          opacity: 0.0,
          child: WebViewWidget(controller: controller),
        ),
      );
    } catch (e) {
      finishError(e);
    }

    // Set an overall timeout of 60 seconds
    Future.delayed(const Duration(seconds: 60), () {
      if (!isCompleted) {
        finishError(Exception('WebView timeout (60s)'));
      }
    });

    return completer.future;
  }
}

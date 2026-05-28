import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'dart:convert';
import 'package:html_unescape/html_unescape.dart';

class BackstageWebView {
  final String? url;
  final String? html;
  final String? javaScript;
  final String? sourceRegex;
  final String? overrideUrlRegex;
  final Map<String, String>? headerMap;
  final int delayTime;

  Timer? _timer;

  static Widget? _hiddenWebViewWidget;

  BackstageWebView({
    this.url,
    this.html,
    this.javaScript,
    this.sourceRegex,
    this.overrideUrlRegex,
    this.headerMap,
    this.delayTime = 0,
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

  Future<Map<String, dynamic>> getStrResponse() async {
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

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000));

    if (headerMap != null && headerMap!.containsKey('User-Agent')) {
      controller.setUserAgent(headerMap!['User-Agent']);
    }

    // Android specific settings
    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(false);
      (controller.platform as AndroidWebViewController)
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

    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (String currentUrl) async {
          if (isCompleted) return;

          await Future.delayed(Duration(milliseconds: 1000 + delayTime));
          if (isCompleted) return;

          final jsToRun =
              javaScript?.isNotEmpty == true
                  ? javaScript!
                  : 'document.documentElement.outerHTML';

          void evaluateAndCheck() async {
            if (isCompleted) return;
            try {
              final result = await controller.runJavaScriptReturningResult(
                jsToRun,
              );
              if (result.toString().isNotEmpty && result.toString() != 'null') {
                var content = result.toString();
                // Remove surrounding quotes if it's a JSON string
                if (content.startsWith('"') && content.endsWith('"')) {
                  content = jsonDecode(content);
                }
                content = HtmlUnescape().convert(content);

                if (sourceRegex != null && sourceRegex!.isNotEmpty) {
                  final match = RegExp(sourceRegex!).firstMatch(content);
                  if (match != null) {
                    finish({
                      'body':
                          match.groupCount > 0
                              ? (match.group(1) ?? match.group(0) ?? '')
                              : (match.group(0) ?? ''),
                      'url': currentUrl,
                      'code': 200,
                    });
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
          if (overrideUrlRegex != null && overrideUrlRegex!.isNotEmpty) {
            if (RegExp(overrideUrlRegex!).hasMatch(request.url)) {
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

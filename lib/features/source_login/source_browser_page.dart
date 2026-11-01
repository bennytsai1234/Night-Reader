import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/source_interaction.dart';
import 'package:night_reader/core/services/webview_cloudflare_solver.dart';
import 'package:night_reader/features/about/external_url_launcher.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 閱讀器的「前往驗證」：開書源 [sourceUrl] 要使用者操作的那一頁
/// [request]（ADR 0038），使用者離開、返回動畫播完才回來，呼叫端接著重抓。
/// 去過之後就不再記著這一頁，重抓又要驗證時記新的。
Future<void> openSourceVerification(
  BuildContext context, {
  required String sourceUrl,
  required String sourceName,
  required SourceBrowseRequest request,
}) async {
  SourceInteraction.forgetVerification(sourceUrl);
  await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => SourceBrowserPage(
        sourceUrl: sourceUrl,
        url: request.url,
        title: request.title.isEmpty ? sourceName : request.title,
        headers: request.headers,
      ),
    ),
  );
  if (context.mounted) await TransitionSettled.uncovered(context);
}

/// 書源登入用的瀏覽器：沒有表單的書源在這裡登入（網頁登入），書源程式要
/// 使用者在網頁上操作（`java.startBrowser`、`startBrowserAwait`）、閱讀器的
/// 「前往驗證」也開這一頁。
///
/// 每載完一頁，就把書源網站與這一頁在瀏覽器裡的 Cookie 存給夜讀，同
/// Legado；離開時再存一次，不論按的是完成還是返回，都不會白登入。右上角
/// 打勾是完成，傳回網頁內容（書源程式等的就是它）；沒按完成就離開傳回
/// null。系統返回鍵先在網頁裡回上一頁，頁首的返回鈕才是離開。
class SourceBrowserPage extends StatefulWidget {
  const SourceBrowserPage({
    super.key,
    required this.sourceUrl,
    required this.url,
    required this.title,
    this.headers = const {},
  });

  /// 書源的網址：Cookie 存在這個網站名下。
  final String sourceUrl;
  final String url;
  final String title;

  /// 書源的標頭（含登入標頭）；`User-Agent` 換成瀏覽器的標識，網站才認得
  /// 是同一個裝置。
  final Map<String, String> headers;

  @override
  State<SourceBrowserPage> createState() => _SourceBrowserPageState();
}

class _SourceBrowserPageState extends State<SourceBrowserPage> {
  late final WebViewController _controller;

  /// 載入進度（0–1）；載完是 null，不畫進度線。
  final ValueNotifier<double?> _progress = ValueNotifier(0);
  String? _pageUrl;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    final headers = Map.of(widget.headers);
    final userAgent =
        headers.remove('User-Agent') ?? headers.remove('user-agent');
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (percent) =>
              _progress.value = percent >= 100 ? null : percent / 100,
          onPageStarted: (url) => _pageUrl = url,
          onPageFinished: (url) {
            _pageUrl = url;
            _progress.value = null;
            unawaited(_saveCookies());
          },
          onNavigationRequest: _onNavigationRequest,
        ),
      );
    if (userAgent != null && userAgent.isNotEmpty) {
      unawaited(_controller.setUserAgent(userAgent));
    }
    final uri = Uri.tryParse(widget.url);
    if (uri != null) {
      unawaited(_controller.loadRequest(uri, headers: headers));
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  /// 網頁要跳到別的 App（例如 `weixin://`）：先問。
  FutureOr<NavigationDecision> _onNavigationRequest(
    NavigationRequest request,
  ) async {
    final scheme = Uri.tryParse(request.url)?.scheme ?? '';
    if (scheme == 'http' || scheme == 'https' || scheme == 'about') {
      return NavigationDecision.navigate;
    }
    if (!mounted) return NavigationDecision.prevent;
    final open = await showAppConfirm(
      context: context,
      title: '用其他 App 開啟？',
      message: request.url,
      confirmLabel: '開啟',
    );
    if (open && mounted) {
      await launchExternalUrlWithFeedback(context, request.url);
    }
    return NavigationDecision.prevent;
  }

  /// 書源網站的 Cookie 存給夜讀；這一頁在別的網站（例如統一登入）時，那個
  /// 網站的 Cookie 也存一份，並併進書源網站的，同 Legado 的網頁登入。
  Future<void> _saveCookies() async {
    try {
      final store = CookieStore();
      final sourceUri = Uri.tryParse(widget.sourceUrl);
      if (sourceUri == null) return;
      final sourceCookies = await WebViewNative.cookies(sourceUri);
      if (sourceCookies != null && sourceCookies.isNotEmpty) {
        await store.setCookie(widget.sourceUrl, sourceCookies);
      }
      final pageUrl = _pageUrl;
      if (pageUrl == null ||
          store.getSubDomain(pageUrl) == store.getSubDomain(widget.sourceUrl)) {
        return;
      }
      final pageUri = Uri.tryParse(pageUrl);
      if (pageUri == null) return;
      final pageCookies = await WebViewNative.cookies(pageUri);
      if (pageCookies == null || pageCookies.isEmpty) return;
      await store.setCookie(pageUrl, pageCookies);
      await store.replaceCookie(widget.sourceUrl, pageCookies);
    } catch (error, stackTrace) {
      AppLog.e('存書源網頁的 Cookie 失敗', error: error, stackTrace: stackTrace);
    }
  }

  Future<String?> _pageHtml() async {
    try {
      final value = await _controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML',
      );
      final text = value.toString();
      return text.length >= 2 && text.startsWith('"') && text.endsWith('"')
          ? jsonDecode(text) as String
          : text;
    } catch (error) {
      AppLog.w('讀不到書源網頁的內容: $error');
      return '';
    }
  }

  Future<void> _leave({required bool done}) async {
    if (_leaving) return;
    _leaving = true;
    final html = done ? await _pageHtml() : null;
    await _saveCookies();
    if (mounted) Navigator.of(context).pop(html);
  }

  Future<void> _onBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    } else {
      await _leave(done: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope<String>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onBack());
      },
      child: Scaffold(
        backgroundColor: AppChrome.of(context).groupedBackground,
        appBar: GlassNavHeader(
          title: widget.title,
          leading: GlassIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: '返回',
            onPressed: () => _leave(done: false),
          ),
          actions: [
            GlassIconButton(
              icon: Icons.check_rounded,
              tooltip: '完成',
              onPressed: () => _leave(done: true),
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(child: WebViewWidget(controller: _controller)),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: ValueListenableBuilder<double?>(
                valueListenable: _progress,
                builder: (context, progress, _) => progress == null
                    ? const SizedBox.shrink()
                    : LinearProgressIndicator(
                        value: progress,
                        minHeight: 2,
                        color: scheme.primary,
                        backgroundColor: Colors.transparent,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

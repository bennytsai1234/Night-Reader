import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:night_reader/core/network/cloudflare.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 讀手機內建瀏覽器的 Cookie 與瀏覽器標識（原生端在 `MainActivity`、
/// `AppDelegate`）。沒有原生端（測試）時是 null。
abstract final class WebViewNative {
  static const MethodChannel _channel = MethodChannel('night_reader/webview');

  /// 瀏覽器存的 [uri] 所在網站的 Cookie（`a=1; b=2`），含網頁程式讀不到的。
  static Future<String?> cookies(Uri uri) =>
      _call<String>('getCookies', uri.toString());

  static Future<String?> defaultUserAgent() =>
      _call<String>('defaultUserAgent', null);

  static Future<T?> _call<T>(String method, Object? arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      AppLog.w('WebView 平台呼叫失敗 $method: $e');
      return null;
    }
  }
}

/// 用看不到的瀏覽器開網站，等 Cloudflare 的瀏覽器檢查自己通過，再交出通行
/// Cookie 與瀏覽器標識。不點任何東西：檢查停在要真人勾選的那一步時回報
/// [ClearanceOutcome.needsHuman]。一次只開一個瀏覽器。
class WebViewCloudflareSolver implements CloudflareSolver {
  /// 正在檢查的瀏覽器，由 [HiddenWebViews] 接到畫面上。
  static final ValueNotifier<List<WebViewController>> attached = ValueNotifier(
    const [],
  );

  /// 一個網站最多等多久。實測霹靂書坊約 12 秒通過，留兩倍多的餘裕給慢的
  /// 手機與網路。
  static const Duration timeLimit = Duration(seconds: 30);

  /// 看到真人勾選框後再等多久。勾選框有時是自動完成的那種，幾秒內會自己
  /// 過；15 秒還在就是在等人勾，不必等滿 [timeLimit]。
  static const Duration humanCheckWait = Duration(seconds: 15);

  Future<void> _tail = Future.value();

  @override
  Future<ClearanceResult> solve(Uri uri) async {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    try {
      await previous;
      return await _solve(uri);
    } finally {
      gate.complete();
    }
  }

  Future<ClearanceResult> _solve(Uri uri) async {
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    attached.value = [...attached.value, controller];
    final stopwatch = Stopwatch()..start();
    Duration? humanCheckSeen;
    var settledPolls = 0;
    try {
      await controller.loadRequest(uri);
      while (stopwatch.elapsed < timeLimit) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final state = await _pageState(controller);
        if (state == null || !state.loaded) continue;
        if (!state.challenge) {
          final cookies = await WebViewNative.cookies(uri) ?? '';
          // 通過後 Cloudflare 會設 cf_clearance；瀏覽器根本沒被檢查時沒有，
          // 頁面穩定幾秒就當作通過，交給重送的請求決定。
          if (cookies.contains('cf_clearance=') || ++settledPolls >= 3) {
            AppLog.i(
              'Cloudflare 檢查通過 ${uri.host}（${stopwatch.elapsed.inSeconds} 秒）',
            );
            return ClearanceResult.passed(
              cookies: cookies,
              userAgent: await _userAgent(controller),
            );
          }
          continue;
        }
        settledPolls = 0;
        if (state.humanCheck) {
          humanCheckSeen ??= stopwatch.elapsed;
          if (stopwatch.elapsed - humanCheckSeen >= humanCheckWait) break;
        }
      }
      AppLog.w(
        'Cloudflare 檢查沒有通過 ${uri.host}'
        '${humanCheckSeen != null ? '：要真人勾選' : ''}',
      );
      return humanCheckSeen != null
          ? const ClearanceResult.needsHuman()
          : const ClearanceResult.failed();
    } finally {
      attached.value = [
        for (final c in attached.value)
          if (!identical(c, controller)) c,
      ];
    }
  }

  static const String _stateScript = '''
JSON.stringify({
  loaded: document.readyState === 'complete',
  challenge: !!window._cf_chl_opt ||
    !!document.querySelector('#challenge-form, #challenge-stage, script[src*="/cdn-cgi/challenge-platform/"]'),
  humanCheck: !!document.querySelector('iframe[src*="challenges.cloudflare.com"], .cf-turnstile')
})''';

  static Future<({bool loaded, bool challenge, bool humanCheck})?> _pageState(
    WebViewController controller,
  ) async {
    try {
      final decoded = _decodeJsString(
        await controller.runJavaScriptReturningResult(_stateScript),
      );
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      return (
        loaded: map['loaded'] == true,
        challenge: map['challenge'] == true,
        humanCheck: map['humanCheck'] == true,
      );
    } catch (_) {
      // 換頁途中執行不了，下一秒再看。
      return null;
    }
  }

  static Future<String?> _userAgent(WebViewController controller) async {
    try {
      return _decodeJsString(
        await controller.runJavaScriptReturningResult('navigator.userAgent'),
      );
    } catch (_) {
      return WebViewUserAgent.value;
    }
  }

  /// Android 傳回的字串外面多包一層 JSON 引號，iOS 沒有。
  static String _decodeJsString(Object value) {
    final text = value.toString();
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      return jsonDecode(text) as String;
    }
    return text;
  }
}

/// 把 [WebViewCloudflareSolver] 正在用的瀏覽器接到畫面上，但看不到、也
/// 點不到：瀏覽器要接在畫面上，網頁的計時器與動畫幀才照常跑，Cloudflare
/// 的檢查程式才會跑完。
///
/// [child]（整個 App 的頁面）一直在同一個位置，瀏覽器出現與收起只改上面
/// 那一層，頁面不會因此重建（ADR 0029）。
class HiddenWebViews extends StatelessWidget {
  const HiddenWebViews({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: ExcludeSemantics(
            child: ValueListenableBuilder<List<WebViewController>>(
              valueListenable: WebViewCloudflareSolver.attached,
              builder: (context, controllers, _) => Stack(
                textDirection: TextDirection.ltr,
                children: [
                  for (final controller in controllers)
                    Positioned(
                      left: 0,
                      top: 0,
                      // 手機直式的大小，網頁照一般手機排版。
                      width: 400,
                      height: 800,
                      child: Opacity(
                        opacity: 0,
                        child: WebViewWidget(controller: controller),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

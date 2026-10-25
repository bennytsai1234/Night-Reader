import 'dart:async';

import 'package:night_reader/core/exception/app_exception.dart';

/// 網站的回應是不是被擋下來的頁面。
enum BlockedPage {
  /// 正常內容。
  none,

  /// Cloudflare 的瀏覽器檢查（「請稍候」「Just a moment」）：真的瀏覽器
  /// 開著等一下多半會自己通過。
  challenge,

  /// 網站直接封鎖這個網路（IP 或地區），換網路以前誰來開都一樣。
  blocked,
}

/// 依狀態碼、標頭與內容判斷 [BlockedPage]。只看 403、429、503：被擋的頁面
/// 都用這幾個狀態碼，正常頁面裡提到 Cloudflare 的字不算。
BlockedPage classifyBlockedPage({
  required int? statusCode,
  required Map<String, List<String>> headers,
  required String body,
}) {
  if (statusCode != 403 && statusCode != 429 && statusCode != 503) {
    return BlockedPage.none;
  }
  String? header(String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value.join(',');
    }
    return null;
  }

  // Cloudflare 在檢查頁加上這個標頭；舊的頁面沒有，再看內容。
  if (header('cf-mitigated')?.toLowerCase().contains('challenge') ?? false) {
    return BlockedPage.challenge;
  }
  if (_challengeMarkers.any(body.contains)) return BlockedPage.challenge;
  final fromCloudflare =
      header('cf-ray') != null ||
      (header('server')?.toLowerCase().contains('cloudflare') ?? false);
  if (fromCloudflare && _cloudflareBlockMarkers.any(body.contains)) {
    return BlockedPage.blocked;
  }
  if (_firewallBlockMarkers.any(body.contains)) return BlockedPage.blocked;
  return BlockedPage.none;
}

/// Cloudflare 檢查頁才有的程式與網址。
const List<String> _challengeMarkers = [
  'window._cf_chl_opt',
  '/cdn-cgi/challenge-platform/',
];

/// Cloudflare 的封鎖頁（「Sorry, you have been blocked」）。
const List<String> _cloudflareBlockMarkers = [
  'Sorry, you have been blocked',
  'cf-error-details',
];

/// 網站自己的防火牆寫明依 IP 或地區擋下（例如一流小說網）。
const List<String> _firewallBlockMarkers = ['IP归属地不受信任', 'IP歸屬地不受信任'];

/// 通過 Cloudflare 檢查的結果，可以跨 isolate 傳。
final class ClearanceResult {
  const ClearanceResult._(this.outcome, {this.cookies = '', this.userAgent});

  const ClearanceResult.passed({
    required String cookies,
    required String? userAgent,
  }) : this._(ClearanceOutcome.passed, cookies: cookies, userAgent: userAgent);

  const ClearanceResult.needsHuman()
    : this._(ClearanceOutcome.needsHuman, userAgent: null);

  const ClearanceResult.failed() : this._(ClearanceOutcome.failed);

  final ClearanceOutcome outcome;

  /// 瀏覽器拿到的這個網站的 Cookie（`a=1; b=2`），含網頁程式讀不到的
  /// `cf_clearance`。
  final String cookies;

  /// 通過檢查的瀏覽器標識；Cloudflare 的通行 Cookie 只對同一個標識有效。
  final String? userAgent;
}

enum ClearanceOutcome {
  passed,

  /// 等到最後還是停在要真人勾選的那一步。
  needsHuman,

  /// 沒有 WebView、載不到，或時間到了還沒通過。
  failed,
}

/// 用真的瀏覽器通過 Cloudflare 檢查，只在主 isolate 做。
abstract interface class CloudflareSolver {
  Future<ClearanceResult> solve(Uri uri);
}

/// 請瀏覽器通過 [uri] 所在網站的 Cloudflare 檢查。同一個網站同時只做一
/// 次，一起等的請求共用結果；通不過的網站記下來，一段時間內直接回報，不
/// 讓每一個請求都再開一次瀏覽器等上半分鐘。
abstract final class CloudflareClearance {
  /// 主 isolate 的瀏覽器（App 啟動時設定）；測試換成假的。
  static CloudflareSolver? solver;

  /// worker isolate 設定：交給主 isolate 做。
  static Future<ClearanceResult> Function(Uri uri)? delegate;

  /// 通不過的網站多久之內不再試。一次檢查最多要等半分鐘，閱讀、下載與搜尋
  /// 會對同一個網站連發好幾十個請求；十分鐘內網站的判定通常不會變，過了
  /// 再給它一次機會。
  static const Duration failureMemory = Duration(minutes: 10);

  static final Map<String, Future<ClearanceResult>> _inFlight = {};
  static final Map<String, (DateTime, ClearanceResult)> _recentFailures = {};

  static Future<ClearanceResult> clear(Uri uri) {
    final delegate = CloudflareClearance.delegate;
    if (delegate != null) return delegate(uri);
    final solver = CloudflareClearance.solver;
    if (solver == null) return Future.value(const ClearanceResult.failed());
    final host = uri.host;
    final failure = _recentFailures[host];
    if (failure != null) {
      if (DateTime.now().difference(failure.$1) < failureMemory) {
        return Future.value(failure.$2);
      }
      _recentFailures.remove(host);
    }
    return _inFlight[host] ??= _solve(solver, uri, host);
  }

  static Future<ClearanceResult> _solve(
    CloudflareSolver solver,
    Uri uri,
    String host,
  ) async {
    try {
      final result = await solver.solve(uri);
      if (result.outcome == ClearanceOutcome.passed) {
        final userAgent = result.userAgent;
        if (userAgent != null) WebViewUserAgent.value = userAgent;
      } else {
        _recentFailures[host] = (DateTime.now(), result);
      }
      return result;
    } catch (_) {
      const result = ClearanceResult.failed();
      _recentFailures[host] = (DateTime.now(), result);
      return result;
    } finally {
      // 移除的就是這一次自己，不能等它。
      _inFlight.remove(host)?.ignore();
    }
  }

  /// 測試用：忘掉進行中與記下的結果。
  static void reset() {
    _inFlight.clear();
    _recentFailures.clear();
  }
}

/// 手機內建瀏覽器的瀏覽器標識。帶著 Cloudflare 通行 Cookie 的請求要用它，
/// 規則的 `java.getWebViewUA()` 也傳回它。主 isolate 開 App 後讀一次，
/// 再轉給 worker；還沒讀到時是 null。
abstract final class WebViewUserAgent {
  static String? _value;

  /// 主 isolate 設定時轉給 worker（[onChanged]）。
  static void Function(String userAgent)? onChanged;

  static String? get value => _value;

  static set value(String? userAgent) {
    if (userAgent == null || userAgent.isEmpty || userAgent == _value) return;
    _value = userAgent;
    onChanged?.call(userAgent);
  }
}

/// 網站要求真人勾選才能通過 Cloudflare 檢查；夜讀不替你勾，這個網站當成
/// 不能用。
class HumanVerificationRequiredException extends AppException {
  HumanVerificationRequiredException() : super('網站要求真人驗證，夜讀不能自動通過');
}

/// 網站封鎖了目前的網路（IP 或地區）。
class SiteBlockedException extends AppException {
  SiteBlockedException() : super('網站封鎖了目前的網路，換一個網路才能用');
}

/// Cloudflare 檢查沒有自動通過（逾時或載不到）。
class ChallengeNotPassedException extends AppException {
  ChallengeNotPassedException() : super('網站的瀏覽器檢查沒有通過');
}

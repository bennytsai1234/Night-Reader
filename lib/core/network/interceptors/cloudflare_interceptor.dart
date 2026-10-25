import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:night_reader/core/network/cloudflare.dart';
import 'package:night_reader/core/network/interceptors/lenient_cookie_manager.dart';
import 'package:night_reader/core/services/app_log_service.dart';

/// 碰到 Cloudflare 的瀏覽器檢查時，請真的瀏覽器在背景通過它，存下通行
/// Cookie，再重送一次原本的請求；整個過程不需要使用者操作。要真人勾選的
/// 與封鎖網路的網站，改丟出看得懂原因的錯誤。
///
/// 通行 Cookie 只對通過檢查的瀏覽器標識有效，所以帶著它的請求一律改用
/// 手機內建瀏覽器的標識（[WebViewUserAgent]）。
class CloudflareInterceptor extends Interceptor {
  CloudflareInterceptor(this._dio, this._cookieJarSave);

  final Dio _dio;
  final Future<void> Function(Uri uri, List<Cookie> cookies) _cookieJarSave;

  static const String _retriedKey = '_cloudflareRetried';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final userAgent = WebViewUserAgent.value;
    if (userAgent != null && _hasClearanceCookie(options.headers)) {
      _setHeader(options.headers, 'User-Agent', userAgent);
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    if (err.type != DioExceptionType.badResponse || response == null) {
      handler.next(err);
      return;
    }
    final page = classifyBlockedPage(
      statusCode: response.statusCode,
      headers: response.headers.map,
      body: _bodyText(response.data),
    );
    switch (page) {
      case BlockedPage.none:
        handler.next(err);
      case BlockedPage.blocked:
        handler.next(_wrap(err, SiteBlockedException()));
      case BlockedPage.challenge:
        if (err.requestOptions.extra[_retriedKey] == true) {
          // 通過了檢查，重送還是被擋：通行 Cookie 沒被網站接受。記下來，
          // 下一章不必再開瀏覽器等一次。
          await CloudflareClearance.markRejected(err.requestOptions.uri);
          handler.next(_wrap(err, ChallengeNotPassedException()));
          return;
        }
        await _clearAndRetry(err, handler);
    }
  }

  Future<void> _clearAndRetry(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;
    // POST 的網址不一定能直接打開（搜尋表單），改開網站首頁；通行 Cookie
    // 對整個網站有效。
    final pageUri = request.method.toUpperCase() == 'GET'
        ? request.uri
        : request.uri.replace(path: '/', query: '');
    AppLog.i('Cloudflare 檢查：請瀏覽器在背景通過 ${request.uri.host}');
    final result = await CloudflareClearance.clear(pageUri);
    switch (result.outcome) {
      case ClearanceOutcome.needsHuman:
        handler.next(_wrap(err, HumanVerificationRequiredException()));
        return;
      case ClearanceOutcome.failed:
        handler.next(_wrap(err, ChallengeNotPassedException()));
        return;
      case ClearanceOutcome.passed:
        break;
    }
    final cookies = _parseCookies(result.cookies);
    if (cookies.isNotEmpty) {
      await _cookieJarSave(request.uri, cookies);
    }
    final headers = <String, dynamic>{...request.headers};
    // 原本的 Cookie 標頭沒有通行 Cookie；Cookie 管理器會照新的合併。
    if (cookies.isNotEmpty) {
      _setHeader(
        headers,
        HttpHeaders.cookieHeader,
        _mergeCookieHeader(request.headers, cookies),
      );
    }
    final userAgent = result.userAgent ?? WebViewUserAgent.value;
    if (userAgent != null) _setHeader(headers, 'User-Agent', userAgent);
    final retry = request.copyWith(
      extra: {...request.extra, _retriedKey: true},
      headers: headers,
    );
    try {
      handler.resolve(await _dio.fetch<dynamic>(retry));
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  static DioException _wrap(DioException err, Object reason) => DioException(
    requestOptions: err.requestOptions,
    response: err.response,
    type: DioExceptionType.unknown,
    error: reason,
    message: reason.toString(),
  );

  static bool _hasClearanceCookie(Map<String, dynamic> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'cookie' &&
          '${entry.value}'.contains('cf_clearance=')) {
        return true;
      }
    }
    return false;
  }

  /// 改掉不分大小寫同名的標頭。不先刪再加：Dio 的標頭表比對名稱不分
  /// 大小寫，刪過再加會碰到 Dart VM 的已刪除欄位而丟出型別錯誤。
  static void _setHeader(
    Map<String, dynamic> headers,
    String name,
    String value,
  ) {
    final lower = name.toLowerCase();
    final same = [
      for (final key in headers.keys)
        if (key.toLowerCase() == lower) key,
    ];
    headers[same.isEmpty ? name : same.first] = value;
    for (final key in same.skip(1)) {
      headers.remove(key);
    }
  }

  /// 瀏覽器只交出 `名稱=值`，沒有路徑；不指定的話 Cookie 檔會照觸發檢查
  /// 的網址目錄（例如 `/book/`）存，換到 `/search` 就拿不到。Cloudflare 的
  /// Cookie 都對整個網站（`/`）有效，只存這些；網站自己的 Cookie 照舊由
  /// 回應的 Set-Cookie 存。
  static List<Cookie> _parseCookies(String cookies) => [
    for (final pair in cookies.split(';'))
      if (parseSetCookieValueLenient(pair.trim(), ignoreInvalidCookies: true)
          case final cookie? when _isCloudflareCookie(cookie.name))
        cookie..path = '/',
  ];

  static bool _isCloudflareCookie(String name) =>
      name == 'cf_clearance' ||
      name == '_cfuvid' ||
      name.startsWith('__cf') ||
      name.startsWith('cf_chl');

  static String _mergeCookieHeader(
    Map<String, dynamic> headers,
    List<Cookie> cookies,
  ) {
    final merged = <String, String>{};
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != 'cookie') continue;
      for (final pair in '${entry.value}'.split(';')) {
        final index = pair.indexOf('=');
        if (index <= 0) continue;
        merged[pair.substring(0, index).trim()] = pair.substring(index + 1);
      }
    }
    for (final cookie in cookies) {
      merged[cookie.name] = cookie.value;
    }
    return merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// 被擋的頁面不大，前 64 KB 就夠判斷。
  static String _bodyText(Object? data) {
    if (data == null) return '';
    if (data is String) return data;
    if (data is List<int>) {
      final bytes = data.length > 65536 ? data.sublist(0, 65536) : data;
      return utf8.decode(bytes, allowMalformed: true);
    }
    return '$data';
  }
}

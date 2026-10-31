import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import '../js_extensions.dart';
import 'js_blocking_tasks.dart';

import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/network/cloudflare.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/source_validation_context.dart';
import 'package:night_reader/core/network/interceptors/app_interceptor.dart';

/// 網路/WebView/I/O 相關 `java.*` 方法的 Dart 側 handler。
///
/// 要等的都經 [onBlocking]：網址在這裡（書源 isolate）組好，網址裡的 JS 也
/// 在這裡跑；發請求交給網路 isolate（[BlockingCall]，ADR 0034）。
extension JsNetworkExtensions on JsExtensions {
  void injectNetworkExtensions() {
    // ─── java.ajax(url) — 返回 body 字串 ─────────────────────────
    onBlocking('ajax', (payload) {
      final url = _parseUrlArg(payload);
      try {
        return BlockingCall.run(responseBody(_analyzeUrl(url)));
      } catch (e) {
        AppLog.e('java.ajax failed: $e');
        rethrow;
      }
    });

    // ─── java.ajaxAll(urlList) — 返回回應陣列（JS 端包成回應物件） ──
    onBlocking('ajaxAll', (payload) {
      if (payload is! List) return const <Object?>[];
      try {
        return BlockingCall.run(
          responses([for (final url in payload) _analyzeUrl('$url')]),
        );
      } catch (e) {
        AppLog.e('java.ajaxAll failed: $e');
        rethrow;
      }
    });

    // ─── java.connect(url, header) — 返回 {body, url, code} ──────
    onBlocking('connect', (payload) {
      final url = _parseUrlArg(payload);
      final AnalyzeUrl analyzeUrl;
      try {
        analyzeUrl = _analyzeUrl(url);
      } catch (e) {
        // 網址組不起來（例如網址裡的 JS 出錯）也照請求失敗傳回，不丟出。
        AppLog.e('java.connect failed: $e');
        return failedResponse(url, e);
      }
      analyzeUrl.headerMap.addAll(
        _parseOptionalHeaderMap(payload)
            .map((key, value) => MapEntry(key, value?.toString() ?? '')),
      );
      return BlockingCall.run(connectResponse(analyzeUrl));
    });

    // ─── java.get(url, headers) — 返回 {body, url, code, headers} ─
    onBlocking('get', (payload) {
      if (payload is! List || payload.isEmpty) {
        throw ArgumentError('java.get requires [url, headers]');
      }
      return BlockingCall.run(
        rawResponse(
          method: 'GET',
          url: payload[0].toString(),
          headers: _headersAt(payload, 1),
        ),
      );
    });

    // ─── java.post(url, body, headers) ───────────────────────────
    onBlocking('post', (payload) {
      if (payload is! List || payload.length < 2) {
        throw ArgumentError('java.post requires [url, body, headers]');
      }
      final body = payload[1];
      final headers = _headersAt(payload, 2);
      if (body is String &&
          !headers.keys.any((key) => key.toLowerCase() == 'content-type')) {
        final rawBody = body.trimLeft();
        headers['Content-Type'] =
            (rawBody.startsWith('{') || rawBody.startsWith('['))
            ? 'application/json; charset=utf-8'
            : 'application/x-www-form-urlencoded; charset=utf-8';
      }
      return BlockingCall.run(
        rawResponse(
          method: 'POST',
          url: payload[0].toString(),
          data: body,
          headers: headers,
        ),
      );
    });

    // ─── java.head(url, headers) — 返回 headers/status，且不自動跟跳轉 ───
    onBlocking('head', (payload) {
      if (payload is! List || payload.isEmpty) {
        throw ArgumentError('java.head requires [url, headers]');
      }
      return BlockingCall.run(
        rawResponse(
          method: 'HEAD',
          url: payload[0].toString(),
          headers: _headersAt(payload, 1),
        ),
      );
    });

    // ─── java.getCookie(tag, key) ────────────────────────────────
    onBlocking('getCookie', (payload) {
      if (payload is! List || payload.isEmpty) return '';
      final cookie = siteCookie(payload[0].toString());
      final key = payload.length > 1 ? payload[1]?.toString() : null;
      if (key == null || key.isEmpty) return cookie;
      return cookieStore.cookieToMap(cookie)[key] ?? '';
    });

    // ─── java.webView(html, url, js) 這一類 ──────────────────────
    onBlocking('webView', (payload) {
      if (payload is! List) return '';
      return _backstage(payload);
    });
    onBlocking('webViewGetSource', (payload) {
      if (payload is! List) return '';
      return _backstage(payload, sourceRegex: _stringAt(payload, 3));
    });
    onBlocking('webViewGetOverrideUrl', (payload) {
      if (payload is! List) return '';
      return _backstage(payload, overrideUrlRegex: _stringAt(payload, 3));
    });

    // ─── java.startBrowserAwait / java.getVerificationCode ───────
    // 驗證 UI 已移除；書源若呼叫這兩個方法一律快速拒絕，
    // 使書源校驗能正確標記為「需要互動驗證」而非逾時。
    onBlocking(
      'startBrowserAwait',
      (_) => throw const SourceInteractionBlockedException('不支援互動驗證'),
    );
    onBlocking(
      'getVerificationCode',
      (_) => throw const SourceInteractionBlockedException('不支援互動驗證'),
    );

    // ─── java.getZipByteArrayContent(url, innerPath) ─────────────
    onBlocking('getZipByteArrayContent', (payload) {
      if (payload is! List || payload.length < 2) return null;
      final url = payload[0].toString();
      if (!url.startsWith('http')) return null;
      try {
        final bytes =
            BlockingCall.run(responseBytes(_analyzeUrl(url))) as Uint8List;
        final file = ZipDecoder().decodeBytes(bytes).findFile('${payload[1]}');
        return file?.content as List<int>?;
      } catch (_) {
        return null;
      }
    });

    // ─── java.getWebViewUA — 手機內建瀏覽器的標識，還沒讀到時用預設 ──
    runtime.onMessage(
      'getWebViewUA',
      (dynamic _) => WebViewUserAgent.value ?? AppInterceptor.mobileUserAgent,
    );

    // ─── java.timeFormatUTC — 真正同步 ───────────────────────────
    runtime.onMessage('timeFormatUTC', (dynamic args) {
      try {
        final time = args[0] as int;
        final format = args[1].toString();
        final offsetMs = args[2] as int;
        final date = DateTime.fromMillisecondsSinceEpoch(
          time,
          isUtc: true,
        ).add(Duration(milliseconds: offsetMs));
        return DateFormat(format).format(date);
      } catch (_) {
        return '';
      }
    });
  }

  /// [url] 在這個書源下組好的請求；網址裡的 JS 在這裡跑完。
  AnalyzeUrl _analyzeUrl(String url) =>
      AnalyzeUrl(url, source: source as BookSource?);

  String _backstage(
    List<dynamic> payload, {
    String? sourceRegex,
    String? overrideUrlRegex,
  }) {
    try {
      return BlockingCall.run(
        backstagePage(
          html: _stringAt(payload, 0),
          url: _stringAt(payload, 1),
          javaScript: _stringAt(payload, 2),
          sourceRegex: sourceRegex,
          overrideUrlRegex: overrideUrlRegex,
        ),
      ) as String;
    } catch (e) {
      AppLog.e('java.webView failed: $e', error: e);
      rethrow;
    }
  }

  static String? _stringAt(List<dynamic> payload, int index) =>
      payload.length > index ? payload[index]?.toString() : null;

  static Map<String, dynamic> _headersAt(List<dynamic> payload, int index) =>
      payload.length > index && payload[index] is Map
      ? Map<String, dynamic>.from(payload[index] as Map)
      : <String, dynamic>{};

  /// 從 JS payload 解析 URL 字串 (兼容 String / List 兩種來源)
  String _parseUrlArg(dynamic payload) {
    if (payload is List && payload.isNotEmpty) return payload[0].toString();
    return payload.toString();
  }

  Map<String, dynamic> _parseOptionalHeaderMap(dynamic payload) {
    if (payload is! List || payload.length < 2) {
      return <String, dynamic>{};
    }
    final rawHeaders = payload[1];
    if (rawHeaders is Map) {
      return Map<String, dynamic>.from(rawHeaders);
    }
    return <String, dynamic>{};
  }
}

import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import '../js_extensions.dart';
import 'js_blocking_tasks.dart';
import 'js_jsoup_http.dart';

import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/network/cloudflare.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/source_interaction.dart';
import 'package:night_reader/core/network/interceptors/app_interceptor.dart';
import 'package:night_reader/core/utils/network_utils.dart';

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

    // ─── org.jsoup.Jsoup.connect(url)…execute() ──────────────────
    onBlocking(
      'jsoupExecute',
      (payload) => BlockingCall.run(
        jsoupExecute(Map<String, Object?>.from(payload as Map)),
      ),
    );

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

    // ─── java.startBrowser／startBrowserAwait／getVerificationCode ──
    // 要使用者操作的：只有登入頁按下的動作可以（[SourceInteraction]），其他
    // 地方立刻失敗、記下要開的網頁給閱讀器的「前往驗證」，背景工作不停下來
    // 等人（ADR 0038）。網址與標頭在這裡組好，請求經網路 isolate 送到主
    // isolate 的登入頁，這條停住等使用者。
    onBlocking('startBrowser', (payload) {
      if (!SourceInteraction.allowed) {
        // Legado 會開瀏覽器、不等結果；夜讀不從背景跳出畫面，照日誌記下。
        AppLog.i('書源要開網頁，只有在登入頁才會開: ${_stringAt(payload, 0)}');
        return null;
      }
      _browse(_browseRequest(payload));
      return null;
    });
    onBlocking('startBrowserAwait', (payload) {
      final args = payload is List ? payload : [payload];
      final request = _browseRequest(args);
      if (!SourceInteraction.allowed) SourceInteraction.blocked(request);
      final url = request.url;
      final html = _browse(request);
      if (html == null || html.isEmpty) throw Exception('驗證結果為空');
      // 和 Legado 一樣預設用書源的標頭重抓一次網址，交出通過驗證後的網頁；
      // 書源指定不重抓（第三個參數 false）時交出瀏覽器裡的網頁。
      if (args.length > 2 && args[2] == false) {
        return {
          'body': html,
          'url': url,
          'requestUrl': url,
          'code': 200,
          'message': '',
          'headers': const <String, Object?>{},
          'redirects': const <String>[],
          'autoRedirects': const <String>[],
        };
      }
      return (BlockingCall.run(responses([_analyzeUrl(url)])) as List).first;
    });
    onBlocking('getVerificationCode', (payload) {
      if (!SourceInteraction.allowed) SourceInteraction.blocked(null);
      // 圖片照書源的請求抓（同一個登入中的 Cookie 與標頭，回應的 Cookie 也
      // 存下來），驗證碼才對得上這次登入。
      final image = BlockingCall.run(
        responseBytes(_analyzeUrl(_absoluteUrl('$payload'))),
      ) as Uint8List;
      final code =
          BlockingCall.run(askUser(SourceCodeRequest(image: image))) as String?;
      if (code == null || code.isEmpty) throw Exception('驗證結果為空');
      return code;
    });

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

  /// `[網址, 標題]` 要開的網頁。
  SourceBrowseRequest _browseRequest(dynamic payload) {
    final args = payload is List ? payload : [payload];
    return SourceBrowseRequest(
      url: _absoluteUrl(_stringAt(args, 0) ?? ''),
      title: _stringAt(args, 1) ?? '',
      headers: _sourceHeaders(),
    );
  }

  /// 開網頁讓使用者操作，停住等他按完成，傳回網頁內容；沒按完成就離開時
  /// 是 null。只有登入頁按下的動作會走到這裡。
  String? _browse(SourceBrowseRequest request) =>
      BlockingCall.run(askUser(request)) as String?;

  String _absoluteUrl(String url) {
    final base = source?.getKey();
    return base == null ? url : NetworkUtils.getAbsoluteURL(base, url);
  }

  /// 書源的標頭（含登入標頭）。
  Map<String, String> _sourceHeaders() =>
      source?.getHeaderMapSync() ?? const {};

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

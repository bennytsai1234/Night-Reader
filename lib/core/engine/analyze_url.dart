import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:night_reader/core/models/base_source.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/services/http_client.dart';
import 'package:night_reader/core/services/rate_limiter.dart';
import 'package:night_reader/core/services/encoding_detect.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/engine/js/extensions/js_blocking_tasks.dart';
import 'package:night_reader/core/engine/web_book/headless_webview_service.dart';
import 'package:night_reader/core/network/redirects.dart';
import 'package:night_reader/core/network/str_response.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/network/cancellation.dart';

/// AnalyzeUrl - URL 規則解析與請求建構 (原 Android AnalyzeUrl.kt)
class AnalyzeUrl {
  final String rawUrl;
  final String? key;
  final int? page;
  final String baseUrl;
  final BaseSource? source;
  final dynamic ruleData;
  final String? speakText;
  final int? speakSpeed;

  String ruleUrl = '';
  String url = '';
  String method = 'GET';
  final Map<String, String> headerMap = {};
  dynamic body;
  String? charset;
  bool useWebView = false;
  String? webJs;
  int webViewDelayTime = 0;

  /// 組好網址：書源 header、網址裡的 `@js:`／`<js>`、`{{}}`、網址選項。裡面
  /// 的 JS 同步執行，要等網路的呼叫在書源 isolate 停住等（ADR 0034）。
  ///
  /// 組好之後只剩資料，可以整個送到網路 isolate 發請求（規則 JS 的
  /// `java.ajax` 就是這樣）。
  AnalyzeUrl(
    this.rawUrl, {
    this.key,
    this.page,
    this.speakText,
    this.speakSpeed,
    this.baseUrl = '',
    this.source,
    this.ruleData,
  }) {
    _init();
  }

  void _init() {
    try {
      // 0. 注入 BookSource.header 與登入標頭
      _initSourceHeaders();
      _initLoginHeaders();
      ruleUrl = rawUrl;
      // 1. 執行 @js, <js>
      _analyzeJs();
      // 2. 替換 {{js}} 和 <page,page>
      _replaceKeyPageJs();
      // 3. 解析 URL 選項 (如 ,{"method": "POST"})
      _analyzeUrlOptions();
    } finally {
      _releaseJsRule();
    }
  }

  /// 組網址期間（書源 header、網址裡的 JS、`{{}}`、選項）共用一個規則與它的
  /// JS 引擎，組完就釋放。每建一個引擎要好幾毫秒，一個網址常有兩三段 JS，
  /// 搜尋時每個書源都要組一次網址，逐段新建會在畫面執行緒上累積成掉幀。
  /// jsLib 裡的變數因此在同一個網址的各段之間延續，和清單逐項共用外層規則
  /// 的引擎一樣；原版 Legado 的 jsLib 作用域更是整個書源共用。
  AnalyzeRule? _jsRuleInstance;

  AnalyzeRule _jsRule() {
    final rule = _jsRuleInstance ??= AnalyzeRule(
      source: source,
      ruleData: ruleData,
    );
    rule.key = key;
    rule.page = page ?? 1;
    return rule;
  }

  void _releaseJsRule() {
    _jsRuleInstance?.dispose();
    _jsRuleInstance = null;
  }

  /// 登入標頭（書源登入程式存的身分資料，例如 token）跟著每次請求送出，蓋過
  /// 書源 header 的同名欄位，網址選項的標頭再蓋過它，同 Legado
  /// （`getHeaderMap(true)`）。
  ///
  /// 只有有登入的書源才找：記憶體沒有時在書源 isolate 停住讀資料庫，讀到
  /// 沒有就在記憶體記成空的，之後不再讀；登入時寫入的會經由記憶體同步蓋過
  /// 它。不能停住的 isolate（主 isolate）只看記憶體。
  void _initLoginHeaders() {
    final source = this.source;
    if (source is! BaseSource || !source.hasLogin) return;
    final key = source.loginHeaderCacheKey;
    final cache = CacheManager();
    var raw = cache.getMemoryText(key);
    if (raw == null && BlockingCall.available) {
      raw = BlockingCall.run(cacheRead(key)) as String? ?? '';
      if (raw.isEmpty) cache.putMemory(key, '');
    }
    headerMap.addAll(BaseSource.decodeLoginHeader(raw));
  }

  /// 將 BookSource.header（JSON 格式）解析並注入 headerMap
  void _initSourceHeaders() {
    final headerStr = source is BaseSource
        ? (source as BaseSource).header
        : null;
    if (headerStr == null || headerStr.isEmpty) return;
    try {
      final resolvedHeaderStr = _resolveMaybeJsString(headerStr);
      final headers = _decodeLooseObject(resolvedHeaderStr);
      if (headers != null) {
        headers.forEach((k, v) => headerMap[k.toString()] = v.toString());
      }
    } catch (e) {
      AppLog.e('AnalyzeUrl source header parse error: $e', error: e);
    }
  }

  void _analyzeJs() {
    final jsRegex = RegExp(
      r'@js:([\s\S]*?)$|<js>([\s\S]*?)</js>',
      caseSensitive: false,
    );
    var result = ruleUrl;
    final matches = jsRegex.allMatches(ruleUrl);

    int lastEnd = 0;

    for (final match in matches) {
      final jsStr = match.group(1) ?? match.group(2) ?? '';
      final jsInput = _jsInputForMatch(match.start, result);
      final evalRes = _jsRule().evalJS(jsStr, jsInput);
      result = evalRes?.toString() ?? '';
      lastEnd = match.end;
    }

    if (lastEnd > 0) {
      ruleUrl = result;
    }
  }

  void _replaceKeyPageJs() {
    // 先替換已知模板變數，避免被 {{js}} 正則吃掉
    if (key != null) {
      ruleUrl = ruleUrl.replaceAll('{{key}}', _encodeKey(key!));
    }
    if (page != null) {
      ruleUrl = ruleUrl.replaceAll('{{page}}', page.toString());
    }
    if (speakText != null) {
      ruleUrl = ruleUrl.replaceAll('{{speakText}}', speakText!);
    }
    if (speakSpeed != null) {
      ruleUrl = ruleUrl.replaceAll('{{speakSpeed}}', speakSpeed!.toString());
    }

    // 替換剩餘的 {{js}} 表達式
    final innerJsRegex = RegExp(r'\{\{([\s\S]*?)\}\}');
    ruleUrl = ruleUrl.replaceAllMapped(innerJsRegex, (match) {
      final jsStr = match.group(1)!;
      return _jsRule().evalJS(jsStr, null)?.toString() ?? '';
    });

    // 替換 <page1,page2,page3>
    if (page != null) {
      final pageRegex = RegExp(r'<(.*?)>');
      ruleUrl = ruleUrl.replaceAllMapped(pageRegex, (match) {
        final pages = match.group(1)!.split(',');
        if (page! <= pages.length) {
          return pages[page! - 1].trim();
        }
        return pages.last.trim();
      });
    }
  }

  String _jsInputForMatch(int matchStart, String currentValue) {
    if (matchStart <= 0) {
      return currentValue;
    }
    final clampedStart = matchStart.clamp(0, currentValue.length);
    return currentValue.substring(0, clampedStart).trimRight();
  }

  /// 根據 charset 對搜尋關鍵字做 URL 編碼
  /// 預設 UTF-8，支援 GBK/GB2312/GB18030
  String _encodeKey(String key) {
    // charset 在 _analyzeUrlOptions 裡才會解析出來，
    // 但 {{key}} 替換在 options 之前，所以先從 rawUrl 裡嘗試提前偵測 charset
    final detectedCharset = _detectCharset();
    if (detectedCharset != null &&
        (detectedCharset.toUpperCase().contains('GBK') ||
            detectedCharset.toUpperCase().contains('GB2312') ||
            detectedCharset.toUpperCase().contains('GB18030'))) {
      // GBK 編碼: 逐位元組轉 %XX
      final bytes = gbk.encode(key);
      final sb = StringBuffer();
      for (final b in bytes) {
        sb.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
      return sb.toString();
    }
    return Uri.encodeComponent(key);
  }

  /// 從 rawUrl 的 JSON 選項中提前偵測 charset
  String? _detectCharset() {
    final paramSplitRegex = RegExp(r'\s*,\s*(?=\{)');
    final match = paramSplitRegex.firstMatch(ruleUrl);
    if (match != null) {
      try {
        final options = _decodeLooseObject(ruleUrl.substring(match.end).trim());
        return options?['charset']?.toString();
      } catch (_) {}
    }
    return null;
  }

  void _analyzeUrlOptions() {
    final paramSplitRegex = RegExp(r'\s*,\s*(?=\{)');
    final match = paramSplitRegex.firstMatch(ruleUrl);

    if (match != null) {
      url = ruleUrl.substring(0, match.start).trim();
      final optionStr = ruleUrl.substring(match.end).trim();
      try {
        final options = _decodeLooseObject(optionStr);
        if (options != null) {
          method = (options['method'] ?? 'GET').toString().toUpperCase();
          if (options['headers'] != null) {
            (options['headers'] as Map).forEach(
              (k, v) => headerMap[k.toString()] = v.toString(),
            );
          }
          body = options['body'];
          useWebView =
              options['webView'] == true || options['webView'] == 'true';
          webJs = options['webJs'];
          charset = options['charset'];
          webViewDelayTime =
              int.tryParse(options['webViewDelayTime']?.toString() ?? '0') ?? 0;
          final ruleJs = options['js']?.toString();
          if (ruleJs != null && ruleJs.isNotEmpty) {
            url = _jsRule().evalJS(ruleJs, url)?.toString() ?? url;
          }
        }
      } catch (e) {
        AppLog.e('AnalyzeUrl options parse error: $e', error: e);
      }
    } else {
      url = ruleUrl.trim();
    }

    // 處理相對路徑
    if (!url.startsWith('http')) {
      final resolvedBaseUrl = _resolveRelativeBaseUrl();
      if (resolvedBaseUrl.isNotEmpty) {
        final baseUri = Uri.parse(resolvedBaseUrl);
        url = baseUri.resolve(url).toString();
      }
    }
  }

  String _resolveRelativeBaseUrl() {
    if (baseUrl.isNotEmpty) {
      return baseUrl;
    }
    if (source is BaseSource) {
      final sourceKey = (source as BaseSource).getKey();
      if (sourceKey.isNotEmpty) {
        return sourceKey;
      }
    }
    return '';
  }

  String _resolveMaybeJsString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('@js:')) {
      return _jsRule().evalJS(trimmed.substring(4), null)?.toString() ?? '';
    }
    if (trimmed.toLowerCase().startsWith('<js>') &&
        trimmed.toLowerCase().endsWith('</js>')) {
      return _jsRule()
              .evalJS(trimmed.substring(4, trimmed.length - 5), null)
              ?.toString() ??
          '';
    }
    return raw;
  }

  Map<String, dynamic>? _decodeLooseObject(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}

    try {
      final normalized = _jsRule()
          .evalJS('JSON.stringify(($raw))', null)
          ?.toString();
      if (normalized == null || normalized.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(normalized);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}

    return null;
  }

  /// 獲取回應內容 (對標 Android AnalyzeUrl.getStrResponseAwait)
  ///
  /// 使用 ResponseType.bytes 取得原始位元組，再根據以下優先順序解碼：
  /// 1. 書源規則指定的 charset
  /// 2. HTTP Content-Type 標頭中的 charset
  /// 3. HTML <meta> 標籤中的 charset
  /// 4. 自動偵測 (UTF-8 / GBK)
  Future<StrResponse> getStrResponse({CancelToken? cancelToken}) async {
    // 規則 JS 裡的請求（java.ajax 這類）沒有傳，跟著所在的書源工作取消。
    cancelToken ??= currentSourceCancelToken;
    final limiter = ConcurrentRateLimiter(
      source is BaseSource ? source as BaseSource : null,
    );

    return limiter.withLimit(() async {
      // 注入站點 Cookie (對標 Android AnalyzeUrl.getProxyClient + CookieStore)
      // 若使用者規則已指定 Cookie，則合併保留使用者設定
      final storedCookie = await CookieStore().getCookie(url);
      if (storedCookie.isNotEmpty) {
        final userCookie = headerMap['Cookie'] ?? headerMap['cookie'];
        if (userCookie == null || userCookie.isEmpty) {
          headerMap['Cookie'] = storedCookie;
        } else {
          final merged = CookieStore().cookieToMap(storedCookie)
            ..addAll(CookieStore().cookieToMap(userCookie));
          headerMap['Cookie'] = CookieStore().mapToCookie(merged);
        }
        headerMap.remove('cookie');
      }

      // 如果開啟了 WebView 抓取模式
      if (useWebView) {
        // WebView 渲染沒辦法中途停下；取消時不再等它，結果丟掉。
        final finalBody = await untilCancelled(
          HeadlessWebViewService().getRenderedHtml(
            url: url,
            headers: headerMap,
            js: webJs,
            delayTime: webViewDelayTime,
          ),
          cancelToken,
        );
        return StrResponse(
          url: url,
          body: finalBody,
          headers: {},
          raw: Response(
            requestOptions: RequestOptions(path: url),
            data: finalBody,
          ),
        );
      }

      final httpClient = HttpClient();
      final options = Options(
        method: method,
        headers: _buildRequestHeaders(),
        responseType: ResponseType.bytes,
      );

      // 網路連線類錯誤重試：最多 3 次 (初次 + 2 retries)，退避 300ms / 1200ms
      // 對標 Android OkHttp RetryAndFollowUpInterceptor 行為
      Response<List<int>> rawResponse;
      const int maxAttempts = 3;
      for (var attempt = 1; ; attempt++) {
        try {
          if (method == 'POST') {
            rawResponse = await httpClient.client.post<List<int>>(
              url,
              data: body,
              options: options,
              cancelToken: cancelToken,
            );
          } else {
            rawResponse = await httpClient.client.get<List<int>>(
              url,
              options: options,
              cancelToken: cancelToken,
            );
          }
          break;
        } on DioException catch (e) {
          if (attempt >= maxAttempts || !_isRetryable(e)) rethrow;
          AppLog.d('AnalyzeUrl: 請求失敗 (${e.type}) → 第 $attempt 次重試: $url');
          // 退避期間取消就不再試。
          await Future.any<Object?>([
            Future<void>.delayed(
              Duration(milliseconds: 300 * attempt * attempt),
            ),
            ?cancelToken?.whenCancel,
          ]);
          if (cancelToken?.cancelError case final cancelled?) throw cancelled;
        }
      }

      final responseBytes = Uint8List.fromList(rawResponse.data ?? []);
      final decodedBody = _decodeResponseBody(responseBytes, rawResponse);

      return StrResponse(
        url: rawResponse.finalUri.toString(),
        body: decodedBody,
        headers: rawResponse.headers.map,
        raw: rawResponse,
      );
    }, cancelToken: cancelToken);
  }

  /// 判斷 Dio 錯誤是否屬於可重試的暫時性網路故障
  /// (connectionTimeout / sendTimeout / receiveTimeout / connectionError / 未知 SocketException)
  /// 不重試: cancel、badResponse (HTTP 4xx/5xx)、badCertificate、transformTimeout (回應轉換逾時)
  bool _isRetryable(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.unknown:
        // Socket 層級故障也算暫時性；網站擋下來（Cloudflare、封鎖網路）
        // 這類已經判斷過的原因再試也一樣。
        return e.error != null && e.error is! AppException;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
      case DioExceptionType.transformTimeout:
        // 用戶端資料轉換逾時,非網路層暫時性故障,重試只會重跑請求再次逾時
        return false;
    }
  }

  /// 依優先順序解碼回應位元組 (對標 Android OkHttpUtils.ResponseBody.text())
  String _decodeResponseBody(Uint8List bytes, Response response) {
    if (bytes.isEmpty) return '';

    // 移除 UTF-8 BOM
    Uint8List cleanBytes = bytes;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      cleanBytes = bytes.sublist(3);
    }

    // 1. 書源規則指定的 charset (最高優先)
    if (charset != null && charset!.isNotEmpty) {
      return _decodeWithCharset(cleanBytes, charset!);
    }

    // 2. HTTP Content-Type 標頭中的 charset
    final contentType = response.headers.value('content-type');
    if (contentType != null) {
      final ctCharset = _extractCharsetFromContentType(contentType);
      if (ctCharset != null) {
        return _decodeWithCharset(cleanBytes, ctCharset);
      }
    }

    // 3. HTML meta 標籤 + 自動偵測 (EncodingDetect.getHtmlEncode)
    final detected = EncodingDetect.getHtmlEncode(cleanBytes);
    return _decodeWithCharset(cleanBytes, detected);
  }

  /// 從 Content-Type 標頭提取 charset
  String? _extractCharsetFromContentType(String contentType) {
    final match = RegExp(
      r'''charset\s*=\s*["']?([^;\s"']+)''',
      caseSensitive: false,
    ).firstMatch(contentType);
    return match?.group(1);
  }

  /// 根據 charset 名稱解碼位元組
  String _decodeWithCharset(Uint8List bytes, String charsetName) {
    return EncodingDetect.decodeWithCharset(bytes, charsetName);
  }

  /// 獲取回應內容的 body (兼容舊代碼)
  Future<String> getResponseBody() async {
    final res = await getStrResponse();
    return res.body;
  }

  /// 獲取位元組回應內容
  Future<Uint8List> getByteArray() async {
    final cancelToken = currentSourceCancelToken;
    final limiter = ConcurrentRateLimiter(
      source is BaseSource ? source as BaseSource : null,
    );

    return limiter.withLimit(() async {
      // 注入站點 Cookie
      final storedCookie = await CookieStore().getCookie(url);
      if (storedCookie.isNotEmpty &&
          (headerMap['Cookie'] == null || headerMap['Cookie']!.isEmpty)) {
        headerMap['Cookie'] = storedCookie;
      }
      final httpClient = HttpClient();
      final options = Options(
        method: method,
        headers: _buildRequestHeaders(),
        responseType: ResponseType.bytes,
      );

      Response<List<int>> response;
      if (method == 'POST') {
        response = await httpClient.client.post<List<int>>(
          url,
          data: body,
          options: options,
          cancelToken: cancelToken,
        );
      } else {
        response = await httpClient.client.get<List<int>>(
          url,
          options: options,
          cancelToken: cancelToken,
        );
      }

      return Uint8List.fromList(response.data ?? []);
    }, cancelToken: cancelToken);
  }

  Map<String, String> _buildRequestHeaders() {
    final headers = Map<String, String>.from(headerMap);
    if (method == 'POST' && body is String && !_hasContentType(headers)) {
      final rawBody = (body as String).trimLeft();
      headers['Content-Type'] =
          (rawBody.startsWith('{') || rawBody.startsWith('['))
          ? 'application/json; charset=utf-8'
          : 'application/x-www-form-urlencoded; charset=utf-8';
    }
    return headers;
  }

  bool _hasContentType(Map<String, String> headers) {
    return headers.keys.any((key) => key.toLowerCase() == 'content-type');
  }
}

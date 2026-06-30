import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:night_reader/core/models/base_source.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/services/http_client.dart';
import 'package:night_reader/core/services/rate_limiter.dart';
import 'package:night_reader/core/services/encoding_detect.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/source_validation_context.dart';
import 'package:night_reader/core/engine/web_book/headless_webview_service.dart';
import 'package:night_reader/core/network/str_response.dart';

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
  String? _prefetchedResponseBody;
  String? _prefetchedResponseUrl;
  String? _prefetchedResponseRequestUrl;
  String? _prefetchedResponseRedirectUrl;

  /// **注意**：這個同步建構子只能處理純同步的 rule JS（不含
  /// `java.ajax` / `cache.get` 等 async 呼叫）。書源實務上若規則內含 async
  /// `@js:` 片段，請改用 [create] async factory。
  ///
  /// 保留同步版本是為了兼容 JS handler 內部用 plain URL 字串建構
  /// `AnalyzeUrl` 的路徑——那些呼叫沒有 rule JS 可以執行，不需要 bridge。
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

  /// 不跑 JS 初始化的私有建構子；供 [create] factory 使用。
  AnalyzeUrl._bare(
    this.rawUrl, {
    this.key,
    this.page,
    this.speakText,
    this.speakSpeed,
    this.baseUrl = '',
    this.source,
    this.ruleData,
  });

  /// 以 async pipeline 建構 AnalyzeUrl。支援 rule JS 內的 `java.ajax`/
  /// `cache.get` 等 Promise bridge 方法。
  ///
  /// 呼叫路徑：
  /// 1. 建立 bare 實例（僅儲存欄位）
  /// 2. 執行 `_initAsync` → 注入 source headers → await `@js:`/`<js>` 評估
  ///    → await `{{js}}` 表達式替換 → 解析 URL options
  static Future<AnalyzeUrl> create(
    String rawUrl, {
    String? key,
    int? page,
    String? speakText,
    int? speakSpeed,
    String baseUrl = '',
    BaseSource? source,
    dynamic ruleData,
  }) async {
    final instance = AnalyzeUrl._bare(
      rawUrl,
      key: key,
      page: page,
      speakText: speakText,
      speakSpeed: speakSpeed,
      baseUrl: baseUrl,
      source: source,
      ruleData: ruleData,
    );
    await instance._initAsync();
    return instance;
  }

  void _init() {
    // 0. 注入 BookSource.header
    _initSourceHeaders();
    ruleUrl = rawUrl;
    // 1. 執行 @js, <js>
    _analyzeJs();
    // 2. 替換 {{js}} 和 <page,page>
    _replaceKeyPageJs();
    // 3. 解析 URL 選項 (如 ,{"method": "POST"})
    _analyzeUrlOptions();
  }

  Future<void> _initAsync() async {
    _initSourceHeaders();
    ruleUrl = rawUrl;
    await _analyzeJsAsync();
    await _replaceKeyPageJsAsync();
    _analyzeUrlOptions();
  }

  /// 將 BookSource.header（JSON 格式）解析並注入 headerMap
  void _initSourceHeaders() {
    final headerStr =
        source is BaseSource ? (source as BaseSource).header : null;
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
      final rule = AnalyzeRule(source: source, ruleData: ruleData);
      try {
        rule.key = key;
        rule.page = page ?? 1;
        final jsInput = _jsInputForMatch(match.start, result);
        final evalRes = rule.evalJS(jsStr, jsInput);
        result = evalRes?.toString() ?? '';
        lastEnd = match.end;
      } finally {
        rule.dispose();
      }
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
      final rule = AnalyzeRule(source: source, ruleData: ruleData);
      try {
        rule.key = key;
        rule.page = page ?? 1;
        return rule.evalJS(jsStr, null)?.toString() ?? '';
      } finally {
        rule.dispose();
      }
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

  /// async 版本的 [_analyzeJs] — 支援 rule JS 內含 `java.ajax` 等 Promise
  /// bridge 方法。邏輯與同步版本一致，只是改用 [AnalyzeRule.evalJSAsync]。
  Future<void> _analyzeJsAsync() async {
    final jsRegex = RegExp(
      r'@js:([\s\S]*?)$|<js>([\s\S]*?)</js>',
      caseSensitive: false,
    );
    var result = ruleUrl;
    final matches = jsRegex.allMatches(ruleUrl).toList();
    if (matches.isEmpty) return;

    for (final match in matches) {
      final jsStr = match.group(1) ?? match.group(2) ?? '';
      final rule = AnalyzeRule(source: source, ruleData: ruleData);
      try {
        rule.key = key;
        rule.page = page ?? 1;
        final jsInput = _jsInputForMatch(match.start, result);
        final evalRes = await rule.evalJSAsync(jsStr, jsInput);
        _capturePrefetchedResponse(rule);
        result = evalRes?.toString() ?? '';
      } finally {
        rule.dispose();
      }
    }
    ruleUrl = result;
  }

  void _capturePrefetchedResponse(AnalyzeRule rule) {
    final body = rule.get('_lastHttpResponseBody');
    if (body.isEmpty) return;
    _prefetchedResponseBody = body;
    _prefetchedResponseUrl = rule.get('_lastHttpResponseUrl');
    _prefetchedResponseRequestUrl = rule.get('_lastHttpResponseRequestUrl');
    _prefetchedResponseRedirectUrl = rule.get('_lastHttpResponseRedirectUrl');
  }

  String _jsInputForMatch(int matchStart, String currentValue) {
    if (matchStart <= 0) {
      return currentValue;
    }
    final clampedStart = matchStart.clamp(0, currentValue.length);
    return currentValue.substring(0, clampedStart).trimRight();
  }

  /// async 版本的 [_replaceKeyPageJs] — `{{js}}` 表達式改走 [AnalyzeRule.evalJSAsync]。
  Future<void> _replaceKeyPageJsAsync() async {
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

    // `replaceAllMapped` 不支援 async mapper，手動用 StringBuffer 處理
    final innerJsRegex = RegExp(r'\{\{([\s\S]*?)\}\}');
    final matches = innerJsRegex.allMatches(ruleUrl).toList();
    if (matches.isNotEmpty) {
      final sb = StringBuffer();
      var lastEnd = 0;
      for (final m in matches) {
        sb.write(ruleUrl.substring(lastEnd, m.start));
        final jsStr = m.group(1)!;
        final rule = AnalyzeRule(source: source, ruleData: ruleData);
        try {
          rule.key = key;
          rule.page = page ?? 1;
          final v = await rule.evalJSAsync(jsStr, null);
          sb.write(v?.toString() ?? '');
        } finally {
          rule.dispose();
        }
        lastEnd = m.end;
      }
      sb.write(ruleUrl.substring(lastEnd));
      ruleUrl = sb.toString();
    }

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
            final rule = AnalyzeRule(source: source, ruleData: ruleData);
            try {
              rule.key = key;
              rule.page = page ?? 1;
              url = rule.evalJS(ruleJs, url)?.toString() ?? url;
            } finally {
              rule.dispose();
            }
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
      final rule = AnalyzeRule(source: source, ruleData: ruleData);
      try {
        rule.key = key;
        rule.page = page ?? 1;
        return rule.evalJS(trimmed.substring(4), null)?.toString() ?? '';
      } finally {
        rule.dispose();
      }
    }
    if (trimmed.toLowerCase().startsWith('<js>') &&
        trimmed.toLowerCase().endsWith('</js>')) {
      final rule = AnalyzeRule(source: source, ruleData: ruleData);
      try {
        rule.key = key;
        rule.page = page ?? 1;
        return rule
                .evalJS(trimmed.substring(4, trimmed.length - 5), null)
                ?.toString() ??
            '';
      } finally {
        rule.dispose();
      }
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
      final rule = AnalyzeRule(source: source, ruleData: ruleData);
      String? normalized;
      try {
        rule.key = key;
        rule.page = page ?? 1;
        normalized = rule.evalJS('JSON.stringify(($raw))', null)?.toString();
      } finally {
        rule.dispose();
      }
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
        if (SourceValidationContext.isNonInteractive) {
          throw const SourceInteractionBlockedException(
            '批量校驗不執行 WebView 載入或互動驗證',
          );
        }
        final finalBody = await HeadlessWebViewService().getRenderedHtml(
          url: url,
          headers: headerMap,
          js: webJs,
          delayTime: webViewDelayTime,
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
      final prefetchedBody = _consumePrefetchedResponseBody();
      if (prefetchedBody != null) {
        return StrResponse(
          url: url,
          body: prefetchedBody,
          headers: const <String, List<String>>{},
          raw: Response(
            requestOptions: RequestOptions(path: url),
            data: prefetchedBody,
          ),
        );
      }
      final options = Options(
        method: method,
        headers: _buildRequestHeaders(),
        responseType: ResponseType.bytes,
      );

      // 網路連線類錯誤重試：最多 3 次 (初次 + 2 retries)，指數退避 300ms / 900ms
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
          await Future.delayed(Duration(milliseconds: 300 * attempt * attempt));
        }
      }

      final responseBytes = Uint8List.fromList(rawResponse.data ?? []);
      final decodedBody = _decodeResponseBody(responseBytes, rawResponse);

      return StrResponse(
        url: rawResponse.realUri.toString(),
        body: decodedBody,
        headers: rawResponse.headers.map,
        raw: rawResponse,
      );
    });
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
        // Socket 層級故障也算暫時性
        return e.error != null;
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
      r'charset=([a-zA-Z0-9_-]+)',
      caseSensitive: false,
    ).firstMatch(contentType);
    return match?.group(1);
  }

  /// 根據 charset 名稱解碼位元組
  String _decodeWithCharset(Uint8List bytes, String charsetName) {
    final upper = charsetName.toUpperCase();
    if (upper == 'GBK' || upper == 'GB2312' || upper == 'GB18030') {
      try {
        return gbk.decode(bytes);
      } catch (_) {
        return utf8.decode(bytes, allowMalformed: true);
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 獲取回應內容的 body (兼容舊代碼)
  Future<String> getResponseBody() async {
    final res = await getStrResponse();
    return res.body;
  }

  /// 獲取位元組回應內容
  Future<Uint8List> getByteArray() async {
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
        );
      } else {
        response = await httpClient.client.get<List<int>>(
          url,
          options: options,
        );
      }

      return Uint8List.fromList(response.data ?? []);
    });
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

  String? _consumePrefetchedResponseBody() {
    final body = _prefetchedResponseBody;
    if (body == null || body.isEmpty) {
      return null;
    }
    if (!_matchesPrefetchedResponseUrl()) {
      return null;
    }
    _prefetchedResponseBody = null;
    return body;
  }

  bool _matchesPrefetchedResponseUrl() {
    final current = Uri.tryParse(url);
    if (current == null) {
      return false;
    }
    for (final candidate in <String?>[
      _prefetchedResponseUrl,
      _prefetchedResponseRedirectUrl,
      _prefetchedResponseRequestUrl,
    ]) {
      if (candidate == null || candidate.isEmpty) continue;
      final candidateUri = _resolveCandidateUri(candidate);
      if (candidateUri == null) continue;
      if (_isSameOrSupersetUrl(candidateUri, current)) {
        return true;
      }
    }
    return false;
  }

  Uri? _resolveCandidateUri(String candidate) {
    try {
      final direct = Uri.tryParse(candidate);
      if (direct != null && direct.hasScheme) {
        return direct;
      }
      final baseCandidates = <String>[
        if (_prefetchedResponseRequestUrl != null &&
            _prefetchedResponseRequestUrl!.isNotEmpty)
          _prefetchedResponseRequestUrl!,
        _resolveRelativeBaseUrl(),
      ];
      for (final base in baseCandidates) {
        if (base.isEmpty) continue;
        final baseUri = Uri.tryParse(base);
        if (baseUri == null || !baseUri.hasScheme) continue;
        return baseUri.resolve(candidate);
      }
      return direct;
    } catch (_) {
      return null;
    }
  }

  bool _isSameOrSupersetUrl(Uri candidate, Uri current) {
    if (candidate == current) {
      return true;
    }
    if (candidate.scheme != current.scheme ||
        candidate.host != current.host ||
        candidate.path != current.path) {
      return false;
    }
    if (candidate.queryParameters.isEmpty) {
      return true;
    }
    return candidate.queryParameters.entries.every(
      (entry) => current.queryParameters[entry.key] == entry.value,
    );
  }

  bool _hasContentType(Map<String, String> headers) {
    return headers.keys.any((key) => key.toLowerCase() == 'content-type');
  }

  @visibleForTesting
  Map<String, String> buildRequestHeadersForTesting() => _buildRequestHeaders();
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:dio/dio.dart';
import 'package:night_reader/core/models/base_source.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/js/encode/charsets.dart';
import 'package:night_reader/core/engine/rule_analyzer.dart';
import 'package:night_reader/core/services/backstage_webview.dart';
import 'package:night_reader/core/services/http_client.dart';
import 'package:night_reader/core/services/rate_limiter.dart';
import 'package:night_reader/core/services/encoding_detect.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/engine/js/extensions/js_blocking_tasks.dart';
import 'package:night_reader/core/network/interceptors/app_interceptor.dart';
import 'package:night_reader/core/network/redirects.dart';
import 'package:night_reader/core/network/str_response.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/network/cancellation.dart';
import 'package:night_reader/core/utils/encoder_utils.dart';
import 'package:night_reader/core/utils/network_utils.dart';

/// AnalyzeUrl - 書源網址的解析與請求，照 Legado `AnalyzeUrl.kt`。
///
/// 網址規則依序處理：書源標頭與登入標頭 → 網址裡的 `@js:`／`<js>` →
/// `{{}}` 與 `<頁,頁>` → 逗號後的網址選項（`{"method":"POST",...}`）。
/// `{{key}}` 代入原文，發請求時才照 `charset` 編碼查詢參數與表單；內文是
/// JSON 時不編碼。裡面的 JS 同步執行，要等網路的呼叫在書源 isolate 停住等
/// （ADR 0034）。
///
/// 組好之後只剩資料，可以整個送到網路 isolate 發請求（規則 JS 的
/// `java.ajax` 就是這樣）。
class AnalyzeUrl {
  final String rawUrl;
  final String? key;
  final int? page;
  final String baseUrl;
  final BaseSource? source;
  final dynamic ruleData;
  final String? speakText;
  final int? speakSpeed;

  /// 處理過 JS 與 `{{}}`、還帶著網址選項的網址（Legado `ruleUrl`）。
  String ruleUrl = '';

  /// 完整網址，查詢參數是原文（Legado `url`）。實際送出的見 [requestUrl]。
  String url = '';

  /// 網址選項 `type`：有給時 [getStrResponse] 的內文是回應位元組的十六進位
  /// （同 Legado），`java.downloadFile` 以它當副檔名。
  String? type;

  String method = 'GET';
  final Map<String, String> headerMap = {};

  /// 網址選項的 `body`；給的是 JSON 物件或陣列時轉成 JSON 文字。
  String? body;
  String? charset;

  /// 網址選項 `retry`：回應不是 2xx 時再試幾次（同 Legado）。
  int retry = 0;
  bool useWebView = false;
  String? webJs;
  int webViewDelayTime = 0;

  /// 網址選項 `serverID`（Legado 用來指定自訂的伺服器）。
  int? serverID;

  /// 給的 [baseUrl] 去掉網址選項，相對網址照它補。
  late final String _givenBaseUrl;

  /// 網址 JS 跑的時候的 `baseUrl`：先是 [_givenBaseUrl]，算出網址後是網址
  /// 的站點（同 Legado）。
  String _jsBaseUrl = '';
  String _urlNoQuery = '';
  String? _encodedQuery;
  String? _encodedForm;

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
    final optionStart = _paramPattern.firstMatch(baseUrl);
    _givenBaseUrl = optionStart == null
        ? baseUrl
        : baseUrl.substring(0, optionStart.start);
    _jsBaseUrl = _givenBaseUrl;
    try {
      // 書源標頭與登入標頭只在建立時放一次；initUrl 重跑時沿用，同 Legado。
      _initSourceHeaders();
      _initLoginHeaders();
      initUrl();
    } finally {
      _releaseJsRule();
    }
  }

  /// 網址選項的開頭：網址之後第一個「逗號接 `{`」。
  static final RegExp _paramPattern = RegExp(r'\s*,\s*(?=\{)');

  /// 重新處理網址（Legado `initUrl`）：網址裡的 JS、`{{}}`、頁碼與網址選項
  /// 再跑一次。登入檢查這類規則改了 Cookie 或變數後用它重組網址再抓。
  void initUrl() {
    final owns = _jsRuleInstance == null;
    try {
      ruleUrl = rawUrl;
      _analyzeJs();
      _replaceKeyPageJs();
      _analyzeUrl();
    } finally {
      if (owns) _releaseJsRule();
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
    rule
      ..key = key
      ..page = page ?? 1
      ..baseUrl = _jsBaseUrl
      ..urlContext = this;
    return rule;
  }

  void _releaseJsRule() {
    _jsRuleInstance?.dispose();
    _jsRuleInstance = null;
  }

  /// 網址 JS 跑到一半要把這個請求交給網路 isolate 時（[send] 裡捕捉它），
  /// 先拿下組網址用的 JS 引擎：引擎連著連接埠，不能跨 isolate（ADR 0034）。
  /// 送出時複製的是當下的物件，[send] 結束就裝回去。
  T whileSendable<T>(T Function() send) {
    final rule = _jsRuleInstance;
    _jsRuleInstance = null;
    try {
      return send();
    } finally {
      _jsRuleInstance = rule;
    }
  }

  /// 跑網址裡的一段 JS（Legado `AnalyzeUrl.evalJS`）：規則裡的 `java` 是
  /// 這個請求。
  dynamic evalJS(String jsStr, [dynamic result]) =>
      _jsRule().evalJS(jsStr, result);

  /// 登入標頭（書源登入程式存的身分資料，例如 token）跟著每次請求送出，蓋過
  /// 書源 header 的同名欄位，網址選項的標頭再蓋過它，同 Legado
  /// （`getHeaderMap(true)`）。
  ///
  /// 只有有登入的書源才找：記憶體沒有時在書源 isolate 停住讀資料庫，讀到
  /// 的（沒有就是空的）記在這條 isolate 的記憶體，之後不再讀。這筆不同步給
  /// 其他 isolate：同一時間登入頁剛寫入的真標頭可能被讀到的舊值蓋掉；登入
  /// 時寫入的經由記憶體同步過來，蓋過這裡記的。不能停住的 isolate（主
  /// isolate）只看記憶體。
  void _initLoginHeaders() {
    final source = this.source;
    if (source is! BaseSource || !source.hasLogin) return;
    final key = source.loginHeaderCacheKey;
    final cache = CacheManager();
    var raw = cache.getMemoryText(key);
    if (raw == null && BlockingCall.available) {
      raw = BlockingCall.run(cacheRead(key)) as String? ?? '';
      cache.applyMirroredWrite(key, raw, 0);
    }
    headerMap.addAll(BaseSource.decodeLoginHeader(raw));
  }

  /// 將 BookSource.header（JSON 格式）解析並注入 headerMap。標頭裡的
  /// `proxy` 是 Legado 的代理設定，夜讀不走代理，不當標頭送出。
  void _initSourceHeaders() {
    final headerStr = source?.header;
    if (headerStr == null || headerStr.isEmpty) return;
    try {
      final resolvedHeaderStr = _resolveMaybeJsString(headerStr);
      final headers = _decodeLooseObject(resolvedHeaderStr);
      if (headers != null) {
        headers.forEach((k, v) => headerMap[k.toString()] = v.toString());
      }
      headerMap.remove('proxy');
    } catch (e) {
      AppLog.e('AnalyzeUrl source header parse error: $e', error: e);
    }
  }

  static final RegExp _jsPattern = RegExp(
    r'<js>([\s\S]*?)</js>|@js:([\s\S]*)',
    caseSensitive: false,
  );

  /// 網址裡的 `@js:`、`<js></js>`（Legado `analyzeJs`）：JS 前面的文字取代
  /// 目前的結果（裡面的 `@result` 換成目前的結果），JS 拿目前的結果當 `result`。
  void _analyzeJs() {
    var start = 0;
    var result = ruleUrl;
    for (final match in _jsPattern.allMatches(ruleUrl)) {
      if (match.start > start) {
        final text = ruleUrl.substring(start, match.start).trim();
        if (text.isNotEmpty) result = text.replaceAll('@result', result);
      }
      final js = match.group(1) ?? match.group(2) ?? '';
      result = evalJS(js, result)?.toString() ?? '';
      start = match.end;
    }
    if (ruleUrl.length > start) {
      final text = ruleUrl.substring(start).trim();
      if (text.isNotEmpty) result = text.replaceAll('@result', result);
    }
    ruleUrl = result;
  }

  /// `{{}}` 與 `<頁1,頁2>`（Legado `replaceKeyPageJs`）：`{{}}` 裡是 JS，
  /// `{{key}}` 得到搜尋關鍵字原文。常見的幾個直接代入，不必跑 JS。
  void _replaceKeyPageJs() {
    if (ruleUrl.contains('{{') && ruleUrl.contains('}}')) {
      final replaced = RuleAnalyzer(ruleUrl).innerRuleRange(
        '{{',
        '}}',
        fr: (js) => switch (js.trim()) {
          'key' when key != null => key!,
          'page' when page != null => '$page',
          'speakText' when speakText != null => speakText!,
          'speakSpeed' when speakSpeed != null => '$speakSpeed',
          _ => _jsText(evalJS(js)),
        },
      );
      if (replaced.isNotEmpty) ruleUrl = replaced;
    }
    final pageNumber = page;
    if (pageNumber != null) {
      ruleUrl = ruleUrl.replaceAllMapped(_pagePattern, (match) {
        final pages = match.group(1)!.split(',');
        return (pageNumber <= pages.length ? pages[pageNumber - 1] : pages.last)
            .trim();
      });
    }
  }

  static final RegExp _pagePattern = RegExp('<(.*?)>');

  /// `{{}}` 的結果寫進網址：整數的數字不帶小數點（同 Legado）。
  static String _jsText(dynamic value) => switch (value) {
    null => '',
    final double number when number % 1 == 0 && number.isFinite =>
      number.toStringAsFixed(0),
    _ => value.toString(),
  };

  /// 拆出網址與網址選項（Legado `analyzeUrl`）。
  void _analyzeUrl() {
    final optionMatch = _paramPattern.firstMatch(ruleUrl);
    final urlNoOption = optionMatch == null
        ? ruleUrl
        : ruleUrl.substring(0, optionMatch.start);
    url = _absoluteUrl(urlNoOption);
    final base = NetworkUtils.getBaseUrl(url);
    if (base != null && base != '://') _jsBaseUrl = base;
    if (optionMatch != null) {
      _applyOptions(ruleUrl.substring(optionMatch.end));
    }
    _prepareRequest();
  }

  /// 照 [url]、[method]、[body] 準備實際送出的網址與表單。
  void _prepareRequest() {
    _urlNoQuery = url;
    _encodedQuery = null;
    _encodedForm = null;
    if (method == 'GET') {
      final pos = url.indexOf('?');
      if (pos != -1) {
        _encodedQuery = _encodeParams(url.substring(pos + 1), isQuery: true);
        _urlNoQuery = url.substring(0, pos);
      }
    } else {
      final body = this.body;
      if (body != null &&
          !_isJson(body) &&
          !_isXml(body) &&
          _header('Content-Type') == null) {
        _encodedForm = _encodeParams(body, isQuery: false);
      }
    }
  }

  /// 相對網址照 [baseUrl]（沒有時用書源網址）補成完整網址。查詢參數不經
  /// `Uri` 解析，保持原文，發請求時才照字元集編碼。
  String _absoluteUrl(String raw) {
    final trimmed = raw.trim();
    final base = _givenBaseUrl.isNotEmpty ? _givenBaseUrl : source?.getKey();
    if (base == null ||
        base.isEmpty ||
        trimmed.startsWith(RegExp('(?:https?|data):', caseSensitive: false))) {
      return trimmed;
    }
    final queryStart = trimmed.indexOf('?');
    final path = queryStart < 0 ? trimmed : trimmed.substring(0, queryStart);
    final query = queryStart < 0 ? '' : trimmed.substring(queryStart);
    if (path.isEmpty) {
      final baseNoQuery = base.split('?').first;
      return '$baseNoQuery$query';
    }
    return NetworkUtils.getAbsoluteURL(base, path) + query;
  }

  /// 網址選項（Legado `UrlOption`）。
  void _applyOptions(String raw) {
    final options = _decodeLooseObject(raw.trim());
    if (options == null) {
      AppLog.w('網址選項不是 JSON，略過：$raw');
      return;
    }
    if ('${options['method'] ?? ''}'.toUpperCase() == 'POST') method = 'POST';
    final headers = switch (options['headers']) {
      final Map map => map,
      final String text when text.trim().isNotEmpty => _decodeLooseObject(text),
      _ => null,
    };
    headers?.forEach((k, v) => headerMap[k.toString()] = v.toString());
    body = switch (options['body']) {
      null => null,
      final String text => text,
      final other => jsonEncode(other),
    };
    type = _nonBlank(options['type']);
    charset = _nonBlank(options['charset']);
    final given = charset;
    if (given != null && given != 'escape' && !Charsets.supports(given)) {
      // 書源打錯字（例如「UTF–8」用了長破折號）或夜讀不認得的：編碼照
      // UTF-8，解碼照回應自己標的。
      AppLog.w('網址選項的字元集認不得，照 UTF-8：$given');
      charset = null;
    }
    retry = int.tryParse('${options['retry'] ?? ''}') ?? 0;
    useWebView = switch (options['webView']) {
      null || '' || false || 'false' => false,
      _ => true,
    };
    webJs = _nonBlank(options['webJs']);
    final js = _nonBlank(options['js']);
    if (js != null) {
      final value = evalJS(js, url);
      if (value != null) url = value.toString();
    }
    serverID = int.tryParse('${options['serverID'] ?? ''}');
    final delay = int.tryParse('${options['webViewDelayTime'] ?? ''}') ?? 0;
    webViewDelayTime = delay < 0 ? 0 : delay;
  }

  static String? _nonBlank(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.trim().isEmpty ? null : text;
  }

  static bool _isJson(String text) {
    final t = text.trim();
    return (t.startsWith('{') && t.endsWith('}')) ||
        (t.startsWith('[') && t.endsWith(']'));
  }

  static bool _isXml(String text) {
    final t = text.trim();
    return t.startsWith('<') && t.endsWith('>');
  }

  /// 查詢參數與表單照 Legado `encodeParams` 編碼：沒指定字元集時已經編碼
  /// 過的照用，`escape` 用 JS 的 escape，其他照字元集（查詢參數保留
  /// `!$%&()*+,/:;=?@[\]^`{|}`，表單照 Java URLEncoder）。
  String _encodeParams(String params, {required bool isQuery}) {
    final charset = this.charset;
    final escape = charset == 'escape';
    if (isQuery && !escape) {
      if (_alreadyEncoded(params, _queryKeep)) return params;
      return _percentEncode(params, charset);
    }
    final checkEncoded = charset == null || charset.isEmpty;
    final parts = <String>[];
    for (final pair in params.split('&')) {
      final eq = pair.indexOf('=');
      final key = eq < 0 ? pair : pair.substring(0, eq);
      final value = eq < 0 ? null : pair.substring(eq + 1);
      String encode(String text) {
        if (checkEncoded && _alreadyEncoded(text, _formKeep)) return text;
        if (escape) return EncoderUtils.escape(text);
        return Charsets.urlEncode(text, charset);
      }

      parts.add(
        value == null ? encode(key) : '${encode(key)}=${encode(value)}',
      );
    }
    return parts.join('&');
  }

  static const String _queryKeep = r"!$&()*+,-./:;=?@[\]^_`{|}~";
  static const String _formKeep = '*-._';

  /// 只有英數字、[keep] 裡的字與合法的 `%XX`（Legado `encodedQuery`、
  /// `encodedForm`）。
  static bool _alreadyEncoded(String text, String keep) {
    bool isHex(int c) =>
        (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x46) ||
        (c >= 0x61 && c <= 0x66);
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      final alnum =
          (c >= 0x30 && c <= 0x39) ||
          (c >= 0x41 && c <= 0x5A) ||
          (c >= 0x61 && c <= 0x7A);
      if (alnum || keep.contains(text[i])) continue;
      if (c == 0x25 &&
          i + 2 < text.length &&
          isHex(text.codeUnitAt(i + 1)) &&
          isHex(text.codeUnitAt(i + 2))) {
        i += 2;
        continue;
      }
      return false;
    }
    return true;
  }

  /// RFC 3986 的非保留字元與 `!$%&()*+,/:;=?@[\]^`{|}` 照原樣，其他照
  /// [charset] 的位元組寫成 `%XX`（Legado 的查詢參數編碼）。
  static String _percentEncode(String text, String? charset) {
    const keep = r"-._~!$%&()*+,/:;=?@[\]^`{|}";
    final out = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final alnum =
          (rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x41 && rune <= 0x5A) ||
          (rune >= 0x61 && rune <= 0x7A);
      if (alnum || keep.contains(char)) {
        out.write(char);
        continue;
      }
      for (final b in Charsets.encode(char, charset)) {
        out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return out.toString();
  }

  /// 規則 JS 裡 `java` 的 `url`、`ruleUrl`、`headerMap`、`type`、`serverID`
  /// （Legado 的 AnalyzeUrl 屬性）與 `isPost()` 要的方法。
  Map<String, Object?> toJs() => {
    'url': url,
    'ruleUrl': ruleUrl,
    'headerMap': headerMap,
    'type': type,
    'serverID': serverID,
    'method': method,
  };

  /// 規則 JS 改過的 `java.url`、`java.headerMap` 寫回來，之後照它送出。
  void applyJs(Object? state) {
    if (state is! Map) return;
    final headers = state['headerMap'];
    if (headers is Map) {
      headerMap
        ..clear()
        ..addAll({
          for (final MapEntry(:key, :value) in headers.entries)
            if (value != null) key.toString(): value.toString(),
        });
    }
    // 網址組到一半（網址選項的 js）就要送出時，也照目前的網址與標頭準備。
    final newUrl = state['url'];
    if (newUrl != null) url = newUrl.toString();
    _prepareRequest();
  }

  /// 實際送出的網址：GET 的查詢參數已照字元集編碼。
  String get requestUrl {
    if (method != 'GET') return _urlNoQuery;
    final query = _encodedQuery;
    return query == null ? _urlNoQuery : '$_urlNoQuery?$query';
  }

  String? _header(String name) {
    final target = name.toLowerCase();
    for (final MapEntry(:key, :value) in headerMap.entries) {
      if (key.toLowerCase() == target) return value;
    }
    return null;
  }

  /// 這個請求帶的瀏覽器標識（Legado `getUserAgent`）。
  String getUserAgent() =>
      _header('User-Agent') ??
      AppInterceptor.defaultUserAgentFor(Uri.tryParse(url) ?? Uri());

  bool isPost() => method == 'POST';

  String _resolveMaybeJsString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('@js:')) {
      return evalJS(trimmed.substring(4))?.toString() ?? '';
    }
    if (trimmed.toLowerCase().startsWith('<js>') &&
        trimmed.toLowerCase().endsWith('</js>')) {
      return evalJS(trimmed.substring(4, trimmed.length - 5))?.toString() ?? '';
    }
    return raw;
  }

  /// JSON 物件；不是標準 JSON 時照 JS 物件寫法讀（單引號、不加引號的鍵），
  /// 同 Legado 先嚴格、再寬鬆讀一次。
  Map<String, dynamic>? _decodeLooseObject(String raw) {
    Map<String, dynamic>? asMap(Object? decoded) => switch (decoded) {
      final Map<String, dynamic> map => map,
      final Map map => map.map((k, v) => MapEntry(k.toString(), v)),
      _ => null,
    };
    try {
      return asMap(jsonDecode(raw));
    } catch (_) {}
    try {
      final normalized = evalJS('JSON.stringify(($raw))')?.toString();
      if (normalized == null || normalized.isEmpty) return null;
      return asMap(jsonDecode(normalized));
    } catch (_) {
      return null;
    }
  }

  static final RegExp _dataUri = RegExp(r'^data:.*?;base64,(.*)');

  /// `data:` 網址裡的位元組；不是 `data:` 網址時是 null。
  Uint8List? _dataUriBytes() {
    if (!_urlNoQuery.startsWith('data:')) return null;
    final match = _dataUri.firstMatch(_urlNoQuery);
    if (match == null) return null;
    final data = match.group(1)!.replaceAll(RegExp(r'\s'), '');
    final padded = data.padRight((data.length + 3) ~/ 4 * 4, '=');
    return base64.decode(padded.replaceAll('-', '+').replaceAll('_', '/'));
  }

  /// 抓網頁，傳回內文（Legado `getStrResponseAwait`）。
  ///
  /// - 網址選項有 `type` 時，內文是回應位元組的十六進位。
  /// - 網址選項開了 `webView`（而且 [useWebView] 為 true）時在看不到的
  ///   瀏覽器裡載入，[jsStr] 是載入後要跑的 JS（網址選項的 `webJs` 優先），
  ///   結果是它的傳回值；[sourceRegex] 在拿到的內容裡找（Legado 是等網頁
  ///   載入的資源網址，WebView 套件拿不到資源載入的事件），找到時內文是
  ///   比對到的那段。POST 先照一般請求送出，再把回應交給瀏覽器。
  /// - 網站回 4xx、5xx 時照樣傳回（[StrResponse.isSuccessful] 為 false），
  ///   交給規則解析；`retry` 是不成功時再試幾次。
  ///
  /// 內文照 Legado 依序照回應標頭、HTML 的 meta、自動偵測解碼（網址選項
  /// 的 `charset` 只用在送出的參數）；回應是 XML 卻沒有宣告時補上
  /// `<?xml version="1.0"?>`。
  Future<StrResponse> getStrResponse({
    CancelToken? cancelToken,
    String? jsStr,
    String? sourceRegex,
    bool useWebView = true,
  }) async {
    // 規則 JS 裡的請求（java.ajax 這類）沒有傳，跟著所在的書源工作取消。
    cancelToken ??= currentSourceCancelToken;
    if (type != null) {
      final bytes = await getByteArray(cancelToken: cancelToken);
      return StrResponse(
        url: url,
        body: _hex(bytes),
        headers: const {},
        raw: Response(
          requestOptions: RequestOptions(path: requestUrl),
          statusCode: 200,
        ),
      );
    }
    final limiter = ConcurrentRateLimiter(source);
    return limiter.withLimit(() async {
      await _mergeStoredCookie();
      if (this.useWebView && useWebView) {
        return _webViewResponse(
          cancelToken,
          javaScript: webJs ?? jsStr,
          sourceRegex: sourceRegex,
        );
      }
      final (response, _) = await _fetch(cancelToken);
      final contentType = response.raw.headers.value('content-type') ?? '';
      if (_xmlContentType.hasMatch(contentType) &&
          !response.body.trimLeft().toLowerCase().startsWith('<?xml')) {
        return StrResponse(
          url: response.url,
          body: '<?xml version="1.0"?>${response.body}',
          headers: response.headers,
          raw: response.raw,
        );
      }
      return response;
    }, cancelToken: cancelToken);
  }

  static final RegExp _xmlContentType = RegExp(
    r'(application|text)/\w*\+?xml',
    caseSensitive: false,
  );

  /// 抓這個請求，傳回解碼的回應與原始位元組（Legado `getResponseAwait`）：
  /// 不管網址選項的 `type` 與 `webView`。
  Future<(StrResponse, Uint8List)> getResponse({
    CancelToken? cancelToken,
  }) async {
    cancelToken ??= currentSourceCancelToken;
    return ConcurrentRateLimiter(source).withLimit(() async {
      await _mergeStoredCookie();
      return _fetch(cancelToken);
    }, cancelToken: cancelToken);
  }

  Future<(StrResponse, Uint8List)> _fetch(CancelToken? cancelToken) async {
    final response = await _send(cancelToken);
    final bytes = Uint8List.fromList(response.data ?? const []);
    return (
      StrResponse(
        url: response.finalUri.toString(),
        body: _decodeResponseBody(bytes, response),
        headers: response.headers.map,
        raw: response,
      ),
      bytes,
    );
  }

  Future<StrResponse> _webViewResponse(
    CancelToken? cancelToken, {
    String? javaScript,
    String? sourceRegex,
  }) async {
    var pageUrl = requestUrl;
    String? html;
    if (method == 'POST') {
      final response = await _send(cancelToken);
      pageUrl = response.finalUri.toString();
      html = _decodeResponseBody(
        Uint8List.fromList(response.data ?? const []),
        response,
      );
    }
    // 瀏覽器載入沒辦法中途停下；取消時不再等它，結果丟掉。
    final result = await untilCancelled(
      BackstageWebView(
        url: pageUrl,
        html: html,
        javaScript: javaScript,
        sourceRegex: sourceRegex,
        headerMap: Map.of(headerMap),
        delayTime: webViewDelayTime,
      ).getStrResponse(),
      cancelToken,
    );
    final body = result['body']?.toString() ?? '';
    final finalUrl = result['url']?.toString() ?? pageUrl;
    return StrResponse(
      url: finalUrl,
      body: body,
      headers: const {},
      raw: Response(
        requestOptions: RequestOptions(path: finalUrl),
        data: body,
        statusCode: 200,
      ),
    );
  }

  /// 抓回應的位元組（Legado `getByteArrayAwait`）；`data:` 網址直接解出來。
  Future<Uint8List> getByteArray({CancelToken? cancelToken}) async {
    final dataBytes = _dataUriBytes();
    if (dataBytes != null) return dataBytes;
    cancelToken ??= currentSourceCancelToken;
    final limiter = ConcurrentRateLimiter(source);
    return limiter.withLimit(() async {
      await _mergeStoredCookie();
      final response = await _send(cancelToken);
      return Uint8List.fromList(response.data ?? const []);
    }, cancelToken: cancelToken);
  }

  /// 站點存的 Cookie 併進請求，規則或網址選項自己給的同名 Cookie 優先
  /// （Legado `setCookie`）。
  Future<void> _mergeStoredCookie() async {
    final stored = await CookieStore().getCookie(url);
    if (stored.isEmpty) return;
    final store = CookieStore();
    final given = _header('Cookie');
    headerMap.removeWhere((k, _) => k.toLowerCase() == 'cookie');
    headerMap['Cookie'] = given == null || given.isEmpty
        ? stored
        : store.mapToCookie(
            store.cookieToMap(stored)..addAll(store.cookieToMap(given)),
          );
  }

  /// 送出請求，傳回回應的位元組。網路斷線這類暫時的失敗再試兩次；網站
  /// 回 4xx、5xx 照樣傳回，不成功時照網址選項 `retry` 再送（同 Legado）。
  Future<Response<List<int>>> _send(CancelToken? cancelToken) async {
    late Response<List<int>> response;
    for (var attempt = 0; attempt <= retry; attempt++) {
      response = await _sendOnce(cancelToken);
      final code = response.statusCode ?? 200;
      if (code >= 200 && code < 300) break;
    }
    return response;
  }

  Future<Response<List<int>>> _sendOnce(CancelToken? cancelToken) async {
    final options = Options(
      method: method,
      headers: requestHeaders,
      responseType: ResponseType.bytes,
    );
    const maxAttempts = 3;
    for (var attempt = 1; ; attempt++) {
      try {
        final client = HttpClient().client;
        return method == 'POST'
            ? await client.post<List<int>>(
                requestUrl,
                data: requestBody,
                options: options,
                cancelToken: cancelToken,
              )
            : await client.get<List<int>>(
                requestUrl,
                options: options,
                cancelToken: cancelToken,
              );
      } on DioException catch (e) {
        final response = e.response;
        // 網站回錯誤碼、攔截器沒有另外說明原因（Cloudflare、封鎖網路）時，
        // 照 Legado 交給規則。
        if (e.type == DioExceptionType.badResponse &&
            response != null &&
            e.error is! AppException) {
          return Response<List<int>>(
            data: switch (response.data) {
              final List<int> bytes => bytes,
              final String text => utf8.encode(text),
              _ => const [],
            },
            requestOptions: response.requestOptions,
            statusCode: response.statusCode,
            statusMessage: response.statusMessage,
            headers: response.headers,
            isRedirect: response.isRedirect,
            redirects: response.redirects,
            extra: response.extra,
          );
        }
        if (attempt >= maxAttempts || !_isRetryable(e)) rethrow;
        AppLog.d('AnalyzeUrl: 請求失敗 (${e.type}) → 第 $attempt 次重試: $url');
        // 退避期間取消就不再試。
        await Future.any<Object?>([
          Future<void>.delayed(Duration(milliseconds: 300 * attempt * attempt)),
          ?cancelToken?.whenCancel,
        ]);
        if (cancelToken?.cancelError case final cancelled?) throw cancelled;
      }
    }
  }

  /// POST 實際送出的內文（Legado）：有表單（或沒有內文）時送編碼過的表單；
  /// 有指定 Content-Type 時照原文送；其他當 JSON 送。
  String get requestBody => _encodedForm ?? body ?? '';

  /// 實際送出的標頭：POST 沒指定 Content-Type 時照內文補上（表單或 JSON）。
  Map<String, String> get requestHeaders {
    final headers = Map<String, String>.from(headerMap);
    if (method != 'POST' || _header('Content-Type') != null) return headers;
    final form = _encodedForm != null || (body?.trim().isEmpty ?? true);
    headers['Content-Type'] = form
        ? 'application/x-www-form-urlencoded'
        : 'application/json; charset=UTF-8';
    return headers;
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

  static String _hex(List<int> bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      out.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
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

    // 1. HTTP Content-Type 標頭中的 charset。網址選項的 charset 只管送出的
    //    參數，同 Legado（newCallStrResponse 解碼時不帶它）。
    final contentType = response.headers.value('content-type');
    if (contentType != null) {
      final ctCharset = _extractCharsetFromContentType(contentType);
      if (ctCharset != null) {
        return EncodingDetect.decodeWithCharset(cleanBytes, ctCharset);
      }
    }

    // 2. HTML meta 標籤 + 自動偵測 (EncodingDetect.getHtmlEncode)
    final detected = EncodingDetect.getHtmlEncode(cleanBytes);
    return EncodingDetect.decodeWithCharset(cleanBytes, detected);
  }

  /// 從 Content-Type 標頭提取 charset
  String? _extractCharsetFromContentType(String contentType) {
    final match = RegExp(
      r'''charset\s*=\s*["']?([^;\s"']+)''',
      caseSensitive: false,
    ).firstMatch(contentType);
    return match?.group(1);
  }
}

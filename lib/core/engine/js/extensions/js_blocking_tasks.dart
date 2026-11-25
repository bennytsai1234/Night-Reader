import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/network/cancellation.dart';
import 'package:night_reader/core/network/interceptors/app_interceptor.dart';
import 'package:night_reader/core/network/interceptors/lenient_cookie_manager.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/network/backstage_webview.dart';
import 'package:night_reader/core/utils/cache_manager.dart';
import 'package:night_reader/core/utils/encoding_detect.dart';
import 'package:night_reader/core/network/cookie_store.dart';
import 'package:night_reader/core/network/http_client.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/core/source/source_interaction.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:night_reader/core/utils/network_utils.dart';

import '../js_encode_utils.dart';
import '../js_response.dart';

/// 規則 JS 要等的呼叫交給網路 isolate 做的事（[BlockingCall]，ADR 0034）。
/// 工作連同捕捉的變數會送到網路 isolate，所以都在這裡的頂層函式建立，只
/// 捕捉網址、書源與字串這類資料（`CODING_STANDARDS.md` 背景執行）。網路
/// isolate 不跑規則 JS：網址裡的 JS 在書源 isolate 組 [AnalyzeUrl] 時就跑完了。
typedef BlockingTask = Future<Object?> Function();

/// 請登入頁的使用者做 [request]（[SourceInteraction]）：網路 isolate 轉給
/// 主 isolate，等使用者做完。
BlockingTask askUser(SourceInteractionRequest request) =>
    () => SourceInteraction.request(request);

/// 快取裡的 [key]（資料庫與檔案）。
BlockingTask cacheRead(String key) =>
    () => CacheManager().get(key);

/// [url] 的站點 Cookie（資料庫）。
BlockingTask cookieRead(String url) => () async {
  final stored = await CookieStore().getCookie(url);
  final uri = NetworkUtils.cookieJarUri(url);
  if (uri == null) return stored;
  // 同 Legado：它的 CookieStore 就是 Cookie 罐，網站寫的也讀得到。夜讀網站
  // 寫的在 Cookie 罐，規則寫的在 CookieStore，兩份合起來；同名的以規則寫的
  // 為準。
  final store = CookieStore();
  final merged = store.cookieToMap(stored);
  for (final cookie in await NetworkService().cookieJar.loadForRequest(uri)) {
    merged.putIfAbsent(cookie.name, () => cookie.value);
  }
  return store.mapToCookie(merged);
};

/// 清掉 Cookie 罐裡 [url] 的 Cookie（網站寫的）：規則 JS 等它清完，接著送的
/// 請求才不會帶著舊的（同 Legado 的 removeCookie 當下就清）。
BlockingTask cookieJarDelete(String url) => () async {
  final uri = NetworkUtils.cookieJarUri(url);
  if (uri != null) await NetworkService().cookieJar.delete(uri, true);
  return null;
};

/// 回應的內文。
BlockingTask responseBody(AnalyzeUrl url) =>
    () async => (await url.getStrResponse()).body;

/// 同時抓，照 [urls] 的順序傳回每個回應（[responseToJs]）：`java.ajaxAll`
/// 和 Legado 一樣給回應物件，規則用 `.body()`、`.code()` 讀。任一個失敗就
/// 整批丟出，和 Legado 一樣。
BlockingTask responses(List<AnalyzeUrl> urls) =>
    () async => [
      for (final (index, response) in (await Future.wait(
        urls.map((u) => u.getStrResponse()),
      )).indexed)
        responseToJs(response, requestUrl: urls[index].requestUrl),
    ];

/// 網址或登入檢查的規則 JS 用 `java.getStrResponse(js, sourceRegex,
/// useWebView)` 抓這個請求（[AnalyzeUrl.getStrResponse]）。
BlockingTask requestResponse(
  AnalyzeUrl url, {
  String? jsStr,
  String? sourceRegex,
  bool useWebView = true,
}) =>
    () async => responseToJs(
      await url.getStrResponse(
        jsStr: jsStr,
        sourceRegex: sourceRegex,
        useWebView: useWebView,
      ),
      requestUrl: url.requestUrl,
    );

/// `java.getResponse()`：原始回應，多帶原始位元組（[AnalyzeUrl.getResponse]）。
BlockingTask rawRequestResponse(AnalyzeUrl url) => () async {
  final (response, bytes) = await url.getResponse();
  return {
    ...responseToJs(response, requestUrl: url.requestUrl),
    'bytes': List<int>.of(bytes),
  };
};

/// `java.connect` 的回應：內文、網址、狀態與標頭。失敗時傳回 500 與錯誤
/// 訊息，不丟出，和原本一樣。
BlockingTask connectResponse(AnalyzeUrl url) => () async {
  try {
    return responseToJs(await url.getStrResponse(), requestUrl: url.requestUrl);
  } catch (e) {
    AppLog.e('java.connect failed: $e');
    return failedResponse(url.requestUrl, e);
  }
};

/// `java.get`、`java.post`、`java.head`：照給的方法與標頭發，不自動跟著
/// 跳轉。失敗時傳回 500 與錯誤訊息。
///
/// [cookieJar]：書源開了 Cookie 罐時，送出前併進這個網站存著的 Cookie
/// （`cookie.setCookie`、登入存的），同名的以存著的為準（同 Legado：
/// JsExtensions.get 加上 CookieJar 標頭，CookieManager.loadRequest 併進去）；
/// 也只有這時網站回的 Cookie 才存下來（CookieManager.saveResponse）。
BlockingTask rawResponse({
  required String method,
  required String url,
  Object? data,
  required Map<String, dynamic> headers,
  bool cookieJar = false,
}) => () async {
  try {
    if (cookieJar) await _mergeStoredCookies(url, headers);
    final client = HttpClient().client;
    final response = await client.fetch<List<int>>(
      RequestOptions(
        method: method,
        path: url,
        baseUrl: '',
        data: data,
        headers: headers,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (_) => true,
        // `fetch` 不併網路的預設設定，逾時要自己帶，網站接上不回時才會停。
        connectTimeout: client.options.connectTimeout,
        sendTimeout: client.options.sendTimeout,
        receiveTimeout: client.options.receiveTimeout,
        // 收原始位元組：`bodyAsBytes()` 要網站給的原文（GBK、加密的正文），
        // 文字另外照回應標頭的字元集解（同 Jsoup `Response.body()`）。
        responseType: ResponseType.bytes,
        extra: <String, dynamic>{
          AppInterceptor.disableManualRedirectHandlingKey: true,
          ...LenientCookieManager.sourceExtra(cookieJar),
        },
        cancelToken: currentSourceCancelToken,
      ),
    );
    final bytes = Uint8List.fromList(response.data ?? const <int>[]);
    return {
      'body': _decodeBody(bytes, response.headers.value('content-type')),
      'bodyBase64': base64Encode(bytes),
      'url': response.realUri.toString(),
      'requestUrl': url,
      'code': response.statusCode,
      'message': response.statusMessage ?? '',
      'headers': response.headers.map,
      'redirects': _redirectsOf(response),
    };
  } catch (e) {
    AppLog.e('java.${method.toLowerCase()} failed: $e');
    return failedResponse(url, e);
  }
};

/// Jsoup `Response.body()`：照回應標頭的字元集解，沒寫是 UTF-8。
String _decodeBody(Uint8List bytes, String? contentType) {
  final charset = contentType == null
      ? null
      : RegExp(
          r'''charset\s*=\s*["']?([^;\s"']+)''',
          caseSensitive: false,
        ).firstMatch(contentType)?.group(1);
  if (charset == null) return utf8.decode(bytes, allowMalformed: true);
  return EncodingDetect.decodeWithCharset(bytes, charset);
}

Future<void> _mergeStoredCookies(
  String url,
  Map<String, dynamic> headers,
) async {
  final store = CookieStore();
  final stored = await store.getCookie(url);
  if (stored.isEmpty) return;
  final key = headers.keys
      .where((k) => k.toLowerCase() == 'cookie')
      .firstOrNull;
  final given = key == null ? '' : '${headers.remove(key)}';
  headers['Cookie'] = store.mapToCookie(
    store.cookieToMap(given)..addAll(store.cookieToMap(stored)),
  );
}

/// 請求失敗時給規則 JS 的回應：狀態碼 500，內文是錯誤訊息。
Map<String, Object?> failedResponse(String url, Object error) => {
  'body': error.toString(),
  'url': url,
  'requestUrl': url,
  'code': 500,
  'message': error.toString(),
  'headers': <String, Object?>{},
  'redirects': const <String>[],
};

List<String> _redirectsOf(Response<dynamic> response) {
  final nativeRedirects = [
    for (final record in response.redirects) record.location.toString(),
  ];
  if (nativeRedirects.isNotEmpty) return nativeRedirects;
  return [
    for (final item
        in (response.extra['_manualRedirectChain'] as List?) ?? const [])
      item.toString(),
  ];
}

/// 回應的位元組。
BlockingTask responseBytes(AnalyzeUrl url) =>
    () => url.getByteArray();

/// `java.cacheFile`：快取裡有就用，沒有就照書源的請求（標頭、登入、網址
/// 選項，同 Legado `downloadFile` 經書源的 AnalyzeUrl）抓回來存進快取。存的
/// 時候不等它寫完：停住的書源 isolate 手上若有交易，寫入要等它，它又在等
/// 這裡。[url] 是快取的鍵（規則給的網址原文）。
BlockingTask cachedText(String url, AnalyzeUrl request, int saveTimeSeconds) =>
    () async {
      final key = JsEncodeUtils.md5Encode16(url);
      final cached = await CacheManager().get(key);
      if (cached != null) return cached;
      try {
        final content = utf8.decode(
          await request.getByteArray(),
          allowMalformed: true,
        );
        if (content.isNotEmpty) {
          unawaited(
            CacheManager().put(key, content, saveTimeSeconds: saveTimeSeconds),
          );
        }
        return content;
      } catch (_) {
        return '';
      }
    };

/// 書源 jsLib 的網址片段（Legado `SharedJsScope`）：抓過的存在快取，不會
/// 過期，之後網站慢或離線照樣用得到；快取沒有又抓不到時丟出錯誤。存的時候
/// 不等它寫完，理由同 [cachedText]。
BlockingTask jsLibText(String url) => () async {
  final key = 'jsLib_${JsEncodeUtils.md5Encode(url)}';
  final cached = await CacheManager().get(key);
  if (cached != null) return cached;
  final response = await HttpClient().client.get<List<int>>(
    url,
    options: Options(
      responseType: ResponseType.bytes,
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ),
    cancelToken: currentSourceCancelToken,
  );
  final content = utf8.decode(
    response.data ?? const <int>[],
    allowMalformed: true,
  );
  unawaited(CacheManager().put(key, content));
  return content;
};

/// 看不到的瀏覽器載入網頁（`java.webView` 這一類），傳回內文。
BlockingTask backstagePage({
  String? html,
  String? url,
  String? javaScript,
  String? sourceRegex,
  String? overrideUrlRegex,
  String? tag,
  Map<String, String>? headerMap,
}) => () async {
  final webView = BackstageWebView(
    html: html,
    url: url,
    javaScript: javaScript,
    headerMap: headerMap,
    sourceRegex: sourceRegex,
    overrideUrlRegex: overrideUrlRegex,
    tag: tag,
  );
  final response = await untilCancelled(
    webView.getStrResponse(),
    currentSourceCancelToken,
  );
  return response['body']?.toString() ?? '';
};

/// App 的快取資料夾（規則 JS 的檔案函式都相對它，同 Legado）。
BlockingTask cacheDirPath() =>
    () async => (await AppStoragePaths.temporaryDir()).path;

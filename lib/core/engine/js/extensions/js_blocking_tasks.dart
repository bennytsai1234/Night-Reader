import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/network/cancellation.dart';
import 'package:night_reader/core/network/interceptors/app_interceptor.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/backstage_webview.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/encoding_detect.dart';
import 'package:night_reader/core/services/http_client.dart';
import 'package:night_reader/core/services/source_interaction.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';

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
BlockingTask cookieRead(String url) =>
    () => CookieStore().getCookie(url);

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
BlockingTask rawResponse({
  required String method,
  required String url,
  Object? data,
  required Map<String, dynamic> headers,
}) => () async {
  try {
    final response = await HttpClient().client.fetch<dynamic>(
      RequestOptions(
        method: method,
        path: url,
        baseUrl: '',
        data: data,
        headers: headers,
        followRedirects: false,
        maxRedirects: 0,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
        extra: <String, dynamic>{
          AppInterceptor.disableManualRedirectHandlingKey: true,
        },
        cancelToken: currentSourceCancelToken,
      ),
    );
    return {
      'body': response.data?.toString() ?? '',
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

/// `Jsoup.connect` 用的連線：Legado 的 Jsoup 用 Java 自己的連線，不經 App
/// 的連線設定，所以這裡也不掛攔截器——不帶 App 的 Cookie 與標識，回應的
/// Cookie 也不存進 App。
Dio? _jsoupDio;

/// `org.jsoup.Jsoup.connect(…).execute()`：照書源給的設定發一次（Jsoup 最多
/// 跟著跳轉 20 次）。內文照回應標頭的字元集解碼，沒寫時用 UTF-8；`parse()`
/// 沒寫字元集時看網頁的 `<meta>`（[EncodingDetect.getHtmlEncode]），和
/// Jsoup 一樣。內文超過 [maxBodySize]（0 是不限）的部分截掉。
BlockingTask jsoupResponse({
  required String method,
  required String url,
  required Map<String, String> headers,
  Uint8List? body,
  required int timeoutMs,
  required int maxBodySize,
  required bool followRedirects,
}) => () async {
  final timeout = timeoutMs > 0 ? Duration(milliseconds: timeoutMs) : null;
  final response = await (_jsoupDio ??= Dio()).fetch<List<int>>(
    RequestOptions(
      method: method,
      path: url,
      data: body,
      headers: headers,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: body == null ? null : timeout,
      followRedirects: followRedirects,
      maxRedirects: 20,
      validateStatus: (_) => true,
      responseType: ResponseType.bytes,
      cancelToken: currentSourceCancelToken,
    ),
  );
  var bytes = Uint8List.fromList(response.data ?? const <int>[]);
  if (maxBodySize > 0 && bytes.length > maxBodySize) {
    bytes = bytes.sublist(0, maxBodySize);
  }
  final contentType = response.headers.value('content-type');
  final charset = RegExp(
    r'charset=\s*"?([\w.:-]+)',
    caseSensitive: false,
  ).firstMatch(contentType ?? '')?.group(1);
  // 從網頁認出的字元集照 Java 的 Charset.name() 寫成大寫（GBK、UTF-8）。
  final htmlCharset =
      charset ?? EncodingDetect.getHtmlEncode(bytes).toUpperCase();
  final text = EncodingDetect.decodeWithCharset(bytes, charset ?? 'UTF-8');
  return {
    'code': response.statusCode ?? 0,
    'message': response.statusMessage ?? '',
    'url': response.realUri.toString(),
    'headers': response.headers.map,
    'contentType': contentType,
    'charset': charset,
    'body': text,
    'htmlCharset': htmlCharset,
    'htmlBody': htmlCharset.toUpperCase() == (charset ?? 'UTF-8').toUpperCase()
        ? null
        : EncodingDetect.decodeWithCharset(bytes, htmlCharset),
    'bytes': base64Encode(bytes),
  };
};

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

/// [url] 的位元組，不經書源設定（字型這類資源）。
BlockingTask plainBytes(String url) => () async {
  final response = await HttpClient().client.get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes),
    cancelToken: currentSourceCancelToken,
  );
  return Uint8List.fromList(response.data ?? const []);
};

/// `java.cacheFile`：快取裡有就用，沒有就抓回來存進快取。存的時候不等它
/// 寫完：停住的書源 isolate 手上若有交易，寫入要等它，它又在等這裡。
BlockingTask cachedText(String url, int saveTimeSeconds) => () async {
  final key = JsEncodeUtils.md5Encode16(url);
  final cached = await CacheManager().get(key);
  if (cached != null) return cached;
  try {
    final response = await HttpClient().client.get<String>(
      url,
      cancelToken: currentSourceCancelToken,
    );
    final content = response.data.toString();
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

/// 看不到的瀏覽器載入網頁（`java.webView` 這一類），傳回內文。
BlockingTask backstagePage({
  String? html,
  String? url,
  String? javaScript,
  String? sourceRegex,
  String? overrideUrlRegex,
}) => () async {
  final webView = BackstageWebView(
    html: html,
    url: url,
    javaScript: javaScript,
    sourceRegex: sourceRegex,
    overrideUrlRegex: overrideUrlRegex,
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

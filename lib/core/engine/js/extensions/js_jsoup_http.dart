import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/network/interceptors/lenient_cookie_manager.dart';
import 'package:night_reader/core/services/encoding_detect.dart';

import '../encode/charsets.dart';
import '../jsoup/jsoup_bridge.dart';
import 'js_blocking_tasks.dart';

/// `Jsoup.connect` 用的連線：Legado 的 Jsoup 用 Java 自己的連線，不經 App
/// 的連線設定，所以這裡也不掛攔截器——不帶 App 的 Cookie 與標識，回應的
/// Cookie 也不存進 App，只存進這個 Jsoup 連線自己的 Cookie（[jsoupExecute]）。
Dio? _jsoupDio;

/// Jsoup 1.16.2 `HttpConnection.MAX_REDIRECTS`。
const int _maxRedirects = 20;

/// `org.jsoup.Jsoup.connect(…).execute()`：照 Jsoup 1.16.2 的
/// `HttpConnection.Response.execute` 發請求。[request] 是 JS 端的連線設定
/// （`js_jsoup_connection.dart` 的 `execute`）：
///
/// - 表單：沒有內文的方法、或書源自己給了 `requestBody` 時，照 UTF-8 接在
///   網址的查詢參數後面（片段之前）；否則照 `postDataCharset` 寫進內文，
///   沒有 Content-Type 時補上表單的類型。
/// - Cookie：書源給的，加上這個連線（與 `newRequest()` 出來的連線）先前
///   收到、符合網址的。每次回應的 Set-Cookie 都存起來，跳轉的下一站就帶上；
///   回應的 `cookies()` 含跳轉途中收到的。
/// - 跳轉：回應有 Location 就跟（最多 20 次）；307 以外改成不帶內文的
///   GET。`followRedirects(false)` 時停在那個回應。
/// - 內文：一邊讀一邊數，讀滿 `maxBodySize`（0 是不限）就停；逾時從這一站
///   送出算起。會被 JS 端當成錯誤丟出的回應（狀態碼、類型不對）不讀內文。
///
/// 傳回回應，連同 Jsoup 在執行時改掉的請求設定（網址、方法、表單、內文、
/// 標頭），與這個連線的 Cookie。
BlockingTask jsoupExecute(Map<String, Object?> request) => () async {
  var url = '${request['url']}';
  var method = '${request['method']}';
  var data = [
    for (final pair in (request['data'] as List?) ?? const [])
      ['${(pair as List)[0]}', '${pair[1]}'],
  ];
  var body = request['body'] as String?;
  final headers = [
    for (final header in (request['headers'] as List?) ?? const [])
      ['${(header as List)[0]}', '${header[1]}'],
  ];
  final charset = '${request['charset'] ?? 'UTF-8'}';
  final cookies = (request['cookies'] as Map?) ?? const {};
  final timeoutMs = (request['timeout'] as num?)?.toInt() ?? 30000;
  final maxBodySize = (request['maxBodySize'] as num?)?.toInt() ?? 0;
  final followRedirects = request['followRedirects'] != false;
  final timeout = timeoutMs > 0 ? Duration(milliseconds: timeoutMs) : null;

  // 這個連線收過的 Set-Cookie（網址、原文），照順序重放進一個只在這次
  // 請求用的 Cookie 罐，網域、路徑、到期都照 Cookie 的規則。
  final store = [
    for (final entry in (request['cookieStore'] as List?) ?? const [])
      ['${(entry as List)[0]}', '${entry[1]}'],
  ];
  final jar = DefaultCookieJar();
  for (final entry in store) {
    await _save(jar, entry[0], entry[1]);
  }

  bool hasHeader(String name) =>
      headers.any((h) => h[0].toLowerCase() == name.toLowerCase());
  var dataCleared = false;
  var responseCookies = <String, String>{};
  var redirects = 0;
  String? previousUrl;
  while (true) {
    final uri = Uri.parse(url);
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw JsoupException('Only http & https protocols supported');
    }
    final hasBody = _methodHasBody(method);
    if (data.isNotEmpty && (!hasBody || body != null)) {
      url = _withQuery(url, data);
      data = [];
      dataCleared = true;
    } else if (hasBody && !hasHeader('Content-Type')) {
      headers.add([
        'Content-Type',
        'application/x-www-form-urlencoded; charset=$charset',
      ]);
    }
    final requestUri = Uri.parse(url);
    final wire = <String, String>{};
    for (final header in headers) {
      final existing = wire.keys
          .where((k) => k.toLowerCase() == header[0].toLowerCase())
          .firstOrNull;
      wire[existing ?? header[0]] = existing == null
          ? header[1]
          : '${wire[existing]}, ${header[1]}';
    }
    final cookieSet = <String>{
      for (final e in cookies.entries) '${e.key}=${e.value}',
      for (final c in await jar.loadForRequest(requestUri))
        '${c.name}=${c.value}',
    };
    if (cookieSet.isNotEmpty) {
      // Jsoup 另送一個 Cookie 標頭；這裡併進書源自己給的那個。
      final key = wire.keys
          .where((k) => k.toLowerCase() == 'cookie')
          .firstOrNull;
      final cookie = cookieSet.join('; ');
      wire[key ?? 'Cookie'] = key == null ? cookie : '${wire[key]}; $cookie';
    }
    final payload = hasBody
        ? Charsets.encode(
            body ??
                [
                  for (final pair in data)
                    '${Charsets.urlEncode(pair[0], charset)}='
                        '${Charsets.urlEncode(pair[1], charset)}',
                ].join('&'),
            charset,
          )
        : null;

    final started = DateTime.now();
    final response = await (_jsoupDio ??= Dio()).fetch<ResponseBody>(
      RequestOptions(
        method: method,
        path: url,
        data: payload,
        headers: wire,
        connectTimeout: timeout,
        receiveTimeout: timeout,
        sendTimeout: payload == null ? null : timeout,
        followRedirects: false,
        validateStatus: (_) => true,
        responseType: ResponseType.stream,
        cancelToken: currentSourceCancelToken,
      ),
    );
    final status = response.statusCode ?? 0;
    final responseHeaders = response.headers.map;

    // 這一站的 Cookie 在前，跳轉前收到的同名不蓋掉（Jsoup 的 Response）。
    final setCookies = response.headers['set-cookie'] ?? const [];
    final current = <String, String>{};
    for (final value in setCookies) {
      final eq = value.indexOf('=');
      final name = (eq < 0 ? value : value.substring(0, eq)).trim();
      final rest = eq < 0 ? '' : value.substring(eq + 1);
      final semi = rest.indexOf(';');
      if (name.isNotEmpty) {
        current.putIfAbsent(
          name,
          () => (semi < 0 ? rest : rest.substring(0, semi)).trim(),
        );
      }
      store.add([url, value]);
      await _save(jar, url, value);
    }
    for (final entry in responseCookies.entries) {
      current.putIfAbsent(entry.key, () => entry.value);
    }
    responseCookies = current;
    if (previousUrl != null) {
      redirects++;
      if (redirects >= _maxRedirects) {
        await _discard(response);
        throw JsoupException(
          'Too many redirects occurred trying to load URL $previousUrl',
        );
      }
    }

    final location = response.headers.value('location');
    if (location != null && followRedirects) {
      await _discard(response);
      if (status != 307) {
        method = 'GET';
        if (data.isNotEmpty) dataCleared = true;
        data = [];
        body = null;
        headers.removeWhere((h) => h[0].toLowerCase() == 'content-type');
      }
      var target = location;
      // Jsoup 修正寫壞的 Location: http:/temp/…
      if (target.startsWith('http:/') &&
          target.length > 6 &&
          target[6] != '/') {
        target = target.substring(6);
      }
      previousUrl = url;
      url = Uri.parse(url).resolve(target).toString();
      continue;
    }

    final contentType = response.headers.value('content-type');
    final rejected =
        ((status < 200 || status >= 400) &&
            request['ignoreHttpErrors'] != true) ||
        (contentType != null &&
            request['ignoreContentType'] != true &&
            !isJsoupTextType(contentType));
    final bytes = rejected || method == 'HEAD'
        ? Uint8List(0)
        : await _readBody(response, maxBodySize, timeout, started);
    final headerCharset = RegExp(
      r'''charset=\s*["']?([^\s,;"']+)''',
      caseSensitive: false,
    ).firstMatch(contentType ?? '')?.group(1);
    final bom = _bomCharset(bytes);
    final htmlCharset = _javaCharsetName(
      bom ?? headerCharset ?? _declaredCharset(bytes) ?? 'UTF-8',
    );
    final text = _decode(bytes, headerCharset ?? 'UTF-8');
    final html = _decode(
      bom == null ? bytes : bytes.sublist(_bomLength(bytes)),
      htmlCharset,
    );
    return {
      'code': status,
      'message': response.statusMessage ?? '',
      'url': url,
      'method': method,
      'headers': responseHeaders,
      'contentType': contentType,
      'charset': headerCharset,
      'body': text,
      'htmlCharset': htmlCharset,
      'htmlBody': html == text ? null : html,
      'bytes': base64Encode(bytes),
      'cookies': [
        for (final e in responseCookies.entries) [e.key, e.value],
      ],
      'cookieStore': store,
      'request': {
        'url': url,
        'method': method,
        'dataCleared': dataCleared,
        'body': body,
        'headers': headers,
      },
    };
  }
};

/// Jsoup 讀得了的回應類型：`text/*`、`application/xml`、`application/*+xml`
/// （`HttpConnection.xmlContentTypeRxp`）。
bool isJsoupTextType(String contentType) =>
    contentType.startsWith('text/') ||
    RegExp(r'^(application|text)/\w*\+?xml').hasMatch(contentType);

bool _methodHasBody(String method) =>
    const {'POST', 'PUT', 'DELETE', 'PATCH'}.contains(method);

/// Jsoup `UrlBuilder.appendKeyVal`：表單照 UTF-8 接在查詢參數後面，片段
/// 留在最後。
String _withQuery(String url, List<List<String>> data) {
  final hash = url.indexOf('#');
  final base = hash < 0 ? url : url.substring(0, hash);
  final query = [
    for (final pair in data)
      '${Charsets.urlEncode(pair[0], 'UTF-8')}='
          '${Charsets.urlEncode(pair[1], 'UTF-8')}',
  ].join('&');
  return '$base${base.contains('?') ? '&' : '?'}$query'
      '${hash < 0 ? '' : url.substring(hash)}';
}

Future<void> _save(CookieJar jar, String url, String setCookie) async {
  final cookie = parseSetCookieValueLenient(
    setCookie,
    ignoreInvalidCookies: true,
  );
  final uri = Uri.tryParse(url);
  if (cookie != null && uri != null) {
    await jar.saveFromResponse(uri, [cookie]);
  }
}

/// 不讀內文就關掉這個回應。
Future<void> _discard(Response<ResponseBody> response) async {
  await response.data?.stream.listen(null).cancel();
}

/// 讀內文：讀滿 [maxBodySize]（0 是不限）就關掉連線；從這一站送出算起超過
/// [timeout] 就失敗（Jsoup 的 `ConstrainableInputStream`）。
Future<Uint8List> _readBody(
  Response<ResponseBody> response,
  int maxBodySize,
  Duration? timeout,
  DateTime started,
) async {
  final stream = response.data?.stream;
  if (stream == null) return Uint8List(0);
  final builder = BytesBuilder(copy: false);
  final done = Completer<void>();
  late final StreamSubscription<Uint8List> subscription;
  subscription = stream.listen(
    (chunk) {
      if (maxBodySize > 0 && builder.length + chunk.length >= maxBodySize) {
        builder.add(chunk.sublist(0, maxBodySize - builder.length));
        unawaited(subscription.cancel());
        if (!done.isCompleted) done.complete();
        return;
      }
      builder.add(chunk);
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
    onError: (Object error, StackTrace stack) {
      if (!done.isCompleted) done.completeError(error, stack);
    },
    cancelOnError: true,
  );
  if (timeout == null) {
    await done.future;
  } else {
    final left = timeout - DateTime.now().difference(started);
    try {
      await done.future.timeout(left.isNegative ? Duration.zero : left);
    } on TimeoutException {
      await subscription.cancel();
      throw JsoupException('Read timeout');
    }
  }
  return builder.takeBytes();
}

String? _bomCharset(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return 'UTF-8';
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return 'UTF-16BE';
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return 'UTF-16LE';
  }
  return null;
}

int _bomLength(Uint8List bytes) => bytes.isNotEmpty && bytes[0] == 0xEF ? 3 : 2;

/// Jsoup `DataUtil.parseInputStream`：網頁前 5KB 裡第一個寫了字元集的
/// `<meta>`，沒有時看 `<?xml encoding=…?>`。
String? _declaredCharset(Uint8List bytes) {
  final head = utf8.decode(
    bytes.length > 5120 ? bytes.sublist(0, 5120) : bytes,
    allowMalformed: true,
  );
  final meta = RegExp(
    r'''<meta\b[^>]*?charset\s*=\s*["']?([^\s"';>/]+)''',
    caseSensitive: false,
  ).firstMatch(head);
  if (meta != null) return meta.group(1);
  return RegExp(
    r'''^\s*<\?xml\b[^>]*?encoding\s*=\s*["']?([\w.:-]+)''',
    caseSensitive: false,
  ).firstMatch(head)?.group(1);
}

/// Java `Charset.name()` 的寫法：多數是大寫（GBK、UTF-8），少數照慣例。
String _javaCharsetName(String name) {
  final upper = name.trim().toUpperCase();
  return switch (upper) {
    'BIG5' => 'Big5',
    'SHIFT_JIS' || 'SHIFT-JIS' => 'Shift_JIS',
    _ when upper.startsWith('WINDOWS-') => 'windows-${upper.substring(8)}',
    _ => upper,
  };
}

String _decode(Uint8List bytes, String charset) {
  if (Charsets.supports(charset)) {
    try {
      return Charsets.decode(bytes, charset);
    } catch (_) {}
  }
  return EncodingDetect.decodeWithCharset(bytes, charset);
}

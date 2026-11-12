import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:night_reader/core/network/page_digest.dart';
import 'package:night_reader/core/network/page_notes.dart';
import 'package:night_reader/core/services/encoding_detect.dart';

/// 一份 [RequestLog] 記什麼；跨 isolate 送得過去（規則 JS 要等的請求在網路
/// isolate 照同樣的設定記，`BlockingCall`）。
typedef RequestLogSettings = ({
  int? responsePreview,
  bool digestPages,
  bool keepPages,
  bool sentHeaders,
});

/// [RequestLog.pages] 的一筆：請求或回應的那一行（同 [RequestLog.lines]），
/// 回應另帶整頁原文 [body]。
typedef LoggedPage = ({String line, String? body});

/// [LoggedPage] 跨 isolate 送的樣子。
List<Object?> loggedPageToJson(LoggedPage page) => [page.line, page.body];

LoggedPage loggedPageFromJson(Object? json) {
  final list = json! as List;
  return (line: list[0]! as String, body: list[1] as String?);
}

/// 一段工作實際送出的請求，依序記在 [lines]；給了 [responsePreview] 時每個
/// 回應也記一行（[recordResponse]），帶內容開頭的那麼多字，POST 這類記下
/// 送出的內容，並數出看起來是暫時性失敗的回應（[transientResponses]）：
/// 書源校驗據此決定要不要重試、失敗時看網站回了什麼（[diagnosisPreview]），
/// AI 修書源拿它看網頁現在長怎樣（長得多）。書源除錯只記網址。
/// [keepPages] 時另外照順序記一份不截、不精簡的（[pages]），給 AI 修復的
/// 完整紀錄。
///
/// 記錄點在所有請求都會經過的地方：Dio 的 `AppInterceptor`（含轉址的每
/// 一跳，規則 JS 的 `java.ajax`、`java.get` 這類也走這裡：它們在網路 isolate
/// 送出，記下的內容由 `BlockingCall` 帶回來，[merge] 接上）與兩種 WebView
/// 的入口。不在 [run] 裡時什麼都不記。
final class RequestLog {
  RequestLog({
    this.responsePreview,
    this.digestPages = false,
    this.keepPages = false,
    this.sentHeaders = false,
  });

  RequestLog.from(RequestLogSettings settings)
    : this(
        responsePreview: settings.responsePreview,
        digestPages: settings.digestPages,
        keepPages: settings.keepPages,
        sentHeaders: settings.sentHeaders,
      );

  /// 網頁先精簡（[digestPage]）再取開頭，給 AI 看。
  final bool digestPages;

  /// 書源校驗的診斷記每個回應的開頭幾個字。
  static const int diagnosisPreview = 160;

  /// 每個回應記內容開頭的幾個字；null 時不記回應。
  final int? responsePreview;

  /// 另外記一份完整的（[pages]）。只在 [withResponses] 時有用。
  final bool keepPages;

  /// 每個請求也記實際送出的標頭（[recordRequestUrl]）：AI 修書源看得出
  /// Cookie 這類有沒有真的送出去。
  final bool sentHeaders;

  RequestLogSettings get settings => (
    responsePreview: responsePreview,
    digestPages: digestPages,
    keepPages: keepPages,
    sentHeaders: sentHeaders,
  );

  bool get withResponses => responsePreview != null;
  final List<String> lines = [];

  /// 和 [lines] 一筆對一筆，回應另帶整頁原本的內容（照編碼解開，最多
  /// [fullPageBytes] 位元組，不精簡）；[keepPages] 才記。
  final List<LoggedPage> pages = [];

  /// [pages] 每個回應最多記多少位元組。
  static const int fullPageBytes = 2 * 1024 * 1024;

  int _transientResponses = 0;

  /// 看起來是暫時性失敗的回應數：網站忙碌（429、5xx）、回了空白、連不上。
  int get transientResponses => _transientResponses;

  /// 在這份紀錄裡執行 [body]：裡面送出的請求都記進來。
  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_requestLogZoneKey: this});

  /// 接上在別的 isolate 記下的內容（規則 JS 要等的請求在網路 isolate 送出，
  /// ADR 0034）。
  void merge(
    List<String> otherLines,
    int transientResponses, {
    List<LoggedPage> otherPages = const [],
  }) {
    lines.addAll(otherLines);
    pages.addAll(otherPages);
    _transientResponses += transientResponses;
  }

  void _add(String line, [String? body]) {
    lines.add(line);
    if (keepPages && withResponses) pages.add((line: line, body: body));
  }
}

/// 外層的 [RequestLog]；不在 [RequestLog.run] 裡時是 null。
RequestLog? get currentRequestLog =>
    Zone.current[_requestLogZoneKey] as RequestLog?;

/// 外層已經在 [RequestLog.run] 裡：裡面的請求會記進外層的紀錄。
bool get isRecordingRequestUrls => currentRequestLog != null;

/// 記下一筆送出的請求。網址 `#` 後面不會送出，記的時候去掉；GET 以外標出
/// 方法，轉址到的網址標出「轉址」。記回應的紀錄（`withResponses`）也記
/// 送出的內容 [body]（POST 的表單這類）：看得出規則實際送了什麼。
/// [RequestLog.sentHeaders] 時也記送出的標頭 [headers]（[_sentHeaders]）。
void recordRequestUrl(
  String method,
  Uri uri, {
  bool redirect = false,
  Object? body,
  Map<String, dynamic>? headers,
}) {
  final log = currentRequestLog;
  if (log == null) return;
  final upper = method.toUpperCase();
  final sent = log.withResponses ? _sentBody(body) : null;
  final sentHeaders = log.sentHeaders && headers != null
      ? _sentHeaders(headers)
      : null;
  log._add(
    '${upper == 'GET' ? '' : '$upper '}${uri.removeFragment()}'
    '${redirect ? '（轉址）' : ''}'
    '${sent == null ? '' : ' 送出：$sent'}'
    '${sentHeaders == null ? '' : ' 標頭：$sentHeaders'}',
  );
}

/// 送出的標頭寫成一行。Cookie 只寫名稱、Authorization 這類只寫有送：值可能
/// 是網站的登入狀態（ADR 0054 不送 Cookie）；看得出「有沒有送出去」就夠。
/// 沒有標頭是 null。
String? _sentHeaders(Map<String, dynamic> headers) {
  final parts = <String>[];
  for (final MapEntry(:key, :value) in headers.entries) {
    if (value == null) continue;
    final text = value is Iterable ? value.join('; ') : '$value';
    final name = key.toLowerCase();
    if (name == 'cookie') {
      final names = [
        for (final pair in text.split(';'))
          if (pair.split('=').first.trim() case final cookie
              when cookie.isNotEmpty)
            cookie,
      ];
      parts.add('Cookie（${names.join('、')}）');
    } else if (_hiddenHeaders.contains(name)) {
      parts.add('$key（有送，值不列）');
    } else {
      parts.add('$key: $text');
    }
  }
  return parts.isEmpty ? null : parts.join('；');
}

const Set<String> _hiddenHeaders = {
  'authorization',
  'proxy-authorization',
  'x-api-key',
};

/// 送出的內容寫成一行，最長 [_sentBodyLength] 字；沒有內容是 null。
String? _sentBody(Object? body) {
  final String text;
  switch (body) {
    case null:
      return null;
    case String():
      text = body;
    case List<int>():
      return '${body.length} 位元組';
    case FormData():
      text = [
        for (final MapEntry(:key, :value) in body.fields) '$key=$value',
        for (final MapEntry(:key, :value) in body.files)
          '$key=（檔案 ${value.length} 位元組）',
      ].join('&');
    case Map() || List():
      text = jsonEncode(body);
    default:
      text = '$body';
  }
  final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (line.isEmpty) return null;
  return line.length > _sentBodyLength
      ? '${line.substring(0, _sentBodyLength)}…'
      : line;
}

const int _sentBodyLength = 2000;

/// 記下一個回應：哪個網址、狀態碼、內容類型、長度與開頭一段（同時送出的
/// 請求回來的順序不一定，所以每行都帶網址）。沒有回應的失敗（連不上、
/// 逾時）記下失敗的種類。只在 `withResponses` 的紀錄裡記。
void recordResponse(Response<dynamic>? response, {DioException? error}) {
  final log = currentRequestLog;
  if (log == null || !log.withResponses) return;
  if (response == null) {
    final type = error?.type;
    final uri = error?.requestOptions.uri.removeFragment();
    log._add('  ← $uri 沒有回應（${type?.name ?? '未知'}）');
    // 網站擋下夜讀（Cloudflare 那幾種）也包成 unknown，只算真的連線斷掉的。
    if (type == DioExceptionType.connectionError ||
        (type == DioExceptionType.unknown && error?.error is IOException)) {
      log._transientResponses++;
    }
    return;
  }
  final status = response.statusCode;
  final type = response.headers.value(Headers.contentTypeHeader);
  final cache = _cacheNote(response.headers);
  final head =
      '  ← ${response.realUri.removeFragment()} ${status ?? '?'}'
      '${type == null ? '' : ' $type'}${cache == null ? '' : ' $cache'}';
  final empty = _recordBody(log, head, response.data, status: status);
  if (status == 429 || (status != null && status >= 500) || empty) {
    log._transientResponses++;
  }
}

/// 回應是網站前面的快取伺服器給的時，寫出快取的狀態，例如「（快取 HIT，
/// 存了 120 秒）」：被快取住的錯誤頁（2026-11-12 蜘蛛小說網的「搜索间隔」）
/// 不管怎麼改參數都一樣，看標頭才知道。沒有這些標頭是 null。
String? _cacheNote(Headers headers) {
  final hit = headers.value('cf-cache-status') ?? headers.value('x-cache');
  if (hit == null || hit.trim().isEmpty) return null;
  final age = headers.value('age');
  return '（快取 ${hit.trim()}${age == null ? '' : '，存了 ${age.trim()} 秒'}）';
}

/// 記下 WebView 渲染出的網頁：網址、內容長度與開頭。WebView 拿不到狀態碼，
/// 寫明沒有，不當成 200。
void recordRenderedPage(String? url, Object? body) {
  final log = currentRequestLog;
  if (log == null || !log.withResponses) return;
  final empty = _recordBody(log, '  ← ${url ?? '?'} 網頁渲染（沒有狀態碼）', body);
  if (empty) log._transientResponses++;
}

/// 回應那一行：[head] 接上長度與內容開頭；[RequestLog.pages] 那份接上整頁。
/// 傳回內容是不是空白。
bool _recordBody(RequestLog log, String head, Object? data, {int? status}) {
  final full = log.keepPages;
  final decoded = _decode(
    data,
    full || log.digestPages ? _digestBytes : log.responsePreview! * 4,
  );
  if (decoded == null) {
    log._add(head);
    return false;
  }
  final (length, text) = decoded;
  if (length == null) {
    log._add('$head，沒有內容');
    return true;
  }
  final raw = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  var collapsed = log.digestPages ? digestPage(text) : raw;
  // 很短的頁面精簡後沒有任何字（整頁只有一段 alert 程式，例如「搜索间隔:
  // 30 秒」）：給原文，不然看的人要再讀一次原文才知道網站回了什麼。
  final tooShort =
      log.digestPages &&
      raw.length <= 2000 &&
      collapsed.replaceAll(RegExp(r'<[^>]*>|\s'), '').isEmpty;
  if (tooShort) collapsed = raw;
  final preview = log.responsePreview!;
  final shown = collapsed.length > preview
      ? '${collapsed.substring(0, preview)}…'
      : collapsed;
  // 給 AI 看的寫出精簡後共幾字：它才知道後面還有沒有。
  final digested = !log.digestPages
      ? ''
      : tooShort
      ? '，太短不精簡'
      : '，精簡後 ${collapsed.length} 字';
  // 限流、防護頁與轉址頁精簡後幾乎是空的，寫出它是什麼（[pageNoteOf]）。
  final note = pageNoteOf(text, status: status);
  log._add(
    '$head，$length$digested${note == null ? '' : '（$note）'}'
    '${shown.isEmpty ? '' : '：$shown'}',
    full ? text : null,
  );
  return collapsed.isEmpty;
}

/// 回應內容的長度與文字；不認得的型別是 null，沒有內容時長度是 null。
/// 位元組照網頁宣告的編碼解開（GBK 這類中文網站），沒宣告的照內容猜，最多
/// 解開 [maxBytes] 位元組。
(String?, String)? _decode(Object? data, int maxBytes) {
  switch (data) {
    case null:
      return (null, '');
    case String():
      return ('${data.length} 字', data);
    case List<int>():
      final bytes = Uint8List.fromList(
        data.length > maxBytes ? data.sublist(0, maxBytes) : data,
      );
      return (
        '${data.length} 位元組',
        EncodingDetect.decodeWithCharset(
          bytes,
          EncodingDetect.getHtmlEncode(bytes),
        ),
      );
    case Map() || List():
      final text = jsonEncode(data);
      return ('${text.length} 字', text);
    default:
      return null;
  }
}

const int _digestBytes = RequestLog.fullPageBytes;

final Object _requestLogZoneKey = Object();

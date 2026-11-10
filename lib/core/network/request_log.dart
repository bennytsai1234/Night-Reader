import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:night_reader/core/network/page_digest.dart';
import 'package:night_reader/core/services/encoding_detect.dart';

/// 一段工作實際送出的請求，依序記在 [lines]；給了 [responsePreview] 時每個
/// 回應也記一行（[recordResponse]），帶內容開頭的那麼多字，並數出看起來是
/// 暫時性失敗的回應（[transientResponses]）：書源校驗據此決定要不要重試、
/// 失敗時看網站回了什麼（[diagnosisPreview]），AI 修書源拿它看網頁現在長
/// 怎樣（長得多）。書源除錯只記網址。
///
/// 記錄點在所有請求都會經過的地方：Dio 的 `AppInterceptor`（含轉址的每
/// 一跳，規則 JS 的 `java.ajax`、`java.get` 這類也走這裡：它們在網路 isolate
/// 送出，記下的內容由 `BlockingCall` 帶回來，[merge] 接上）與兩種 WebView
/// 的入口。不在 [run] 裡時什麼都不記。
final class RequestLog {
  RequestLog({this.responsePreview, this.digestPages = false});

  /// 網頁先精簡（[digestPage]）再取開頭，給 AI 看。
  final bool digestPages;

  /// 書源校驗的診斷記每個回應的開頭幾個字。
  static const int diagnosisPreview = 160;

  /// 每個回應記內容開頭的幾個字；null 時不記回應。
  final int? responsePreview;

  bool get withResponses => responsePreview != null;
  final List<String> lines = [];
  int _transientResponses = 0;

  /// 看起來是暫時性失敗的回應數：網站忙碌（429、5xx）、回了空白、連不上。
  int get transientResponses => _transientResponses;

  /// 在這份紀錄裡執行 [body]：裡面送出的請求都記進來。
  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_requestLogZoneKey: this});

  /// 接上在別的 isolate 記下的內容（規則 JS 要等的請求在網路 isolate 送出，
  /// ADR 0034）。
  void merge(List<String> otherLines, int transientResponses) {
    lines.addAll(otherLines);
    _transientResponses += transientResponses;
  }
}

/// 外層的 [RequestLog]；不在 [RequestLog.run] 裡時是 null。
RequestLog? get currentRequestLog =>
    Zone.current[_requestLogZoneKey] as RequestLog?;

/// 外層已經在 [RequestLog.run] 裡：裡面的請求會記進外層的紀錄。
bool get isRecordingRequestUrls => currentRequestLog != null;

/// 外層的紀錄每個回應記開頭幾個字；不記回應時是 null。
int? get recordingResponsePreview => currentRequestLog?.responsePreview;

/// 記下一筆送出的請求。網址 `#` 後面不會送出，記的時候去掉；GET 以外標出
/// 方法，轉址到的網址標出「轉址」。
void recordRequestUrl(String method, Uri uri, {bool redirect = false}) {
  final log = currentRequestLog;
  if (log == null) return;
  final upper = method.toUpperCase();
  log.lines.add(
    '${upper == 'GET' ? '' : '$upper '}${uri.removeFragment()}'
    '${redirect ? '（轉址）' : ''}',
  );
}

/// 記下一個回應：哪個網址、狀態碼、內容類型、長度與開頭一段（同時送出的
/// 請求回來的順序不一定，所以每行都帶網址）。沒有回應的失敗（連不上、
/// 逾時）記下失敗的種類。只在 `withResponses` 的紀錄裡記。
void recordResponse(Response<dynamic>? response, {DioException? error}) {
  final log = currentRequestLog;
  if (log == null || !log.withResponses) return;
  if (response == null) {
    final type = error?.type;
    final uri = error?.requestOptions.uri.removeFragment();
    log.lines.add('  ← $uri 沒有回應（${type?.name ?? '未知'}）');
    // 網站擋下夜讀（Cloudflare 那幾種）也包成 unknown，只算真的連線斷掉的。
    if (type == DioExceptionType.connectionError ||
        (type == DioExceptionType.unknown && error?.error is IOException)) {
      log._transientResponses++;
    }
    return;
  }
  final status = response.statusCode;
  final type = response.headers.value(Headers.contentTypeHeader);
  final (length, head, empty) = _bodyPreview(
    response.data,
    log.responsePreview!,
    digest: log.digestPages,
  );
  log.lines.add(
    '  ← ${response.realUri.removeFragment()} ${status ?? '?'}'
    '${type == null ? '' : ' $type'}'
    '${length == null ? '' : '，$length'}'
    '${head.isEmpty ? '' : '：$head'}',
  );
  if (status == 429 || (status != null && status >= 500) || empty) {
    log._transientResponses++;
  }
}

/// 記下 WebView 渲染出的網頁：網址、內容長度與開頭。WebView 拿不到狀態碼，
/// 寫明沒有，不當成 200。
void recordRenderedPage(String? url, Object? body) {
  final log = currentRequestLog;
  if (log == null || !log.withResponses) return;
  final (length, head, empty) = _bodyPreview(
    body,
    log.responsePreview!,
    digest: log.digestPages,
  );
  log.lines.add(
    '  ← ${url ?? '?'} 網頁渲染（沒有狀態碼）'
    '${length == null ? '' : '，$length'}'
    '${head.isEmpty ? '' : '：$head'}',
  );
  if (empty) log._transientResponses++;
}

/// 回應內容的長度、開頭 [previewLength] 個字（空白合成一格）與是不是空白。
/// 位元組照網頁宣告的編碼解開（GBK 這類中文網站），沒宣告的照內容猜。
/// [digest] 時整頁解開、精簡過再取開頭（最多解開 [_digestBytes] 位元組）。
(String?, String, bool) _bodyPreview(
  Object? data,
  int previewLength, {
  bool digest = false,
}) {
  final decodeBytes = digest ? _digestBytes : previewLength * 4;
  final String text;
  final String length;
  switch (data) {
    case null:
      return ('沒有內容', '', true);
    case String():
      text = data;
      length = '${data.length} 字';
    case List<int>():
      final bytes = Uint8List.fromList(
        data.length > decodeBytes ? data.sublist(0, decodeBytes) : data,
      );
      text = EncodingDetect.decodeWithCharset(
        bytes,
        EncodingDetect.getHtmlEncode(bytes),
      );
      length = '${data.length} 位元組';
    case Map() || List():
      text = jsonEncode(data);
      length = '${text.length} 字';
    default:
      return (null, '', false);
  }
  final collapsed = digest
      ? digestPage(text)
      : text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return (
    length,
    collapsed.length > previewLength
        ? '${collapsed.substring(0, previewLength)}…'
        : collapsed,
    collapsed.isEmpty,
  );
}

const int _digestBytes = 2 * 1024 * 1024;

final Object _requestLogZoneKey = Object();

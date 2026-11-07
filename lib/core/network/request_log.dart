import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// 書源除錯要看實際送出的網址：在 [body] 裡送出的請求依序記進 [urls]。
/// [withResponses] 時每個回應也記一行（[recordResponse]），書源校驗失敗時
/// 拿來看網站回了什麼。
///
/// 記錄點在所有請求都會經過的地方：Dio 的 `AppInterceptor`（含轉址的每
/// 一跳，規則 JS 的 `java.ajax`、`java.get` 這類也走這裡：它們在網路 isolate
/// 送出，記下的網址由 `BlockingCall` 帶回來）與兩種 WebView
/// 的入口。不在 [body] 裡時什麼都不記。
Future<T> recordRequestUrls<T>(
  List<String> urls,
  Future<T> Function() body, {
  bool withResponses = false,
}) => runZoned(
  body,
  zoneValues: {_requestLogZoneKey: _RequestLog(urls, withResponses)},
);

/// 外層已經在 [recordRequestUrls] 裡：裡面的請求會記進外層的清單。
bool get isRecordingRequestUrls => _current != null;

/// 外層的 [recordRequestUrls] 連回應也記。
bool get isRecordingResponses => _current?.withResponses ?? false;

/// 記下一筆送出的請求。網址 `#` 後面不會送出，記的時候去掉；GET 以外標出
/// 方法，轉址到的網址標出「轉址」。
void recordRequestUrl(String method, Uri uri, {bool redirect = false}) {
  final log = _current;
  if (log == null) return;
  final upper = method.toUpperCase();
  log.lines.add(
    '${upper == 'GET' ? '' : '$upper '}${uri.removeFragment()}'
    '${redirect ? '（轉址）' : ''}',
  );
}

/// 記下一個回應：狀態碼、內容類型、長度與開頭一段。沒有回應的失敗（連不
/// 上、逾時）記下失敗的種類。只在 [recordRequestUrls] 的 `withResponses`
/// 裡記。
void recordResponse(Response<dynamic>? response, {DioException? error}) {
  final log = _current;
  if (log == null || !log.withResponses) return;
  if (response == null) {
    log.lines.add('  ← 沒有回應（${error?.type.name ?? '未知'}）');
    return;
  }
  final type = response.headers.value(Headers.contentTypeHeader);
  final (length, head) = _bodyPreview(response.data);
  log.lines.add(
    '  ← ${response.statusCode ?? '?'}'
    '${type == null ? '' : ' $type'}'
    '${length == null ? '' : '，$length'}'
    '${head.isEmpty ? '' : '：$head'}',
  );
}

/// 接上在別的 isolate 記下的 [urls]（規則 JS 要等的請求在網路 isolate 送出，
/// ADR 0034）。不在 [recordRequestUrls] 裡時什麼都不做。
void recordRequestedUrls(List<String> urls) {
  if (urls.isEmpty) return;
  _current?.lines.addAll(urls);
}

const int _previewLength = 160;

/// 回應內容的長度與開頭一段（空白合成一格）。位元組照 UTF-8 解開，其他
/// 編碼的網站會是亂碼，只看得出有沒有內容。
(String?, String) _bodyPreview(Object? data) {
  final String text;
  final String length;
  switch (data) {
    case null:
      return ('沒有內容', '');
    case String():
      text = data;
      length = '${data.length} 字';
    case List<int>():
      final head = data.length > _previewLength * 4
          ? data.sublist(0, _previewLength * 4)
          : data;
      text = utf8.decode(head, allowMalformed: true);
      length = '${data.length} 位元組';
    case Map() || List():
      text = jsonEncode(data);
      length = '${text.length} 字';
    default:
      return (null, '');
  }
  final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return (
    length,
    collapsed.length > _previewLength
        ? '${collapsed.substring(0, _previewLength)}…'
        : collapsed,
  );
}

_RequestLog? get _current => Zone.current[_requestLogZoneKey] as _RequestLog?;

final class _RequestLog {
  const _RequestLog(this.lines, this.withResponses);

  final List<String> lines;
  final bool withResponses;
}

final Object _requestLogZoneKey = Object();

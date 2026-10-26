import 'dart:async';

/// 書源除錯要看實際送出的網址：在 [body] 裡送出的請求依序記進 [urls]。
///
/// 記錄點在所有請求都會經過的地方：Dio 的 `AppInterceptor`（含轉址的每
/// 一跳，規則 JS 的 `java.ajax`、`java.get` 這類也走這裡）與兩種 WebView
/// 的入口。不在 [body] 裡時什麼都不記。
Future<T> recordRequestUrls<T>(List<String> urls, Future<T> Function() body) =>
    runZoned(body, zoneValues: {_requestUrlsZoneKey: urls});

/// 外層已經在 [recordRequestUrls] 裡：裡面的請求會記進外層的清單。
bool get isRecordingRequestUrls => Zone.current[_requestUrlsZoneKey] != null;

/// 記下一筆送出的請求。網址 `#` 後面不會送出，記的時候去掉；GET 以外標出
/// 方法，轉址到的網址標出「轉址」。
void recordRequestUrl(String method, Uri uri, {bool redirect = false}) {
  final urls = Zone.current[_requestUrlsZoneKey] as List<String>?;
  if (urls == null) return;
  final upper = method.toUpperCase();
  urls.add(
    '${upper == 'GET' ? '' : '$upper '}${uri.removeFragment()}'
    '${redirect ? '（轉址）' : ''}',
  );
}

final Object _requestUrlsZoneKey = Object();

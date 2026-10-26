import 'package:dio/dio.dart';
import 'package:night_reader/core/network/redirects.dart';
import 'package:night_reader/core/network/str_response.dart';

/// 回應在規則 JS 裡的資料（`buildHttpResponse` 包成有 `body()`、`code()`、
/// `url()` 的回應物件，同 Legado 的 StrResponse）。`java.connect` 的回傳與
/// 登入檢查的 `result` 都是它。
Map<String, Object?> responseToJs(StrResponse response, {String? requestUrl}) =>
    {
      'body': response.body,
      'url': response.url,
      'requestUrl': requestUrl ?? response.raw.requestOptions.uri.toString(),
      'code': response.raw.statusCode ?? 200,
      'message': response.raw.statusMessage ?? '',
      'headers': response.headers,
      'redirects': response.redirectChain,
      // HTTP 套件自己跟著走的轉址；換回 StrResponse 時還原，`isRedirect` 照舊。
      'autoRedirects': [
        for (final uri in response.raw.redirectedUris) uri.toString(),
      ],
    };

/// 規則 JS 傳回的回應物件（[responseToJs] 的資料）換回 [StrResponse]。
StrResponse responseFromJs(Map<dynamic, dynamic> data) {
  final url = data['url']?.toString() ?? '';
  final headers = <String, List<String>>{};
  (data['headers'] as Map?)?.forEach((key, value) {
    headers[key.toString()] = value is List
        ? [for (final item in value) item.toString()]
        : [value.toString()];
  });
  return StrResponse(
    url: url,
    body: data['body']?.toString() ?? '',
    headers: headers,
    raw: Response(
      requestOptions: RequestOptions(
        path: data['requestUrl']?.toString() ?? url,
      ),
      statusCode: (data['code'] as num?)?.toInt(),
      statusMessage: data['message']?.toString(),
      headers: Headers.fromMap(headers),
      // 原本每一跳的狀態碼沒帶過來，只留下走到的網址。
      redirects: [
        for (final item in (data['autoRedirects'] as List?) ?? const [])
          RedirectRecord(302, 'GET', Uri.parse(item.toString())),
      ],
      extra: {
        '_manualRedirectChain': [
          for (final item in (data['redirects'] as List?) ?? const [])
            item.toString(),
        ],
      },
    ),
  );
}

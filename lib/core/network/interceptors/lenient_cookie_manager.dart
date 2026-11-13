import 'dart:async';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart' as dio_cookie;
import 'package:night_reader/core/network/redirects.dart';

final _setCookieReg = RegExp('(?<=)(,)(?=[^;]+?=)');

/// Cookie manager variant that tolerates malformed session-cookie markers such
/// as `expires=session`, which some book-source sites emit in the wild.
class LenientCookieManager extends Interceptor {
  LenientCookieManager(this.cookieJar, {this.ignoreInvalidCookies = true});

  final CookieJar cookieJar;
  bool ignoreInvalidCookies;

  /// 請求的 `extra` 裡這一項是 false 時，回應的 Cookie 不存：書源沒開
  /// Cookie 罐（同 Legado：`HttpHelper` 的網路攔截器只在請求帶著 CookieJar
  /// 標頭時 `CookieManager.saveResponse`）。存著的 Cookie 照樣帶上。
  static const String saveResponseCookiesKey = 'saveResponseCookies';

  /// 書源請求的 `extra`：照 [enabledCookieJar] 決定存不存回應的 Cookie。
  static Map<String, dynamic> sourceExtra(bool enabledCookieJar) => {
    if (!enabledCookieJar) saveResponseCookiesKey: false,
  };

  static String getCookies(List<Cookie> cookies) {
    cookies.sort((a, b) {
      if (a.path == null && b.path == null) {
        return 0;
      } else if (a.path == null) {
        return -1;
      } else if (b.path == null) {
        return 1;
      }
      return b.path!.length.compareTo(a.path!.length);
    });
    return cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final cookies = await loadCookies(options);
      options.headers[HttpHeaders.cookieHeader] = cookies.isNotEmpty
          ? cookies
          : null;
      handler.next(options);
    } catch (e, s) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: dio_cookie.CookieManagerLoadException(error: e, stackTrace: s),
          message: 'Failed to load cookies for the request.',
        ),
        true,
      );
    }
  }

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    try {
      await saveCookies(response);
      handler.next(response);
    } catch (e, s) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.unknown,
          error: dio_cookie.CookieManagerSaveException(
            response: response,
            error: e,
            stackTrace: s,
            dioException: null,
          ),
          stackTrace: s,
        ),
        true,
      );
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    if (response == null) {
      handler.next(err);
      return;
    }

    try {
      await saveCookies(response);
      handler.next(err);
    } catch (e, s) {
      handler.next(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.unknown,
          error: dio_cookie.CookieManagerSaveException(
            response: response,
            error: e,
            stackTrace: s,
            dioException: err,
          ),
          stackTrace: s,
        ),
      );
    }
  }

  Cookie? _fromSetCookieValue(String value) {
    return parseSetCookieValueLenient(
      value,
      ignoreInvalidCookies: ignoreInvalidCookies,
    );
  }

  /// 請求自己帶的 Cookie（規則給的、併進來的 `CookieStore`）加上 Cookie 罐裡
  /// 符合網址的；同名的以請求帶的為準，罐裡的舊值不再附上（同 Legado
  /// `CookieManager.mergeCookies` 照名稱合成一份）：不然網站同時收到
  /// `sid=新; sid=舊`。
  Future<String> loadCookies(RequestOptions options) async {
    final savedCookies = await cookieJar.loadForRequest(options.uri);
    final given = _cookieHeaderValues(options.headers)
        .expand((value) => value.split(';'))
        .where((e) => e.trim().isNotEmpty)
        .map((c) => _fromSetCookieValue(c))
        .whereType<Cookie>()
        .toList();
    final givenNames = {for (final cookie in given) cookie.name};
    return getCookies([
      ...given,
      ...savedCookies.where((cookie) => !givenNames.contains(cookie.name)),
    ]);
  }

  Future<void> saveCookies(Response response) async {
    if (response.requestOptions.extra[saveResponseCookiesKey] == false) return;
    final setCookies = response.headers[HttpHeaders.setCookieHeader];
    if (setCookies == null || setCookies.isEmpty) {
      return;
    }

    final cookies = setCookies
        .map((str) => str.split(_setCookieReg))
        .expand((cookie) => cookie)
        .where((cookie) => cookie.isNotEmpty)
        .map((str) => _fromSetCookieValue(str))
        .whereType<Cookie>()
        .toList();

    await cookieJar.saveFromResponse(response.finalUri, cookies);
  }

  Iterable<String> _cookieHeaderValues(Map<String, dynamic> headers) sync* {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != HttpHeaders.cookieHeader) continue;
      final value = entry.value;
      if (value is String) {
        yield value;
      } else if (value is Iterable) {
        yield* value
            .where((item) => item != null)
            .map((item) => item.toString());
      }
    }
  }
}

Cookie? parseSetCookieValueLenient(
  String value, {
  bool ignoreInvalidCookies = false,
}) {
  try {
    return Cookie.fromSetCookieValue(value);
  } catch (error) {
    if (error is! HttpException && error is! FormatException) rethrow;
    final sanitized = sanitizeSetCookieValue(value);
    if (sanitized != value && sanitized.isNotEmpty) {
      try {
        return Cookie.fromSetCookieValue(sanitized);
      } catch (sanitizedError) {
        if (sanitizedError is! HttpException &&
            sanitizedError is! FormatException) {
          rethrow;
        }
        if (ignoreInvalidCookies) {
          return null;
        }
        rethrow;
      }
    }
    if (ignoreInvalidCookies) {
      return null;
    }
    rethrow;
  }
}

String sanitizeSetCookieValue(String value) {
  final segments = value.split(';');
  if (segments.length < 2) {
    return value;
  }

  final kept = <String>[];
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i].trim();
    if (segment.isEmpty) {
      continue;
    }
    if (i > 0 && _isSessionSentinelDirective(segment)) {
      continue;
    }
    kept.add(segment);
  }

  if (kept.isEmpty) {
    return value;
  }
  return kept.join('; ');
}

bool _isSessionSentinelDirective(String segment) {
  final separatorIndex = segment.indexOf('=');
  if (separatorIndex <= 0) {
    return false;
  }

  final name = segment.substring(0, separatorIndex).trim().toLowerCase();
  if (name != 'expires' && name != 'max-age') {
    return false;
  }

  final rawValue = segment.substring(separatorIndex + 1).trim();
  final normalizedValue = rawValue
      .replaceAll(RegExp("^[\"']+|[\"']+\$"), '')
      .trim()
      .toLowerCase();
  return normalizedValue == 'session';
}

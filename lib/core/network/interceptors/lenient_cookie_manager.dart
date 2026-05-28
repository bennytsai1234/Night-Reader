import 'dart:async';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart' as dio_cookie;

final _setCookieReg = RegExp('(?<=)(,)(?=[^;]+?=)');

/// Cookie manager variant that tolerates malformed session-cookie markers such
/// as `expires=session`, which some book-source sites emit in the wild.
class LenientCookieManager extends Interceptor {
  LenientCookieManager(this.cookieJar, {this.ignoreInvalidCookies = false});

  final CookieJar cookieJar;
  bool ignoreInvalidCookies;

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
      options.headers[HttpHeaders.cookieHeader] =
          cookies.isNotEmpty ? cookies : null;
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

  Future<String> loadCookies(RequestOptions options) async {
    final savedCookies = await cookieJar.loadForRequest(options.uri);
    final previousCookies =
        options.headers[HttpHeaders.cookieHeader] as String?;
    final cookies = getCookies([
      ...?previousCookies
          ?.split(';')
          .where((e) => e.isNotEmpty)
          .map((c) => _fromSetCookieValue(c))
          .whereType<Cookie>(),
      ...savedCookies,
    ]);
    return cookies;
  }

  Future<void> saveCookies(Response response) async {
    final setCookies = response.headers[HttpHeaders.setCookieHeader];
    if (setCookies == null || setCookies.isEmpty) {
      return;
    }

    final cookies =
        setCookies
            .map((str) => str.split(_setCookieReg))
            .expand((cookie) => cookie)
            .where((cookie) => cookie.isNotEmpty)
            .map((str) => _fromSetCookieValue(str))
            .whereType<Cookie>()
            .toList();

    final originalUri = response.requestOptions.uri;
    final realUri = originalUri.resolveUri(response.realUri);
    await cookieJar.saveFromResponse(realUri, cookies);

    final statusCode = response.statusCode ?? 0;
    final locations = response.headers[HttpHeaders.locationHeader] ?? [];
    final redirected = statusCode >= 300 && statusCode < 400;
    if (redirected && locations.isNotEmpty) {
      final baseUri = response.realUri;
      await Future.wait(
        locations.map(
          (location) =>
              cookieJar.saveFromResponse(baseUri.resolve(location), cookies),
        ),
      );
    }
  }
}

Cookie? parseSetCookieValueLenient(
  String value, {
  bool ignoreInvalidCookies = false,
}) {
  try {
    return Cookie.fromSetCookieValue(value);
  } on HttpException {
    final sanitized = sanitizeSetCookieValue(value);
    if (sanitized != value && sanitized.isNotEmpty) {
      try {
        return Cookie.fromSetCookieValue(sanitized);
      } on HttpException {
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
  final normalizedValue =
      rawValue.replaceAll(RegExp("^[\"']+|[\"']+\$"), '').trim().toLowerCase();
  return normalizedValue == 'session';
}

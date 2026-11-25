import 'dart:async';
import 'dart:convert';
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
    return cookies
        .where(cookieFitsHeader)
        .map((cookie) => '${cookie.name}=${cookieValueForRequest(cookie)}')
        .join('; ');
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
    // 同 Legado `CookieStore.cookieToMap`：照字串切 `;` 與第一個 `=`，只略過
    // 空值；空白、逗號、雙引號（`a={"k":1}`）照原樣，不經 dart:io Cookie 的
    // 字元檢查。中文這種值留著，但 dart:io 的標頭送不出去，[getCookies] 會
    // 略過那一條。
    final given = <String, String>{};
    for (final header in _cookieHeaderValues(options.headers)) {
      for (final pair in header.split(';')) {
        final index = pair.indexOf('=');
        if (index <= 0) continue;
        final name = pair.substring(0, index).trim();
        final value = pair.substring(index + 1).trim();
        if (name.isEmpty || value.isEmpty) continue;
        given[name] = value;
      }
    }
    final givenNames = given.keys.toSet();
    return getCookies([
      for (final entry in given.entries) _LenientCookie(entry.key, entry.value),
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

/// Set-Cookie 的一段。合法的值照 `dart:io` 嚴格解析；值有空白、中文、逗號、
/// 雙引號這類 RFC 6265 不收的字元時改用寬鬆解析，值保留原文
/// （[_LenientCookie]）。
Cookie? parseSetCookieValueLenient(
  String value, {
  bool ignoreInvalidCookies = false,
}) {
  try {
    return Cookie.fromSetCookieValue(value);
  } catch (error) {
    if (error is! HttpException && error is! FormatException) rethrow;
    final cookie = _parseLenientSetCookie(value);
    if (cookie != null) return cookie;
    if (ignoreInvalidCookies) return null;
    rethrow;
  }
}

Cookie? _parseLenientSetCookie(String value) {
  final segments = value.split(';');
  final pair = segments.first;
  final index = pair.indexOf('=');
  if (index <= 0) return null;
  final name = pair.substring(0, index).trim();
  if (!_isCookieName(name)) return null;
  final cookie = _LenientCookie(name, pair.substring(index + 1).trim());

  for (final segment in segments.skip(1)) {
    final attribute = segment.trim();
    if (attribute.isEmpty) continue;
    final separator = attribute.indexOf('=');
    final attributeName =
        (separator < 0 ? attribute : attribute.substring(0, separator))
            .trim()
            .toLowerCase();
    final attributeValue = separator < 0
        ? ''
        : attribute.substring(separator + 1).trim();
    switch (attributeName) {
      case 'expires':
        try {
          cookie.expires = HttpDate.parse(attributeValue);
        } on HttpException {
          // `expires=session` 這類不是日期的當沒有過期時間（同 Legado 只
          // 照 OkHttp 讀得到的部分）。
        } on FormatException {
          // 同上。
        }
      case 'max-age':
        final maxAge = int.tryParse(attributeValue);
        if (maxAge != null) cookie.maxAge = maxAge;
      case 'domain':
        if (attributeValue.isNotEmpty) cookie.domain = attributeValue;
      case 'path':
        if (attributeValue.isNotEmpty) cookie.path = attributeValue;
      case 'secure':
        cookie.secure = true;
      case 'httponly':
        cookie.httpOnly = true;
      case 'samesite':
        cookie.sameSite = switch (attributeValue.toLowerCase()) {
          'lax' => SameSite.lax,
          'strict' => SameSite.strict,
          'none' when cookie.secure => SameSite.none,
          _ => null,
        };
    }
  }
  return cookie;
}

/// `dart:io` 的 [Cookie] 只收 RFC 6265 的字元，值有空白、中文、逗號或雙引號
/// 時建不起來；網站與書源規則常寫這種 Cookie（例如 JSON 值），Legado 照字串
/// 存、原樣送回。自己實作一份，值保留原文；寫進 Cookie 檔時把 `dart:io`
/// 存不下的字元編碼，讀回來交給 [cookieValueForRequest] 解回原文。
final class _LenientCookie implements Cookie {
  _LenientCookie(this._name, this._value);

  String _name;
  String _value;

  @override
  String get name => _name;

  @override
  set name(String value) => _name = value;

  @override
  String get value => _value;

  @override
  set value(String value) => _value = value;

  @override
  DateTime? expires;

  @override
  int? maxAge;

  @override
  String? domain;

  @override
  String? path;

  @override
  bool secure = false;

  @override
  bool httpOnly = false;

  @override
  SameSite? sameSite;

  @override
  String toString() {
    final out = StringBuffer()
      ..write(_name)
      ..write('=')
      ..write(_storedCookieValue(_value));
    void parameter(String name, [Object? value]) {
      out.write('; $name');
      if (value != null) out.write('=$value');
    }

    final expires = this.expires;
    if (expires != null) {
      out.write('; Expires=');
      out.write(HttpDate.format(expires));
    }
    if (maxAge != null) parameter('Max-Age', maxAge);
    if (domain != null) parameter('Domain', domain!.trim());
    if (path != null) parameter('Path', path!.trim());
    if (secure) parameter('Secure');
    if (httpOnly) parameter('HttpOnly');
    if (sameSite != null) parameter('SameSite', sameSite!.name);
    return out.toString();
  }
}

/// Cookie 檔裡代表原文的開頭：`dart:io` 存不下的值以 base64url 接在後面。
/// 合法值照原樣寫；本身就長這樣的值再多編一次，讀回時用「再編一次一樣」
/// 確認，不會把網站原本的值解錯。
const _encodedValuePrefix = 'nr~';

String _storedCookieValue(String value) {
  if (!value.startsWith(_encodedValuePrefix) && _cookieValueFits(value)) {
    return value;
  }
  return '$_encodedValuePrefix${base64Url.encode(utf8.encode(value))}';
}

bool _cookieValueFits(String value) {
  var start = 0;
  var end = value.length;
  if (end >= 2 && value.startsWith('"') && value.endsWith('"')) {
    start++;
    end--;
  }
  for (var i = start; i < end; i++) {
    final unit = value.codeUnitAt(i);
    if (unit < 0x21 ||
        unit > 0x7E ||
        unit == 0x22 ||
        unit == 0x2C ||
        unit == 0x3B ||
        unit == 0x5C) {
      return false;
    }
  }
  return true;
}

/// Cookie 罐裡的 [cookie] 要送出的值：App 自己編碼存下的解回原文，網站原本
/// 就長得像編碼的值照原樣送。
String cookieValueForRequest(Cookie cookie) {
  if (cookie is _LenientCookie) return cookie.value;
  final value = cookie.value;
  if (!value.startsWith(_encodedValuePrefix)) return value;
  try {
    final decoded = utf8.decode(
      base64Url.decode(value.substring(_encodedValuePrefix.length)),
    );
    if (_storedCookieValue(decoded) == value) return decoded;
  } on FormatException {
    // 不是 App 編碼的值：照原樣送。
  }
  return value;
}

/// Cookie 的 `名稱=值` 能不能放進 HTTP 標頭：`dart:io` 的標頭只收 ASCII
/// 與 tab，中文這類值放進去整條請求會失敗（Legado 的 OkHttp 也一樣擋）。
/// 這種 Cookie 留在罐子裡給規則讀，不進標頭。
bool cookieFitsHeader(Cookie cookie) =>
    cookiePairFitsHeader(cookie.name, cookieValueForRequest(cookie));

/// 還沒進 Cookie 罐、書源規則自己給的一條 Cookie（[cookieFitsHeader]）。
bool cookiePairFitsHeader(String name, String value) =>
    _fitsHeaderValue('$name=$value');

bool _fitsHeaderValue(String value) {
  for (final unit in value.codeUnits) {
    if (unit != 0x09 && (unit < 0x20 || unit > 0x7E)) return false;
  }
  return true;
}

bool _isCookieName(String name) {
  if (name.isEmpty) return false;
  const separators = r'''()<>@,;:\"/[]?={}''';
  for (final unit in name.codeUnits) {
    if (unit <= 0x20 || unit >= 0x7F || separators.codeUnits.contains(unit)) {
      return false;
    }
  }
  return true;
}

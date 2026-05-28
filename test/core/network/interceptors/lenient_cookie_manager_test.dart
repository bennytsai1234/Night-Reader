import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/core/network/interceptors/lenient_cookie_manager.dart';

void main() {
  group('LenientCookieManager', () {
    test('parses cookies with expires=session as session cookies', () {
      final cookie = parseSetCookieValueLenient(
        'msecToken=abc123;expires=session;Domain=.qq.com;Path=/;secure;samesite=none',
      );

      expect(cookie, isNotNull);
      expect(cookie!.name, 'msecToken');
      expect(cookie.value, 'abc123');
      expect(cookie.domain, '.qq.com');
      expect(cookie.path, '/');
      expect(cookie.secure, isTrue);
      expect(cookie.expires, isNull);
    });

    test('saves sanitized cookies from responses', () async {
      final cookieJar = CookieJar();
      final manager = LenientCookieManager(cookieJar);
      final requestUri = Uri.parse(
        'https://yunqi.qq.com/search/%E6%88%91%E7%9A%84',
      );
      final response = Response<void>(
        requestOptions: RequestOptions(path: requestUri.toString()),
        headers: Headers.fromMap({
          HttpHeaders.setCookieHeader: [
            'msecToken=abc123;expires=session;Domain=.qq.com;Path=/;secure;samesite=none',
          ],
        }),
        statusCode: 200,
      );

      await manager.saveCookies(response);

      final cookies = await cookieJar.loadForRequest(requestUri);
      expect(cookies.map((cookie) => cookie.name), contains('msecToken'));
      expect(
        cookies.firstWhere((cookie) => cookie.name == 'msecToken').value,
        'abc123',
      );
    });
  });
}

import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/interceptors/lenient_cookie_manager.dart';

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

    test('parses cookies with max-age=session as session cookies', () {
      final cookie = parseSetCookieValueLenient(
        'token=abc123; Max-Age=session; Path=/',
      );

      expect(cookie, isNotNull);
      expect(cookie!.name, 'token');
      expect(cookie.value, 'abc123');
      expect(cookie.maxAge, isNull);
      expect(cookie.path, '/');
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

    test(
      'default manager skips one invalid cookie and saves valid peers',
      () async {
        final cookieJar = CookieJar();
        final manager = LenientCookieManager(cookieJar);
        final requestUri = Uri.parse('https://example.com/search');
        final response = Response<void>(
          requestOptions: RequestOptions(path: requestUri.toString()),
          headers: Headers.fromMap({
            HttpHeaders.setCookieHeader: [
              'invalid name=value; Path=/',
              'valid=value; Path=/',
            ],
          }),
          statusCode: 200,
        );

        await manager.saveCookies(response);

        final cookies = await cookieJar.loadForRequest(requestUri);
        expect(cookies.map((cookie) => cookie.name), ['valid']);
      },
    );

    test('loads manual Cookie headers case-insensitively', () async {
      final manager = LenientCookieManager(CookieJar());
      final options = RequestOptions(
        path: 'https://example.com/search',
        headers: <String, dynamic>{'Cookie': 'manual=value'},
      );

      final cookies = await manager.loadCookies(options);

      expect(cookies, 'manual=value');
    });

    test('loads list-valued manual Cookie headers', () async {
      final manager = LenientCookieManager(CookieJar());
      final options = RequestOptions(
        path: 'https://example.com/search',
        headers: <String, dynamic>{
          HttpHeaders.cookieHeader: <String>['first=1', 'second=2'],
        },
      );

      final cookies = await manager.loadCookies(options);

      expect(cookies, contains('first=1'));
      expect(cookies, contains('second=2'));
    });

    test(
      'malformed redirect Location does not discard response cookies',
      () async {
        final cookieJar = CookieJar();
        final manager = LenientCookieManager(cookieJar);
        final requestUri = Uri.parse('https://example.com/start');
        final response = Response<void>(
          requestOptions: RequestOptions(path: requestUri.toString()),
          headers: Headers.fromMap({
            HttpHeaders.setCookieHeader: ['session=kept; Path=/'],
            HttpHeaders.locationHeader: ['http://[invalid'],
          }),
          statusCode: HttpStatus.found,
        );

        await manager.saveCookies(response);

        final cookies = await cookieJar.loadForRequest(requestUri);
        expect(cookies.map((cookie) => cookie.name), contains('session'));
      },
    );

    test(
      'does not copy host-only cookies to a cross-origin redirect',
      () async {
        final cookieJar = CookieJar();
        final manager = LenientCookieManager(cookieJar);
        final originalUri = Uri.parse('https://a.example/start');
        final response = Response<void>(
          requestOptions: RequestOptions(path: originalUri.toString()),
          headers: Headers.fromMap({
            HttpHeaders.setCookieHeader: ['sid=secret; Path=/'],
            HttpHeaders.locationHeader: ['https://b.example/next'],
          }),
          statusCode: HttpStatus.found,
        );

        await manager.saveCookies(response);

        expect(
          (await cookieJar.loadForRequest(
            originalUri,
          )).map((cookie) => cookie.name),
          contains('sid'),
        );
        expect(
          await cookieJar.loadForRequest(Uri.parse('https://b.example/next')),
          isEmpty,
        );
      },
    );

    test(
      'same-origin redirect can load cookies from the original response',
      () async {
        final cookieJar = CookieJar();
        final manager = LenientCookieManager(cookieJar);
        final originalUri = Uri.parse('https://example.com/start');
        final response = Response<void>(
          requestOptions: RequestOptions(path: originalUri.toString()),
          headers: Headers.fromMap({
            HttpHeaders.setCookieHeader: ['sid=kept; Path=/'],
            HttpHeaders.locationHeader: ['/next'],
          }),
          statusCode: HttpStatus.found,
        );

        await manager.saveCookies(response);

        final redirectedCookies = await cookieJar.loadForRequest(
          Uri.parse('https://example.com/next'),
        );
        expect(redirectedCookies.map((cookie) => cookie.name), contains('sid'));
      },
    );
  });
}

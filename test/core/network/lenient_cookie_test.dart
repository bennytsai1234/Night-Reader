import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/network/interceptors/lenient_cookie_manager.dart';

/// Cookie 的值照 Legado `CookieStore.cookieToMap` 當字串切、原樣處理：網站
/// 與書源常寫空白、逗號、雙引號（JSON）這類 `dart:io` Cookie 收不下的值，
/// 不該整條丟掉。中文留得到 Cookie 罐，但 `dart:io` 的標頭只收 ASCII，送不
/// 出去（Legado 的 OkHttp 也一樣擋），所以不進請求的 Cookie 標頭。
void main() {
  Map<String, String> pairs(String header) => {
    for (final pair in header.split('; '))
      pair.substring(0, pair.indexOf('=')): pair.substring(
        pair.indexOf('=') + 1,
      ),
  };

  RequestOptions request(String url, {String? cookie}) {
    final options = RequestOptions(path: url);
    if (cookie != null) options.headers[HttpHeaders.cookieHeader] = cookie;
    return options;
  }

  Response<void> responseWith(String url, List<String> setCookies) =>
      Response<void>(
        requestOptions: RequestOptions(path: url),
        statusCode: 200,
        headers: Headers.fromMap({HttpHeaders.setCookieHeader: setCookies}),
      );

  test('請求自己帶的 Cookie 值保留原文，空值與標頭送不出的中文不送', () async {
    final manager = LenientCookieManager(CookieJar());
    final header = await manager.loadCookies(
      request(
        'https://site.test/x',
        cookie: 'a=x y; b=中文; c={"k":1}; d=b,c; token=',
      ),
    );

    expect(pairs(header), {'a': 'x y', 'c': '{"k":1}', 'd': 'b,c'});
  });

  test('回應的 Set-Cookie 值保留原文，下次請求帶上送得出去的', () async {
    final jar = CookieJar();
    final manager = LenientCookieManager(jar);
    const url = 'https://site.test/x';
    await manager.saveCookies(
      responseWith(url, [
        'a=x y; Path=/',
        'b=中文; Path=/',
        'c={"k":1}; Path=/',
        'd=b,c; Path=/',
      ]),
    );

    expect(pairs(await manager.loadCookies(request(url))), {
      'a': 'x y',
      'c': '{"k":1}',
      'd': 'b,c',
    });
    expect(
      {
        for (final cookie in await jar.loadForRequest(Uri.parse(url)))
          cookie.name: cookieValueForRequest(cookie),
      },
      {'a': 'x y', 'b': '中文', 'c': '{"k":1}', 'd': 'b,c'},
    );
  });

  test('值存進 Cookie 檔再讀回來還是原文', () async {
    final dir = await Directory.systemTemp.createTemp('night_reader_cookie_');
    addTearDown(() => dir.delete(recursive: true));
    const url = 'https://site.test/x';

    final first = LenientCookieManager(
      PersistCookieJar(storage: FileStorage(dir.path)),
    );
    await first.saveCookies(
      responseWith(url, ['a=x y; Path=/', 'b=中文; Path=/']),
    );

    final secondJar = PersistCookieJar(storage: FileStorage(dir.path));
    final second = LenientCookieManager(secondJar);
    expect(pairs(await second.loadCookies(request(url))), {'a': 'x y'});
    expect(
      {
        for (final cookie in await secondJar.loadForRequest(Uri.parse(url)))
          cookie.name: cookieValueForRequest(cookie),
      },
      {'a': 'x y', 'b': '中文'},
    );
  });

  test('同名的 Cookie 以請求帶的為準，罐裡的舊值不附上', () async {
    final manager = LenientCookieManager(CookieJar());
    const url = 'https://site.test/x';
    await manager.saveCookies(responseWith(url, ['a=jar; Path=/']));

    final header = await manager.loadCookies(request(url, cookie: 'a=given'));
    expect(pairs(header), {'a': 'given'});
  });
}

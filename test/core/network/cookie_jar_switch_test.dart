import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/engine/js/extensions/js_blocking_tasks.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/http_client.dart';
import 'package:night_reader/core/services/network_service.dart';

import '../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

/// 網站回的 Cookie 只在書源開了 Cookie 罐時才存下來、下次帶上（同 Legado：
/// `AnalyzeUrl.setCookie` 開了才加 CookieJar 標頭，`HttpHelper` 的網路攔截器
/// 看到這個標頭才 `CookieManager.saveResponse`）。沒開的書源每次都像第一次
/// 來：靠 Cookie 記上次搜尋時間的網站（神话之后的「搜索时间间隔 30 秒」）
/// 不會擋第二次搜尋。
void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();

  late HttpServer server;
  late String baseUrl;

  setUpAll(() async {
    await NetworkService().init(ephemeral: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      if (request.uri.path == '/set') {
        request.response.headers.add(
          HttpHeaders.setCookieHeader,
          'last=${request.uri.queryParameters['v']}; Path=/',
        );
        request.response.write('set');
      } else {
        request.response.write(
          'cookie=${request.headers.value(HttpHeaders.cookieHeader) ?? ''}',
        );
      }
      await request.response.close();
    });
  });

  setUp(() async => NetworkService().cookieJar.deleteAll());

  tearDownAll(() async => server.close(force: true));

  BookSource source({required bool jar}) =>
      BookSource(bookSourceUrl: baseUrl)..enabledCookieJar = jar;

  Future<String> get(String path, BookSource source) async =>
      (await AnalyzeUrl('$baseUrl$path', source: source).getStrResponse()).body;

  test('沒開 Cookie 罐的書源：網站回的 Cookie 不存，下一個請求不帶', () async {
    await get('/set?v=1', source(jar: false));
    expect(await get('/echo', source(jar: false)), 'cookie=');
  });

  test('開了 Cookie 罐的書源：網站回的 Cookie 存起來，下一個請求帶上', () async {
    await get('/set?v=2', source(jar: true));
    expect(await get('/echo', source(jar: true)), 'cookie=last=2');
  });

  test('規則 JS 的 java.get 也照書源的 Cookie 罐開關存', () async {
    Future<void> javaGet(String path, BookSource source) => rawResponse(
      method: 'GET',
      url: '$baseUrl$path',
      headers: {},
      cookieJar: source.enabledCookieJar,
    )();
    await javaGet('/set?v=3', source(jar: false));
    expect(await get('/echo', source(jar: true)), 'cookie=');
    await javaGet('/set?v=4', source(jar: true));
    expect(await get('/echo', source(jar: true)), 'cookie=last=4');
  });

  test('不經書源規則的請求（App 自己抓的）照舊存 Cookie', () async {
    await HttpClient().client.get<String>('$baseUrl/set?v=5');
    expect(await get('/echo', source(jar: false)), 'cookie=last=5');
  });
}

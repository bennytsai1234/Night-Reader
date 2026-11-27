import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/cover_fetcher.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/network_service.dart';

import '../../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

/// 書源的封面照書源抓（Legado `OkHttpStreamFetcher` 照 `sourceOrigin` 組
/// 請求、`ImageUtils.decode` 跑 `coverDecodeJs`）。
void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();
  final skip = quickJsUnavailableReason();

  late HttpServer server;
  late String baseUrl;
  const image = [1, 2, 3, 4];

  setUpAll(() async {
    await NetworkService().init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      // 擋盜連：沒帶 Referer 就 403。
      if (request.headers.value('referer') != '$baseUrl/') {
        request.response.statusCode = HttpStatus.forbidden;
      } else {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(image);
      }
      await request.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  BookSource source({String? header, String? coverDecodeJs}) => BookSource(
    bookSourceUrl: baseUrl,
    bookSourceName: '封面',
    header: header,
    coverDecodeJs: coverDecodeJs,
  );

  test('帶著書源的標頭抓', () async {
    final bytes = await CoverFetcher.fetch(
      source(header: '{"Referer":"$baseUrl/"}'),
      null,
      '$baseUrl/c.png',
    );
    expect(bytes, image);
  }, skip: skip);

  test('網址選項裡的標頭也帶上', () async {
    final bytes = await CoverFetcher.fetch(
      source(),
      null,
      '$baseUrl/c.png,{"headers":{"Referer":"$baseUrl/"}}',
    );
    expect(bytes, image);
  }, skip: skip);

  test('抓到後交給 coverDecodeJs 解', () async {
    final bytes = await CoverFetcher.fetch(
      source(
        header: '{"Referer":"$baseUrl/"}',
        coverDecodeJs:
            'var a = []; for (var i = result.length - 1; '
            'i >= 0; i--) a.push(result[i]); a',
      ),
      null,
      '$baseUrl/c.png',
    );
    expect(bytes, image.reversed.toList());
  }, skip: skip);

  test('沒標頭、不用登入、不用解密、網址沒選項時照一般圖片抓', () {
    expect(CoverFetcher.needsSource(source(), '$baseUrl/c.png'), isFalse);
    expect(
      CoverFetcher.needsSource(
        source(header: '{"Referer":"x"}'),
        '$baseUrl/c.png',
      ),
      isTrue,
    );
    expect(
      CoverFetcher.needsSource(source(), '$baseUrl/c.png,{"headers":{}}'),
      isTrue,
    );
    expect(
      CoverFetcher.needsSource(
        source(coverDecodeJs: 'result'),
        '$baseUrl/c.png',
      ),
      isTrue,
    );
    // 網址帶 {{}}、@js:：Legado 每張封面都經過 AnalyzeUrl，先算出來才抓。
    expect(CoverFetcher.needsSource(source(), '$baseUrl/{{1+1}}.png'), isTrue);
    expect(CoverFetcher.needsSource(source(), '$baseUrl/c.png@JS:1'), isTrue);
  });

  test('只有要跑書源程式時才交給書源 isolate', () {
    expect(
      CoverFetcher.needsScript(
        source(header: '{"Referer":"x"}'),
        '$baseUrl/c.png,{"headers":{"a":"b"}}',
      ),
      isFalse,
    );
    expect(
      CoverFetcher.needsScript(
        source(coverDecodeJs: 'result'),
        '$baseUrl/c.png',
      ),
      isTrue,
    );
    expect(
      CoverFetcher.needsScript(
        source(header: '@js:JSON.stringify({a:1})'),
        '$baseUrl/c.png',
      ),
      isTrue,
    );
    expect(CoverFetcher.needsScript(source(), '$baseUrl/{{1+1}}.png'), isTrue);
    // AnalyzeUrl 的 _jsPattern 不分大小寫。
    expect(CoverFetcher.needsScript(source(), '$baseUrl/c.png@JS:1'), isTrue);
  });

  test('標頭或網址選項解不成 JSON（會當成 JS 跑）時也交給書源 isolate', () {
    expect(
      CoverFetcher.needsScript(
        source(header: '{"Referer": "x" + "y"}'),
        '$baseUrl/c.png',
      ),
      isTrue,
    );
    expect(
      CoverFetcher.needsScript(
        source(),
        '$baseUrl/c.png,{"headers": base + "/"}',
      ),
      isTrue,
    );
    expect(
      CoverFetcher.needsScript(
        source(header: "{Referer:'$baseUrl/'}"),
        '$baseUrl/c.png',
      ),
      isFalse,
      reason: '寬鬆 JSON 照樣解得開',
    );
  });
}

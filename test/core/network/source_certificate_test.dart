import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/js/extensions/js_jsoup_http.dart';
import 'package:night_reader/core/services/network_service.dart';

import '../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

/// 連書源網站不驗憑證（同 Legado：書源的 OkHttp 與 Jsoup 都用
/// `SSLHelper.unsafeTrustManager`），夜讀自己的服務照常驗。測試網站用一張
/// 自簽憑證（`test/fixtures/tls/`），等同過期或不受信任的憑證。
void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();

  late HttpServer server;
  late String baseUrl;

  setUpAll(() async {
    await NetworkService().init(ephemeral: true);
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/tls/self_signed_cert.pem')
      ..usePrivateKey('test/fixtures/tls/self_signed_key.pem');
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    baseUrl = 'https://${server.address.address}:${server.port}';
    server.listen((request) async {
      request.response.write('ok');
      await request.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  test('書源的連線：憑證不受信任照樣連', () async {
    final response = await NetworkService().dio.get<String>('$baseUrl/');
    expect(response.data, 'ok');
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('規則 JS 的 Jsoup 連線：憑證不受信任照樣連', () async {
    final response =
        await jsoupExecute({'url': '$baseUrl/', 'method': 'GET'})()
            as Map<String, Object?>;
    expect(response['code'], 200);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('App 更新的連線：憑證不受信任就不連', () async {
    await expectLater(
      NetworkService().appDio.get<String>('$baseUrl/'),
      throwsA(isA<DioException>()),
    );
  }, timeout: const Timeout(Duration(seconds: 20)));
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/network_service.dart';

import '../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

/// 網站在時限內沒回應就算失敗，不重送（同 Legado：OkHttp 的
/// `retryOnConnectionFailure` 只換下一條路線，請求送出後逾時不再試）。重送
/// 讓一個不回應的網站要等三倍時間：2026-11-13 手機實跑裡一個請求等 46 秒。
void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();

  late HttpServer server;
  late String baseUrl;
  late Duration savedReceiveTimeout;
  var hits = 0;

  setUpAll(() async {
    await NetworkService().init(ephemeral: true);
    final options = NetworkService().dio.options;
    savedReceiveTimeout = options.receiveTimeout!;
    options.receiveTimeout = const Duration(milliseconds: 300);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      hits++;
      await Future<void>.delayed(const Duration(seconds: 2));
      request.response.write('late');
      await request.response.close().catchError((_) {});
    });
  });

  tearDownAll(() async {
    NetworkService().dio.options.receiveTimeout = savedReceiveTimeout;
    await server.close(force: true);
  });

  test('網站逾時不回應：只送一次就失敗', () async {
    final source = BookSource(bookSourceUrl: baseUrl);
    await expectLater(
      AnalyzeUrl('$baseUrl/slow', source: source).getStrResponse(),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );
    expect(hits, 1);
  }, timeout: const Timeout(Duration(seconds: 20)));
}

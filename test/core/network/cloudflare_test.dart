import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/network/cloudflare.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

const _webViewUserAgent = 'NightReaderTestWebView/1.0';

/// 假的瀏覽器：照 [outcome] 回報，記下被叫了幾次。
class _FakeSolver implements CloudflareSolver {
  ClearanceOutcome outcome = ClearanceOutcome.passed;
  int calls = 0;

  @override
  Future<ClearanceResult> solve(Uri uri) async {
    calls++;
    // 讓同時被擋的請求都排到這一次後面。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return switch (outcome) {
      ClearanceOutcome.passed => const ClearanceResult.passed(
        cookies: 'cf_clearance=ok; __cf_bm=b',
        userAgent: _webViewUserAgent,
      ),
      ClearanceOutcome.needsHuman => const ClearanceResult.needsHuman(),
      ClearanceOutcome.failed => const ClearanceResult.failed(),
    };
  }
}

/// 在 worker 裡抓網頁；只捕捉網址（`CODING_STANDARDS.md`）。
Future<String> Function(CancelToken) _fetchTask(String url) =>
    (_) async => (await NetworkService().dio.get<String>(url)).data ?? '';

void main() {
  _MinimalServicesBinding.ensureInitialized();

  late HttpServer server;
  late String baseUrl;
  final solver = _FakeSolver();

  setUpAll(() async {
    await NetworkService().init(ephemeral: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      final cookie = request.headers.value(HttpHeaders.cookieHeader) ?? '';
      final userAgent = request.headers.value(HttpHeaders.userAgentHeader);
      final response = request.response;
      switch (request.uri.path) {
        // 像 Cloudflare 保護的網站：要通行 Cookie，而且瀏覽器標識要和通過
        // 檢查的瀏覽器一樣。
        case final path when path.startsWith('/protected'):
          if (cookie.contains('cf_clearance=ok') &&
              userAgent == _webViewUserAgent) {
            response.write('<p>正文</p>');
          } else {
            response.statusCode = HttpStatus.forbidden;
            response.headers.set('cf-mitigated', 'challenge');
            response.headers.set('server', 'cloudflare');
            response.write(
              '<title>Just a moment...</title>'
              '<script>window._cf_chl_opt={};</script>',
            );
          }
        case '/blocked':
          response.statusCode = HttpStatus.forbidden;
          response.headers.set('cf-ray', '1234');
          response.write('<h1>Sorry, you have been blocked</h1>');
        case '/firewall':
          response.statusCode = HttpStatus.forbidden;
          response.write('您的IP归属地不受信任，已被网站防火墙拦截');
        default:
          response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  });

  setUp(() async {
    CloudflareClearance.reset();
    CloudflareClearance.solver = solver;
    solver
      ..outcome = ClearanceOutcome.passed
      ..calls = 0;
    await NetworkService().cookieJar.deleteAll();
  });

  tearDownAll(() async {
    CloudflareClearance.solver = null;
    await server.close(force: true);
  });

  test('a Cloudflare check is passed in the background and the request '
      'goes through', () async {
    final response = await NetworkService().dio.get<String>(
      '$baseUrl/protected/1',
    );

    expect(response.data, '<p>正文</p>');
    expect(solver.calls, 1);

    // 之後的請求自動帶通行 Cookie 與瀏覽器標識，不再檢查。
    final next = await NetworkService().dio.get<String>('$baseUrl/protected/2');
    expect(next.data, '<p>正文</p>');
    expect(solver.calls, 1);
  });

  test('requests blocked at the same time share one check', () async {
    final pages = await Future.wait([
      for (var i = 0; i < 5; i++)
        NetworkService().dio.get<String>('$baseUrl/protected/$i'),
    ]);

    expect(pages.map((page) => page.data), everyElement('<p>正文</p>'));
    expect(solver.calls, 1);
  });

  test('a site that wants a human click is reported and not retried for '
      'a while', () async {
    solver.outcome = ClearanceOutcome.needsHuman;

    Future<Object?> failure() async {
      try {
        await NetworkService().dio.get<String>('$baseUrl/protected/1');
        return null;
      } on DioException catch (e) {
        return e;
      }
    }

    final first = await failure();
    expect(first, isA<DioException>());
    expect(
      (first! as DioException).error,
      isA<HumanVerificationRequiredException>(),
    );
    expect(userErrorReason(first), '網站要求真人驗證，夜讀不能自動通過');

    await failure();
    expect(solver.calls, 1);
  });

  test('blocked networks are reported without opening a browser', () async {
    for (final path in ['/blocked', '/firewall']) {
      try {
        await NetworkService().dio.get<String>('$baseUrl$path');
        fail('should be blocked');
      } on DioException catch (e) {
        expect(e.error, isA<SiteBlockedException>());
        expect(userErrorReason(e), '網站封鎖了目前的網路，換一個網路才能用');
      }
    }
    expect(solver.calls, 0);
  });

  test('ordinary error pages are left alone', () async {
    try {
      await NetworkService().dio.get<String>('$baseUrl/missing');
      fail('should be 404');
    } on DioException catch (e) {
      expect(e.type, DioExceptionType.badResponse);
      expect(e.response?.statusCode, 404);
    }
    expect(solver.calls, 0);
  });

  group('in a source worker', () {
    late DriftIsolate databaseIsolate;
    late AppDatabase db;
    late SourceWorker worker;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await GetIt.instance.reset();
      databaseIsolate = await DriftIsolate.spawn(NativeDatabase.memory);
      db = AppDatabase.connected(await databaseIsolate.connect());
      registerDatabase(db);
      worker = await SourceWorker.spawn(
        debugName: 'CloudflareTest',
        withDictionaries: false,
        database: Future.value(databaseIsolate),
      );
    });

    tearDownAll(() async {
      worker.kill(StateError('test done'));
      await db.close();
      await databaseIsolate.shutdownAll();
      await GetIt.instance.reset();
    });

    test('the check is passed by the main isolate and its cookies are '
        'shared', () async {
      expect(await worker.run(_fetchTask('$baseUrl/protected/1')), '<p>正文</p>');
      expect(solver.calls, 1);

      // 通行 Cookie 存在主 isolate 的 Cookie 檔，主 isolate 也用得到。
      final main = await NetworkService().dio.get<String>(
        '$baseUrl/protected/2',
      );
      expect(main.data, '<p>正文</p>');
      expect(solver.calls, 1);
    });
  });
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/services/source_debug_service.dart';

import '../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();

  late HttpServer server;
  late String baseUrl;

  setUpAll(() async {
    await NetworkService().init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      switch (request.uri.path) {
        case '/':
          request.response.write('<div class="item"><b>夜讀</b></div>');
        case '/down':
          // Cloudflare 連不到網站主機時回的 521。
          request.response.statusCode = 521;
          request.response.write('error code: 521');
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  Future<List<String>> debug(BookSource source) async {
    final service = SourceDebugService();
    final messages = <String>[];
    final sub = service.logStream.listen((log) => messages.add(log.message));
    await service.startDebug(source, '關鍵字');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    return messages;
  }

  test('logs the URL actually sent, not the search rule', () async {
    // 搜尋網址是 `#` 的書源（例如只列首頁雜誌的書源）抓的是首頁。
    final messages = await debug(
      BookSource(
        bookSourceUrl: '$baseUrl/',
        bookSourceName: '首頁清單',
        searchUrl: '#',
        ruleSearch: SearchRule(bookList: '.item', name: 'b@text'),
      ),
    );

    expect(messages, contains('  搜尋 URL: #'));
    expect(messages, contains('  實際請求: $baseUrl/'));
  });

  test('a failed request shows the reason and the URL', () async {
    final messages = await debug(
      BookSource(
        bookSourceUrl: baseUrl,
        bookSourceName: '網站掛了',
        searchUrl: '/down?q={{key}}',
        ruleSearch: SearchRule(bookList: '.item', name: 'b@text'),
      ),
    );

    expect(messages, contains('❌ 發生錯誤: 伺服器回應錯誤（521）'));
    expect(
      messages,
      contains('  出錯的請求: $baseUrl/down?q=${Uri.encodeQueryComponent('關鍵字')}'),
    );
  });

  test('logs from a cancelled run never reach the next run', () async {
    final service = SourceDebugService();
    final messages = <String>[];
    final sub = service.logStream.listen((log) => messages.add(log.message));
    addTearDown(sub.cancel);

    // 第一輪沒有搜尋網址，會在網路層失敗；不等它結束就取消並開始第二輪。
    final source = BookSource(
      bookSourceUrl: 'https://a.invalid',
      bookSourceName: '甲',
    );
    final first = service.startDebug(source, '關鍵字');
    service.cancel();
    final second = service.startDebug(
      BookSource(bookSourceUrl: 'https://b.invalid', bookSourceName: '乙'),
      '關鍵字',
    );
    await Future.wait([first, second]);

    await Future<void>.delayed(Duration.zero);
    final secondStart = messages.indexOf('⇒開始除錯書源: 乙');
    expect(secondStart, isNonNegative);
    // 第一輪取消後才回來的錯誤不會混進第二輪。
    expect(
      messages.skip(secondStart).where((m) => m.startsWith('❌')),
      hasLength(1),
    );
  });
}

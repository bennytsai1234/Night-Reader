import 'dart:io' hide HttpClient;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/network/http_client.dart';
import 'package:night_reader/core/network/network_service.dart';
import 'package:night_reader/core/source/source_debug_service.dart';

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
        case '/moved':
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, '/');
        case '/empty':
          // 2026-11-13 酷匠阅读的搜尋介面回 0 位元組。
          break;
        case '/s-var':
          request.response.write(
            '<div class="item"><a href="/b-var">變數書</a><i>42</i></div>',
          );
        case '/b-var':
          request.response.write('<h1>詳情</h1>');
        case '/toc-vol':
          request.response.write(
            '<div class="ch"><span class="v">true</span><span class="n">卷一</span></div>'
            '<div class="ch"><span class="n"><a href="/c1">第一章</a></span></div>'
            '<div class="ch"><span class="n"><a href="/c2">第二章</a></span></div>',
          );
        case '/c1' || '/c2':
          request.response.write('<p class="t">正文</p>');
        case '/moved-down':
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, '/down');
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

  test('redirects are logged hop by hop', () async {
    final messages = await debug(
      BookSource(
        bookSourceUrl: baseUrl,
        bookSourceName: '搬家了',
        searchUrl: '/moved',
        ruleSearch: SearchRule(bookList: '.item', name: 'b@text'),
      ),
    );

    final requests = messages.where((m) => m.startsWith('  實際請求: '));
    expect(requests.take(2), [
      '  實際請求: $baseUrl/moved',
      '  實際請求: $baseUrl/（轉址）',
    ]);
  });

  test('a failure after a redirect shows the URL it was sent to', () async {
    final messages = await debug(
      BookSource(
        bookSourceUrl: baseUrl,
        bookSourceName: '搬去的地方掛了',
        searchUrl: '/moved-down',
        ruleSearch: SearchRule(bookList: '.item', name: 'b@text'),
      ),
    );

    expect(messages, contains('❌ 發生錯誤: 伺服器回應錯誤（521）'));
    expect(messages, contains('  出錯的請求: $baseUrl/down'));
  });

  // 書單規則抓不到東西時照詳情頁解析（Legado BookList.kt）。酷匠阅读的搜尋
  // 回空白，照詳情頁解析時詳情頁的 JS 出錯；沒寫這一行，看起來像詳情頁的
  // 規則壞了，AI 兩輪說看不懂。
  test('an empty book list says it falls back to the detail page', () async {
    final messages = await debug(
      BookSource(
        bookSourceUrl: baseUrl,
        bookSourceName: '搜尋回空白',
        searchUrl: '/empty',
        ruleSearch: SearchRule(bookList: '.item', name: 'b@text'),
        ruleBookInfo: BookInfoRule(name: '@js:JSON.parse(result).name'),
      ),
    );

    final fallback = messages.indexOf('└列表為空,按詳情頁解析');
    expect(fallback, isNonNegative, reason: messages.join('\n'));
    expect(
      messages.indexWhere((m) => m.startsWith('❌')),
      greaterThan(fallback),
      reason: messages.join('\n'),
    );
  }, skip: quickJsUnavailableReason());

  // Legado Debug.kt：搜尋結果接到詳情用 `searchBooks[0].toBook()`，搜尋規則
  // 存的變數跟著帶過去。
  test('the detail step keeps the variables the search rules stored', () async {
    final messages = await debug(
      BookSource(
        bookSourceUrl: baseUrl,
        bookSourceName: '搜尋存變數',
        searchUrl: '/s-var',
        ruleSearch: SearchRule(
          bookList: '.item',
          name: 'a@text',
          bookUrl: 'a@href@put:{bid:i@text}',
        ),
        // 寫了 canReName，詳情頁讀到的變數才會換上書名（同 Legado）。
        ruleBookInfo: BookInfoRule(name: '@get:{bid}', canReName: '1'),
      ),
    );

    expect(messages, contains('︽詳情頁解析完成: 42'), reason: messages.join('\n'));
  });

  // Legado Debug.kt：目錄先拿掉沒有網址的卷名（網址是「卷名＋序號」的那種），
  // 第一章與下一章都從拿掉之後的取。
  test('the content step skips volume titles without a URL', () async {
    final service = SourceDebugService();
    final messages = <String>[];
    final sub = service.logStream.listen((log) => messages.add(log.message));
    await service.startDebug(
      BookSource(
        bookSourceUrl: baseUrl,
        bookSourceName: '有分卷',
        ruleToc: TocRule(
          chapterList: '.ch',
          chapterName: 'class.n@text',
          chapterUrl: 'tag.a@href',
          isVolume: 'class.v@text',
        ),
        ruleContent: ContentRule(content: 'class.t@text'),
      ),
      '++$baseUrl/toc-vol',
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(messages, contains('  首章: 第一章'), reason: messages.join('\n'));
    expect(messages, contains('︾開始解析正文頁: 第一章'), reason: messages.join('\n'));
    expect(messages, contains('  正文 URL: $baseUrl/c1'));
    expect(messages, contains('  下一章 URL: $baseUrl/c2'));
  });

  test('requests sent straight through Dio are recorded', () async {
    // 規則 JS 的 `java.get`、`java.post` 不經過 AnalyzeUrl，直接用 Dio 送。
    final log = RequestLog();
    await log.run(() => HttpClient().client.post<String>('$baseUrl/'));

    expect(log.lines, ['POST $baseUrl/']);
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

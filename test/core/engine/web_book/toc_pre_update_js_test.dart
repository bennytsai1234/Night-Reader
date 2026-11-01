import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/web_book/web_book_service.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/network_service.dart';

import '../../../test_helper.dart';

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
  final skip = quickJsUnavailableReason();

  late HttpServer server;
  late String baseUrl;

  // 書上記的目錄網址已經失效，詳情頁指向新的目錄（顶点小说這類目錄網址
  // 會變的書源）。
  setUpAll(() async {
    await NetworkService().init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      switch (request.uri.path) {
        case '/book':
          request.response.write(
            '<html><body><a class="toc" href="/toc/new">目錄</a></body></html>',
          );
        case '/toc/new':
          request.response.write(
            '<html><body><div class="list">'
            '<a href="/c/1.html">第一章</a><a href="/c/2.html">第二章</a>'
            '</div></body></html>',
          );
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  BookSource source() => BookSource.fromJson({
    'bookSourceName': '測試',
    'bookSourceUrl': baseUrl,
    'ruleBookInfo': {'tocUrl': 'class.toc@href'},
    'ruleToc': {
      'preUpdateJs': 'java.refreshTocUrl()',
      'chapterList': 'class.list@a',
      'chapterName': 'text',
      'chapterUrl': 'href',
    },
  });

  test('java.refreshTocUrl() in preUpdateJs reads the TOC from the details '
      'page again', () async {
    final chapters = await WebBook.getChapterListAwait(
      source(),
      Book(
        bookUrl: '$baseUrl/book',
        tocUrl: '$baseUrl/toc/old',
        origin: baseUrl,
        name: '書',
        author: '作者',
      ),
    );

    expect(chapters.map((c) => c.title), ['第一章', '第二章']);
  }, skip: skip);

  test('java.refreshTocUrl() outside preUpdateJs is an error, as in '
      'Legado', () {
    final rule = AnalyzeRule(source: source());
    expect(() => rule.evalJS('java.refreshTocUrl()', null), throwsA(anything));
    rule.dispose();
  }, skip: skip);
}

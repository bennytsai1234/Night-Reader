import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/complete_content_fetcher.dart';
import 'package:night_reader/core/engine/web_book/web_book_service.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
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

  late HttpServer server;
  late String baseUrl;
  final longText = '正文的一段話，' * 60;

  // /free 第一頁免費、第二頁要登入；/linked 頁首有登入連結但讀得到。
  setUpAll(() async {
    await NetworkService().init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      String page(String content, {String? next}) =>
          '<html><body><header><a href="/login">請先登錄</a></header>'
          '<div id="content">$content</div>'
          '${next == null ? '' : '<a class="next" href="$next">下一頁</a>'}'
          '</body></html>';
      request.response.headers.contentType = ContentType.html;
      switch (request.uri.path) {
        case '/free':
          request.response.write(page(longText, next: '/free/2'));
        case '/free/2':
          request.response.write(page(''));
        case '/linked':
          request.response.write(page(longText));
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  final source = BookSource.fromJson({
    'bookSourceName': '測試',
    'bookSourceUrl': 'http://local.test',
    'ruleContent': {
      'content': 'id.content@text',
      'nextContentUrl': 'class.next@href',
    },
  });
  final book = Book(
    bookUrl: 'http://local.test/book',
    origin: 'http://local.test',
    name: '書',
  );
  BookChapter chapter(String path) =>
      BookChapter(url: '$baseUrl$path', title: '第一章');

  // 第一頁免費、後面要登入：不能把第一頁當成一整章（ADR 0038）。
  test('a later page behind a login wall fails the whole chapter', () async {
    for (final fetch in [
      () => WebBook.getContentAwait(source, book, chapter('/free')),
      () => CompleteContentFetcher.fetch(source, book, chapter('/free')),
    ]) {
      await expectLater(fetch(), throwsA(isA<LoginCheckException>()));
    }
  });

  test(
    'a login link in the page header does not fail a readable chapter',
    () async {
      expect(
        await WebBook.getContentAwait(source, book, chapter('/linked')),
        contains('正文的一段話'),
      );
      expect(
        await CompleteContentFetcher.fetch(source, book, chapter('/linked')),
        contains('正文的一段話'),
      );
    },
  );
}

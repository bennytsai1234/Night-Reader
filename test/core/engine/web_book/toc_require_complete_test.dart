import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  late HttpServer server;
  late String baseUrl;

  // 目錄首頁列出兩個分頁（並行抓取），第三頁的連線會被直接切斷。
  setUpAll(() async {
    await NetworkService().init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      String page(List<String> chapters, {List<String> next = const []}) =>
          '<html><body><div class="list">'
          '${chapters.map((c) => '<a href="/c/$c.html">$c</a>').join()}'
          '</div><div class="next">'
          '${next.map((n) => '<a href="$n">下一頁</a>').join()}'
          '</div></body></html>';
      request.response.headers.contentType = ContentType.html;
      switch (request.uri.path) {
        case '/toc':
          request.response.write(
            page(['第一章', '第二章'], next: ['/toc/2', '/toc/3']),
          );
        case '/toc/2':
          request.response.write(page(['第三章']));
        case '/toc/3':
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.destroy();
          return;
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
    'ruleToc': {
      'chapterList': 'class.list@a',
      'chapterName': 'a@text',
      'chapterUrl': 'a@href',
      'nextTocUrl': 'class.next@a@href',
    },
  });

  Book book() => Book(
    bookUrl: '$baseUrl/book',
    tocUrl: '$baseUrl/toc',
    origin: baseUrl,
    name: '書',
    author: '作者',
  );

  test('a failed TOC page is skipped by default', () async {
    final chapters = await WebBook.getChapterListAwait(source(), book());

    expect(chapters.map((c) => c.title).toSet(), {'第一章', '第二章', '第三章'});
  });

  test('requireComplete fails when any TOC page fails', () async {
    await expectLater(
      WebBook.getChapterListAwait(source(), book(), requireComplete: true),
      throwsA(anything),
    );
  });
}

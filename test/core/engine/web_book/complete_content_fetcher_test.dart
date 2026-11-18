import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/complete_content_fetcher.dart';
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

  // /long/N 共 120 頁，每頁指向下一頁；/loop/1、/loop/2 互相指。
  setUpAll(() async {
    await NetworkService().init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      String page(String content, String? next) =>
          '<html><body><div id="content">$content</div>'
          '${next == null ? '' : '<a class="next" href="$next">下一頁</a>'}'
          '</body></html>';
      request.response.headers.contentType = ContentType.html;
      final parts = request.uri.pathSegments;
      final n = int.tryParse(parts.lastOrNull ?? '') ?? 0;
      switch (parts.firstOrNull) {
        case 'long':
          request.response.write(
            page('第$n頁的正文。', n < 120 ? '/long/${n + 1}' : null),
          );
        case 'loop':
          request.response.write(page('第$n頁的正文。', '/loop/${3 - n}'));
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

  test('a chapter split into more than 100 pages is read to the end, '
      'like Legado', () async {
    final content = await CompleteContentFetcher.fetch(
      source,
      book,
      chapter('/long/1'),
    );
    expect(content, contains('第1頁的正文'));
    expect(content, contains('第120頁的正文'));
  });

  test(
    'a next-page link back to a page already read stops the chapter',
    () async {
      final content = await CompleteContentFetcher.fetch(
        source,
        book,
        chapter('/loop/1'),
      );
      expect(content, contains('第1頁的正文'));
      expect(content, contains('第2頁的正文'));
    },
  );
}

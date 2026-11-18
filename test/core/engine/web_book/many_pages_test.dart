import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/web_book_service.dart';
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

/// 目錄、正文分很多頁時照 Legado 抓到沒有下一頁（或下一頁抓過了）為止，
/// 不在某個頁數停下、把後面的當成沒有。
void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();

  const pages = 101;
  late HttpServer server;
  late String baseUrl;

  setUpAll(() async {
    await NetworkService().init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      String toc(List<int> chapters, {List<String> next = const []}) =>
          '<html><body><div class="list">'
          '${chapters.map((c) => '<a href="/c/$c.html">第$c章</a>').join()}'
          '</div><div class="next">'
          '${next.map((n) => '<a href="$n">下一頁</a>').join()}'
          '</div></body></html>';
      final segments = request.uri.pathSegments;
      final n = segments.length > 1 ? int.tryParse(segments[1]) : null;
      request.response.headers.contentType = ContentType.html;
      switch (segments.firstOrNull) {
        // 一頁一章，每頁連到下一頁。
        case 'chain' when n != null:
          request.response.write(
            toc([n], next: n < pages ? ['/chain/${n + 1}'] : const []),
          );
        // 第一頁一次列出後面所有分頁。
        case 'list':
          request.response.write(
            toc([0], next: [for (var i = 1; i <= pages; i++) '/page/$i']),
          );
        case 'page' when n != null:
          request.response.write(toc([n]));
        // 正文一頁一段，每頁連到下一頁。
        case 'content' when n != null:
          final next = n < pages
              ? '<a id="next" href="/content/${n + 1}">下一頁</a>'
              : '';
          request.response.write(
            '<html><body><div id="content">第$n段</div>$next</body></html>',
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
    'ruleToc': {
      'chapterList': 'class.list@a',
      'chapterName': 'a@text',
      'chapterUrl': 'a@href',
      'nextTocUrl': 'class.next@a@href',
    },
    'ruleContent': {
      'content': 'id.content@text',
      'nextContentUrl': 'id.next@href',
    },
  });

  Book book(String tocPath) => Book(
    bookUrl: '$baseUrl/book',
    tocUrl: '$baseUrl$tocPath',
    origin: baseUrl,
    name: '書',
    author: '作者',
  );

  for (final requireComplete in [false, true]) {
    test('目錄一頁連一頁 $pages 頁，每一頁都抓（requireComplete: $requireComplete）', () async {
      final chapters = await WebBook.getChapterListAwait(
        source(),
        book('/chain/1'),
        requireComplete: requireComplete,
      );
      expect(chapters, hasLength(pages));
      expect(chapters.last.title, '第$pages章');
    });

    test(
      '目錄第一頁列出 $pages 個分頁，每一頁都抓（requireComplete: $requireComplete）',
      () async {
        final chapters = await WebBook.getChapterListAwait(
          source(),
          book('/list'),
          requireComplete: requireComplete,
        );
        expect(chapters, hasLength(pages + 1));
        expect(chapters.last.title, '第$pages章');
      },
    );
  }

  test('正文一頁連一頁 $pages 頁，每一頁都抓', () async {
    final content = await WebBook.getContentAwait(
      source(),
      book('/chain/1'),
      BookChapter(title: '第一章', url: '$baseUrl/content/1', bookUrl: 'b'),
    );
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty);
    expect(lines, hasLength(pages));
    expect(lines.last.trim(), '第$pages段');
  });
}

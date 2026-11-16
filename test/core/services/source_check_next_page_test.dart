import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/complete_content_fetcher.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/services/source_check_isolate.dart';

import '../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() =>
      _instance ??= _MinimalServicesBinding();
}

/// 搜尋、詳情、目錄照 [toc] 給，正文照書源的規則真的去本機網站抓
/// （[CompleteContentFetcher]），請求經過真的網路層記進校驗的紀錄。
class _SiteService extends BookSourceService {
  _SiteService(this.toc);

  final List<BookChapter> toc;

  @override
  Future<List<SearchBook>> searchBooks(
    BookSource source,
    String key, {
    int page = 1,
    bool Function(String name, String author)? filter,
    bool Function(int size)? shouldBreak,
    CancelToken? cancelToken,
  }) async => key == nonsenseKeyword
      ? const []
      : [
          SearchBook(
            bookUrl: '${source.bookSourceUrl}/book',
            name: '書',
            origin: source.bookSourceUrl,
          ),
        ];

  @override
  Future<Book> getBookInfo(
    BookSource source,
    Book book, {
    CancelToken? cancelToken,
  }) async => book;

  @override
  Future<List<BookChapter>> getChapterList(
    BookSource source,
    Book book, {
    int? chapterLimit,
    int? pageConcurrency,
    CancelToken? cancelToken,
    bool requireComplete = false,
  }) async => toc;

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) => CompleteContentFetcher.fetch(
    source,
    book,
    chapter,
    nextChapterUrl: nextChapterUrl,
    pageConcurrency: pageConcurrency,
  );
}

const _config = IsolateCheckConfig(
  keyword: '書',
  timeoutSeconds: 10,
  checkSearch: true,
  checkDiscovery: false,
  checkInfo: true,
  checkCategory: true,
  checkContent: true,
);

void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();

  late HttpServer server;
  late String site;
  final half = '前半章的一段話，' * 40;

  // /c/N.html 是第 N 章的前半，後半在 /c/N_2.html（下書網 2026-11-12 的
  // 結構）；/f/ 是腐文小说那種一頁一章，目錄的下一章就是 1_2.html。
  setUpAll(() async {
    await NetworkService().init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    site = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      final path = request.uri.path;
      final match = RegExp(r'^/([cf])/(\d+)(_2)?\.html$').firstMatch(path);
      request.response.headers.contentType = ContentType.html;
      if (match == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        final (folder, n, second) = (
          match.group(1)!,
          match.group(2)!,
          match.group(3) != null,
        );
        final next = second ? null : '/$folder/${n}_2.html';
        request.response.write(
          '<html><body><div id="content">'
          '${second ? '後半章的一段話，' * 40 : half}第$n章'
          '</div><a href="/$folder/${int.parse(n) - 1}.html">上一章</a>'
          '${next == null ? '' : '<a href="$next">下一页</a>'}'
          '</body></html>',
        );
      }
      await request.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  BookSource source({String? next}) => BookSource(
    bookSourceUrl: site,
    bookSourceName: '分頁的網站',
    searchUrl: '/search?q={{key}}',
    ruleContent: ContentRule(content: 'id.content@text', nextContentUrl: next),
  );

  List<BookChapter> chapters(String folder, List<String> files) => [
    for (final (i, file) in files.indexed)
      BookChapter(url: '$site/$folder/$file', title: '第${i + 1}章', index: i),
  ];

  Future<SourceCheckIsolateResult> check(
    BookSource source,
    List<BookChapter> toc,
  ) => SourceChecker(
    source: source,
    config: _config,
    service: _SiteService(toc),
    networkCheck: () async => true,
  ).run();

  final paged = ['1.html', '2.html', '3.html'];

  test('a source without a next-page rule reads only the first page of each '
      'chapter and its content is marked broken', () async {
    final result = await check(source(), chapters('c', paged));

    expect(result.isHealthy, isFalse, reason: result.logs.join('\n'));
    final checked = BookSource.fromJson(result.updatedSourceJson);
    expect(checked.groupTags, contains(contentBrokenSourceGroupTag));
    expect(result.message, contains('只抓到第一頁'));
    expect(result.message, contains('$site/c/1_2.html'));
    expect(result.message, contains('書源沒有下一頁規則'));
  });

  test('a next-page rule that finds no link is caught too', () async {
    // 2026-11-13 下書網：nextContentUrl 的選擇器在頁面上抓不到連結。
    final result = await check(
      source(next: 'class.next@href'),
      chapters('c', paged),
    );

    expect(result.isHealthy, isFalse, reason: result.logs.join('\n'));
    expect(result.message, contains('下一頁規則（nextContentUrl）沒有抓到它'));
  });

  test('a rule that follows the next page is healthy', () async {
    final result = await check(
      source(next: 'text.下一页@href'),
      chapters('c', paged),
    );

    expect(result.isHealthy, isTrue, reason: result.logs.join('\n'));
  });

  test('a "next page" that the table of contents lists as the next chapter '
      'is not missing', () async {
    // 腐文小说：一頁一章，第二章就是 1_2.html，引擎照 Legado 不把下一章當
    // 同一章的下一頁抓；沒有下一頁規則也一樣。
    for (final next in [null, 'text.下一页@href']) {
      final result = await check(
        source(next: next),
        chapters('f', ['1.html', '1_2.html', '2.html']),
      );

      expect(result.isHealthy, isTrue, reason: result.logs.join('\n'));
    }
  });
}

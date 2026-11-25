import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/complete_content_fetcher.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/backstage_webview.dart';
import 'package:night_reader/core/network/network_service.dart';

import '../../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

/// 正文規則裡 `content` 以外的欄位，同 Legado `WebBook.getContentAwait`、
/// `BookContent.analyzeContent`：用網頁抓正文時跑的 `webJs`、等網頁載入的資源
/// `sourceRegex`，與從正文頁取章名的 `title`。
void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();

  late HttpServer server;
  late String baseUrl;
  final hits = <String>[];

  setUpAll(() async {
    await NetworkService().init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      hits.add(request.uri.path);
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        request.uri.path.startsWith('/echo/')
            ? '<html><body><div id="content">'
                  '${request.uri.path.substring(6)}</div></body></html>'
            : request.uri.path == '/locked'
            ? '<html><body><h1>請先登入</h1>'
                  '<div id="content">請先登錄後閱讀</div></body></html>'
            : '<html><body><h1>第1章 開端</h1>'
                  '<div id="content">第一章的正文。</div></body></html>',
      );
      await request.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  final book = Book(
    bookUrl: 'http://local.test/book',
    origin: 'http://local.test',
    name: '書',
  );

  group('webJs and sourceRegex of the content rule', () {
    final requests = <BackstageWebView>[];
    setUp(() {
      requests.clear();
      BackstageWebView.delegate = (request) async {
        requests.add(request);
        return {'url': request.url, 'body': '網頁跑出來的正文'};
      };
    });
    tearDown(() => BackstageWebView.delegate = null);

    BookSource source() => BookSource.fromJson({
      'bookSourceName': '測試',
      'bookSourceUrl': 'http://local.test',
      'ruleContent': {
        'content': '@js:result',
        'webJs': 'getText()',
        'sourceRegex': r'.*\.m3u8',
      },
    });

    test('go to the browser like Legado', () async {
      final content = await CompleteContentFetcher.fetch(
        source(),
        book,
        BookChapter(url: '$baseUrl/c/1,{"webView":true}', title: '第1章'),
      );
      expect(requests, hasLength(1));
      expect(requests.single.javaScript, 'getText()');
      expect(requests.single.sourceRegex, r'.*\.m3u8');
      expect(content, contains('網頁跑出來的正文'));
    });

    test("the chapter URL's own webJs wins", () async {
      await CompleteContentFetcher.fetch(
        source(),
        book,
        BookChapter(
          url: '$baseUrl/c/1,{"webView":true,"webJs":"fromUrl()"}',
          title: '第1章',
        ),
      );
      expect(requests.single.javaScript, 'fromUrl()');
    });
  });

  group('title of the content rule', () {
    BookSource source(String? title) => BookSource.fromJson({
      'bookSourceName': '測試',
      'bookSourceUrl': 'http://local.test',
      'ruleContent': {'content': 'id.content@text', 'title': ?title},
    });

    test('replaces the chapter title like Legado', () async {
      final chapter = BookChapter(url: '$baseUrl/c/1', title: '第1章');
      await CompleteContentFetcher.fetch(source('h1@text'), book, chapter);
      expect(chapter.title, '第1章 開端');
    });

    // 整章抓完、沒被登入牆擋住才換：失敗時呼叫端照樣存回章節欄位，目錄
    // 不能變成登入提示。
    test('a chapter behind a login wall keeps its title', () async {
      final chapter = BookChapter(url: '$baseUrl/locked', title: '第1章');
      await expectLater(
        CompleteContentFetcher.fetch(source('h1@text'), book, chapter),
        throwsA(isA<LoginCheckException>()),
      );
      expect(chapter.title, '第1章');
    });

    test('an empty or broken title rule keeps the title', () async {
      final empty = BookChapter(url: '$baseUrl/c/1', title: '第1章');
      await CompleteContentFetcher.fetch(source('h2@text'), book, empty);
      expect(empty.title, '第1章');

      final broken = BookChapter(url: '$baseUrl/c/1', title: '第1章');
      final content = await CompleteContentFetcher.fetch(
        source('@js:throw "壞了"'),
        book,
        broken,
      );
      expect(broken.title, '第1章');
      expect(content, contains('第一章的正文'));
    });
  });

  // 同 Legado `WebBook.getContentAwait`：章節那一頁的請求帶著這一章，網址裡
  // 的規則讀 `title` 是章名，`java.put` 存進這一章。
  group('the chapter request carries the chapter', () {
    final source = BookSource.fromJson({
      'bookSourceName': '測試',
      'bookSourceUrl': 'http://local.test',
      'ruleContent': {'content': 'id.content@text'},
    });

    test('java.get("title") in the chapter URL is the chapter title', () async {
      final content = await CompleteContentFetcher.fetch(
        source,
        Book(bookUrl: 'http://local.test/book', origin: 'http://local.test'),
        BookChapter(url: "$baseUrl/echo/{{java.get('title')}}", title: 'T1'),
      );
      expect(content, contains('T1'));
    });

    test('java.put in the chapter URL stores into the chapter', () async {
      final book = Book(
        bookUrl: 'http://local.test/book',
        origin: 'http://local.test',
      );
      final chapter = BookChapter(
        url: "$baseUrl/echo/a@js:java.put('k', 'v'); result",
        title: 'T1',
      );
      await CompleteContentFetcher.fetch(source, book, chapter);
      expect(chapter.getVariable('k'), 'v');
      expect(book.getVariable('k'), isEmpty);
    });
  });

  // 同 Legado `WebBook.getContentAwait`：章節網址就是書的網址、目錄頁還在手上
  // （詳情頁就是目錄頁時存著的那一頁）就直接解析，不再抓一次。
  group('a chapter whose URL is the book URL', () {
    final source = BookSource.fromJson({
      'bookSourceName': '測試',
      'bookSourceUrl': 'http://local.test',
      'ruleContent': {'content': 'id.content@text'},
    });
    setUp(hits.clear);

    test('parses the stored TOC page without fetching it again', () async {
      final book = Book(bookUrl: '$baseUrl/one', origin: 'http://local.test')
        ..tocHtml = '<html><body><div id="content">存著的那頁</div></body></html>';
      final content = await CompleteContentFetcher.fetch(
        source,
        book,
        BookChapter(url: book.bookUrl, title: '全文'),
      );
      expect(content, contains('存著的那頁'));
      expect(hits, isEmpty);
    });

    test('fetches it when no TOC page is stored', () async {
      final book = Book(bookUrl: '$baseUrl/one', origin: 'http://local.test');
      final content = await CompleteContentFetcher.fetch(
        source,
        book,
        BookChapter(url: book.bookUrl, title: '全文'),
      );
      expect(content, contains('第一章的正文'));
      expect(hits, ['/one']);
    });
  });
}

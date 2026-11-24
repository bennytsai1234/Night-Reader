import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/complete_content_fetcher.dart';
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

  setUpAll(() async {
    await NetworkService().init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<html><body><h1>第1章 開端</h1>'
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
}

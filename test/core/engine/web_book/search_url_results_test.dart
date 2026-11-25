import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/web_book/web_book_service.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/network/network_service.dart';

import '../../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

/// 搜尋網址帶給搜尋結果的東西，照 Legado `WebBook.searchBookAwait` 與
/// `BookList`：網址裡存的變數每本書都帶著；搜尋直接回詳情頁、沒有轉址時，
/// 書的網址是搜尋網址（含 POST 選項）。
void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();
  final skip = quickJsUnavailableReason();

  late HttpServer server;
  late String baseUrl;
  var postRequests = 0;

  setUpAll(() async {
    await NetworkService().init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      switch (request.uri.path) {
        case '/list':
          request.response.write(
            '<div class="item"><a href="/book/1">甲書</a></div>'
            '<div class="item"><a href="/book/2">乙書</a></div>',
          );
        case '/post':
          // POST 搜尋，網站直接給唯一一本的詳情頁；GET 同一條網址是別的
          // 內容，重抓會拿到另一頁。
          postRequests++;
          if (request.method == 'POST') {
            await request.drain<void>();
            request.response.write(
              '<h1 class="title">詳情書名</h1>'
              '<div class="intro">搜尋那一頁的簡介</div>',
            );
          } else {
            request.response.write('<h1 class="title">重抓的另一頁</h1>');
          }
        case '/jump':
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set('location', '/book/9');
        case '/book/9':
          request.response.write('<h1>轉址的書</h1>');
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  BookSource source(String searchUrl) => BookSource.fromJson({
    'bookSourceName': '搜尋',
    'bookSourceUrl': baseUrl,
    'searchUrl': searchUrl,
    'ruleSearch': {
      'bookList': 'class.item',
      'name': 'tag.a@text',
      'bookUrl': 'tag.a@href',
    },
    'ruleBookInfo': {'name': 'tag.h1@text'},
  });

  test('搜尋網址的 JS 存的變數，每本搜尋結果都帶著', () async {
    final books = await WebBook.searchBookAwait(
      source('@js:java.put("token", "t-" + key); "/list?k=" + key'),
      '書',
    );
    expect(books.map((b) => b.name), ['甲書', '乙書']);
    for (final book in books) {
      expect(book.getVariable('token'), 't-書');
    }
  }, skip: skip);

  test('POST 搜尋直接給詳情頁：書的網址是搜尋網址，選項留著', () async {
    final books = await WebBook.searchBookAwait(
      source('/post,{"method":"POST","body":"k={{key}}"}'),
      '書',
    );
    expect(books.map((b) => b.name), ['詳情書名']);
    expect(
      books.single.bookUrl,
      '$baseUrl/post,{"method":"POST","body":"k=書"}',
    );
  }, skip: skip);

  test('轉址到詳情頁時，書的網址是轉址後的網址', () async {
    final books = await WebBook.searchBookAwait(source('/jump?k={{key}}'), '書');
    expect(books.map((b) => b.name), ['轉址的書']);
    expect(books.single.bookUrl, '$baseUrl/book/9');
  }, skip: skip);

  test('搜尋直接回詳情頁時，打開書用搜尋那一頁，不再連網', () async {
    // 同一條網址 GET 拿到的是另一頁：重抓會打開錯的書（同 Legado 把
    // 搜尋回的詳情頁留在 SearchBook.infoHtml）。
    final before = postRequests;
    final detailSource = BookSource.fromJson({
      'bookSourceName': '詳情',
      'bookSourceUrl': baseUrl,
      'searchUrl': '/post,{"method":"POST","body":"k={{key}}"}',
      'ruleSearch': {'bookList': 'class.item', 'name': 'tag.a@text'},
      'ruleBookInfo': {'name': 'tag.h1@text', 'intro': 'class.intro@text'},
    });
    final found = await WebBook.searchBookAwait(detailSource, '書');
    expect(found.single.infoHtml, contains('搜尋那一頁的簡介'));

    final info = await WebBook.getBookInfoAwait(
      detailSource,
      found.single.toBook(),
    );
    expect(info.name, '詳情書名');
    expect(info.intro, '搜尋那一頁的簡介');
    expect(postRequests, before + 1);
  });
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/engine/web_book/complete_content_fetcher.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/network/network_service.dart';

import '../../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

/// 書架上這本書存著的目錄：第 i 章是 /book/i。
class _StoredChapters extends Fake implements ChapterDao {
  _StoredChapters(this.baseUrl, this.count);

  final String baseUrl;
  final int count;

  @override
  Future<BookChapter?> getChapter(String bookUrl, int index) async =>
      index < count
      ? BookChapter(
          url: '$baseUrl/book/$index',
          title: '第$index章',
          index: index,
        )
      : null;
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
        case 'book':
          // 每章一頁，「下一頁」的規則抓到的其實是下一章。
          request.response.write(page('第$n章的正文。', '/book/${n + 1}'));
        case 'loop':
          request.response.write(page('第$n頁的正文。', '/loop/${3 - n}'));
        case 'start':
          // 章節網址轉到真正的第一頁；第二頁的「下一頁」又連回第一頁。
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, '/p/1');
        case 'p':
          request.response.write(
            n == 1 ? page('甲段正文。', '/p/2') : page('乙段正文。', '/p/1'),
          );
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

  test('with no next chapter given, the stored table of contents stops the '
      'chapter at the next one, like Legado', () async {
    // 書架自動下載、漫畫與有聲書沒傳下一章網址；Legado 這時查這本書存著的
    // 目錄（下一章，沒有就第一章）。
    GetIt.I.registerSingleton<ChapterDao>(_StoredChapters(baseUrl, 150));
    addTearDown(() => GetIt.I.unregister<ChapterDao>());
    final content = await CompleteContentFetcher.fetch(
      source,
      book,
      BookChapter(url: '$baseUrl/book/3', title: '第3章', index: 3),
    );
    expect(content, contains('第3章的正文'));
    expect(content, isNot(contains('第4章的正文')));
  });

  // 同 Legado `BookContent`：已抓的網址從第一頁轉址後的網址算起。
  test('a next-page link back to where the chapter url redirected does not '
      'read that page again', () async {
    final content = await CompleteContentFetcher.fetch(
      source,
      book,
      chapter('/start/0'),
    );
    expect('甲段'.allMatches(content), hasLength(1));
    expect('乙段'.allMatches(content), hasLength(1));
  });

  // 同 Legado `WebBook.getContentAwait`：正文規則空白時正文是章節網址
  // （有聲書的章節網址本身是音訊），不去抓。
  test('a blank content rule gives the chapter url without fetching', () async {
    for (final ruleContent in [
      null,
      {'content': ' '},
    ]) {
      final blank = BookSource.fromJson({
        'bookSourceName': '有聲',
        'bookSourceUrl': 'http://local.test',
        'bookSourceType': 1,
        'ruleContent': ?ruleContent,
      });
      expect(
        await CompleteContentFetcher.fetch(
          blank,
          book,
          BookChapter(url: 'http://unreachable.invalid/a.mp3', title: '第一集'),
        ),
        'http://unreachable.invalid/a.mp3',
      );
    }
  });
}

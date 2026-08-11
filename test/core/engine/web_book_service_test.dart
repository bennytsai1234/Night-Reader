import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/engine/web_book/web_book_service.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/network_service.dart';

import '../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

class _FakeChapterDao extends Fake implements ChapterDao {
  @override
  Future<List<BookChapter>> getByBook(String bookUrl) async => const [];
}

void main() {
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();

  final getIt = GetIt.instance;
  if (getIt.isRegistered<ChapterDao>()) {
    getIt.unregister<ChapterDao>();
  }
  getIt.registerLazySingleton<ChapterDao>(() => _FakeChapterDao());

  late HttpServer server;
  late String baseUrl;
  late Future<void> Function(HttpRequest request) requestHandler;

  setUpAll(() async {
    await NetworkService().init();
    requestHandler = (_) async {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      await requestHandler(request);
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  test('reuses cached detail html when toc url matches book url', () async {
    var hitCount = 0;
    requestHandler = (request) async {
      if (request.uri.path == '/book/1') {
        hitCount++;
        request.response.write('''
<html>
  <body>
    <div class="title">測試書籍</div>
    <ul class="toc">
      <li><a href="/chapter/1.html">第一章</a></li>
      <li><a href="/chapter/2.html">第二章</a></li>
    </ul>
  </body>
</html>
''');
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    };

    final source = BookSource.fromJson({
      'bookSourceUrl': baseUrl,
      'bookSourceName': '測試書源',
      'ruleBookInfo': {'name': '.title@text'},
      'ruleToc': {
        'chapterList': 'ul.toc@li',
        'chapterName': 'a@text',
        'chapterUrl': 'a@href',
      },
    });
    final book = Book(
      bookUrl: '$baseUrl/book/1',
      origin: baseUrl,
      originName: '測試書源',
    );

    final detailedBook = await WebBook.getBookInfoAwait(source, book);
    final chapters = await WebBook.getChapterListAwait(source, detailedBook);

    expect(detailedBook.name, '測試書籍');
    expect(detailedBook.infoHtml, isNotEmpty);
    expect(detailedBook.tocHtml, isNotEmpty);
    expect(chapters, hasLength(2));
    expect(
      chapters.map((chapter) => chapter.url),
      containsAll(<String>[
        '$baseUrl/chapter/1.html',
        '$baseUrl/chapter/2.html',
      ]),
    );
    expect(hitCount, 1);
  });

  test(
    'getChapterListAwait keeps chapters in natural order by default',
    () async {
      requestHandler = (request) async {
        if (request.uri.path == '/book/2') {
          request.response.write('''
<html>
  <body>
    <ul class="toc">
      <li><a href="/chapter/1.html">第一章</a></li>
      <li><a href="/chapter/2.html">第二章</a></li>
      <li><a href="/chapter/3.html">第三章</a></li>
    </ul>
  </body>
</html>
''');
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      };

      final source = BookSource.fromJson({
        'bookSourceUrl': baseUrl,
        'bookSourceName': '測試書源',
        'ruleToc': {
          'chapterList': 'ul.toc@li',
          'chapterName': 'a@text',
          'chapterUrl': 'a@href',
        },
      });
      final book = Book(
        bookUrl: '$baseUrl/book/2',
        tocUrl: '$baseUrl/book/2',
        origin: baseUrl,
        originName: '測試書源',
      );

      final chapters = await WebBook.getChapterListAwait(source, book);

      expect(chapters.map((chapter) => chapter.title).toList(), <String>[
        '第一章',
        '第二章',
        '第三章',
      ]);
      expect(chapters.map((chapter) => chapter.index).toList(), <int>[0, 1, 2]);
    },
  );

  test('getChapterListAwait respects reverseToc display preference', () async {
    requestHandler = (request) async {
      if (request.uri.path == '/book/3') {
        request.response.write('''
<html>
  <body>
    <ul class="toc">
      <li><a href="/chapter/1.html">第一章</a></li>
      <li><a href="/chapter/2.html">第二章</a></li>
      <li><a href="/chapter/3.html">第三章</a></li>
    </ul>
  </body>
</html>
''');
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    };

    final source = BookSource.fromJson({
      'bookSourceUrl': baseUrl,
      'bookSourceName': '測試書源',
      'ruleToc': {
        'chapterList': 'ul.toc@li',
        'chapterName': 'a@text',
        'chapterUrl': 'a@href',
      },
    });
    final book = Book(
      bookUrl: '$baseUrl/book/3',
      tocUrl: '$baseUrl/book/3',
      origin: baseUrl,
      originName: '測試書源',
      readConfig: ReadConfig(reverseToc: true),
    );

    final chapters = await WebBook.getChapterListAwait(source, book);

    expect(chapters.map((chapter) => chapter.title).toList(), <String>[
      '第三章',
      '第二章',
      '第一章',
    ]);
    expect(chapters.map((chapter) => chapter.index).toList(), <int>[0, 1, 2]);
  });

  test('並發正文任一分頁失敗時整章失敗', () async {
    requestHandler = (request) async {
      switch (request.uri.path) {
        case '/content/1':
          request.response.write('''
<html><body>
  <div id="content">第一頁正文</div>
  <a class="next" href="/content/2">第二頁</a>
  <a class="next" href="/content/3">第三頁</a>
</body></html>
''');
        case '/content/2':
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write('failed');
        case '/content/3':
          request.response.write(
            '<html><body><div id="content">第三頁正文</div></body></html>',
          );
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    };

    final source = BookSource(
      bookSourceUrl: baseUrl,
      bookSourceName: '測試書源',
      ruleContent: ContentRule(
        content: '#content@text',
        nextContentUrl: 'a.next@href',
      ),
    );
    final book = Book(
      bookUrl: '$baseUrl/book/parallel-content',
      origin: baseUrl,
      originName: '測試書源',
    );
    final chapter = BookChapter(
      title: '第一章',
      url: '$baseUrl/content/1',
      bookUrl: book.bookUrl,
    );

    await expectLater(
      WebBook.getContentAwait(source, book, chapter),
      throwsA(anything),
    );
  });

  test('取消平行目錄分頁不會被降級成部分成功', () async {
    final nextPageStarted = Completer<void>();
    final releaseNextPages = Completer<void>();
    requestHandler = (request) async {
      if (request.uri.path == '/toc/cancel') {
        request.response.write('''
<html><body>
  <ul><li class="chapter"><a href="/chapter/1">第一章</a></li></ul>
  <a class="next" href="/toc/cancel/2">第二頁</a>
  <a class="next" href="/toc/cancel/3">第三頁</a>
</body></html>
''');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/toc/cancel/2' ||
          request.uri.path == '/toc/cancel/3') {
        if (!nextPageStarted.isCompleted) nextPageStarted.complete();
        await releaseNextPages.future;
        try {
          request.response.write('''
<html><body>
  <ul><li class="chapter"><a href="/chapter/2">第二章</a></li></ul>
</body></html>
''');
          await request.response.close();
        } catch (_) {
          // 取消請求後測試伺服器可能已失去 client 連線。
        }
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    };

    final source = BookSource.fromJson({
      'bookSourceUrl': baseUrl,
      'bookSourceName': '取消測試書源',
      'ruleToc': {
        'chapterList': 'li.chapter',
        'chapterName': 'a@text',
        'chapterUrl': 'a@href',
        'nextTocUrl': 'a.next@href',
      },
    });
    final book = Book(
      bookUrl: '$baseUrl/book/cancel',
      tocUrl: '$baseUrl/toc/cancel',
      origin: baseUrl,
      originName: '取消測試書源',
    );
    final cancelToken = CancelToken();
    final future = WebBook.getChapterListAwait(
      source,
      book,
      cancelToken: cancelToken,
    );

    try {
      await nextPageStarted.future.timeout(const Duration(seconds: 2));
      cancelToken.cancel('使用者取消目錄載入');
      releaseNextPages.complete();

      await expectLater(
        future,
        throwsA(
          predicate<Object>(
            (error) => error is DioException && CancelToken.isCancel(error),
          ),
        ),
      );
    } finally {
      if (!releaseNextPages.isCompleted) releaseNextPages.complete();
    }
  });
}

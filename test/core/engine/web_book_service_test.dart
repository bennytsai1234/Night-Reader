import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

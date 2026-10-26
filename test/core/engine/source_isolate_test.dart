import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/js/js_engine.dart';
import 'package:night_reader/core/engine/source_isolate/isolate_channel.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/engine/web_book/headless_webview_service.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/backstage_webview.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/book_update_service.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/services/rate_limiter.dart';
import 'package:night_reader/features/search/search_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_helper.dart';

// 送進書源 isolate 的工作都在頂層函式裡建立，只捕捉參數（見
// [SourceIsolate.run]）。

Future<String?> _isolateName() =>
    SourceIsolate.run((_) async => Isolate.current.debugName);

Future<void> _throwInSourceIsolate(Object Function() error) =>
    SourceIsolate.run((_) async => throw error());

DioException _connectionTimeout() => DioException(
  requestOptions: RequestOptions(path: '/x'),
  type: DioExceptionType.connectionTimeout,
);

Future<String> _waitForCancel(CancelToken cancelToken) => SourceIsolate.run(
  (token) async => throw await token.whenCancel,
  cancelToken: cancelToken,
);

Future<void> _upsertBook(String url) =>
    SourceIsolate.run((_) => getIt<BookDao>().upsert(_book(url)));

Future<void> _saveCookie(String url, String name, String value) =>
    SourceIsolate.run(
      (_) => NetworkService().cookieJar.saveFromResponse(Uri.parse(url), [
        Cookie(name, value),
      ]),
    );

Future<List<String>> _loadCookies(String url) => SourceIsolate.run(
  (_) async => [
    for (final cookie in await NetworkService().cookieJar.loadForRequest(
      Uri.parse(url),
    ))
      '${cookie.name}=${cookie.value}',
  ],
);

/// 書源 isolate 依 [source] 的限流發一個「請求」，回傳它開始的時間。
Future<int> _limitedRequestStart(BookSource source) => SourceIsolate.run(
  (_) =>
      ConcurrentRateLimiter(source)
          .withLimit(() async => DateTime.now().millisecondsSinceEpoch),
);

Future<String> _renderInSourceIsolate(String url) => SourceIsolate.run(
  (_) => HeadlessWebViewService().getRenderedHtml(url: url, delayTime: 5),
);

Future<Object?> _backstageInSourceIsolate(String html) => SourceIsolate.run(
  (_) async => (await BackstageWebView(
    html: html,
    sourceRegex: 'b+',
  ).getStrResponse())['body'],
);

Future<void> _logInSourceIsolate(String message) =>
    SourceIsolate.run((_) async => AppLog.put(message, toast: true));

Future<Object?> _memoryInSourceIsolate(String key) =>
    SourceIsolate.run((_) async => CacheManager().getFromMemory(key));

Future<void> _putMemoryInSourceIsolate(String key, String value) =>
    SourceIsolate.run((_) async => CacheManager().putMemory(key, value));

Future<String> _cookieStoreInSourceIsolate(String url) =>
    SourceIsolate.run((_) => CookieStore().getCookie(url));

Future<String> _evaluateJs(String code) => SourceIsolate.run((_) async {
  final engine = JsEngine();
  try {
    return '${engine.evaluate(code)}';
  } finally {
    engine.dispose();
  }
});

Book _book(String url) =>
    Book(bookUrl: url, origin: 'local', name: url, author: '作者');

/// 錯誤裡帶著不能跨 isolate 傳的連接埠。
class _UnsendableError implements Exception {
  _UnsendableError() : _port = ReceivePort()..close();

  // ignore: unused_field
  final ReceivePort _port;

  @override
  String toString() => '帶著連接埠的錯誤';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DriftIsolate databaseIsolate;
  late AppDatabase db;
  late HttpServer server;
  late String baseUrl;

  // `/held/<名稱>` 的正文：請求到了就記下（[arrived]），等測試放行
  // （[released]）才回。
  final arrived = <String, Completer<void>>{};
  final released = <String, Completer<void>>{};
  Completer<void> gate(Map<String, Completer<void>> gates, String name) =>
      gates.putIfAbsent(name, Completer<void>.new);

  setUpAll(() async {
    quickJsUnavailableReason();
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    databaseIsolate = await DriftIsolate.spawn(NativeDatabase.memory);
    db = AppDatabase.connected(await databaseIsolate.connect());
    registerDatabase(db);
    GetIt.instance.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    await NetworkService().init(ephemeral: true);

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      request.response.headers.contentType = ContentType.html;
      switch (request.uri.path) {
        case '/search':
          request.response.write(
            '<div class="item"><a href="/book/1">夜讀</a>'
            '<span class="author">作者</span></div>',
          );
        case '/book/1':
          request.response.write(
            '<h1>夜讀</h1><p class="author">作者</p>'
            '<div class="list"><a href="/c/1">第一章</a>'
            '<a href="/c/2">第二章</a><a href="/c/3">第三章</a></div>',
          );
        case '/c/1':
          request.response.write('<p>第一章的正文，夜裡讀起來剛好。</p>');
        case '/c/2':
          request.response.write('<p>第二章的正文，夜裡讀起來剛好。</p>');
        case final path when path.startsWith('/held/'):
          final name = path.substring('/held/'.length);
          gate(arrived, name).complete();
          await gate(released, name).future;
          request.response.write('<p>$name 的正文，夜裡讀起來剛好。</p>');
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    SourceIsolate.enabled = true;
    SourceIsolate.start(database: Future.value(databaseIsolate));
  });

  tearDownAll(() async {
    await SourceIsolate.stop();
    SourceIsolate.enabled = false;
    await server.close(force: true);
    await db.close();
    await databaseIsolate.shutdownAll();
    await GetIt.instance.reset();
  });

  test('work runs in the source isolate', () async {
    expect(await _isolateName(), 'SourceIsolate');
  });

  group('errors', () {
    test('come back as the same type', () async {
      await expectLater(
        _throwInSourceIsolate(_connectionTimeout),
        throwsA(
          isA<DioException>().having(
            (e) => e.type,
            'type',
            DioExceptionType.connectionTimeout,
          ),
        ),
      );
    });

    test('that cannot cross isolates come back as their text', () async {
      await expectLater(
        _throwInSourceIsolate(_UnsendableError.new),
        throwsA(
          isA<IsolateTaskError>().having(
            (e) => e.message,
            'message',
            '帶著連接埠的錯誤',
          ),
        ),
      );
    });
  });

  test('cancelling on the main isolate cancels the work', () async {
    final cancelToken = CancelToken();
    final work = _waitForCancel(cancelToken);
    await pumpEventQueue();
    cancelToken.cancel();

    await expectLater(
      work,
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
  });

  test('database writes update queries watched on the main isolate', () async {
    const url = 'https://book.test/watched';
    final watched = db.select(db.books).watch();
    final seen = expectLater(
      watched,
      emitsThrough(
        predicate<List<Book>>((books) => books.any((b) => b.bookUrl == url)),
      ),
    );

    await _upsertBook(url);

    await seen;
  });

  test('cookies saved on either side are one cookie jar', () async {
    await _saveCookie('https://cookie.test/a', 'fromSource', '1');
    await NetworkService().cookieJar.saveFromResponse(
      Uri.parse('https://cookie.test/b'),
      [Cookie('fromMain', '2')],
    );

    final mainSide = await NetworkService().cookieJar.loadForRequest(
      Uri.parse('https://cookie.test/'),
    );
    expect(mainSide.map((c) => c.name), contains('fromSource'));
    expect(
      await _loadCookies('https://cookie.test/'),
      containsAll(['fromSource=1', 'fromMain=2']),
    );
  });

  test('rate limits are shared with requests on the main isolate', () async {
    final source = BookSource.fromJson({
      'bookSourceUrl': 'https://limited.test',
      'bookSourceName': '限流',
      'concurrentRate': '300',
    });
    final mainRequestDone = Completer<void>();
    final mainRequest = ConcurrentRateLimiter(source)
        .withLimit(() => mainRequestDone.future);
    await pumpEventQueue();

    final sourceRequest = _limitedRequestStart(source);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final releasedAt = DateTime.now().millisecondsSinceEpoch;
    mainRequestDone.complete();
    await mainRequest;

    // 主 isolate 的請求還沒結束，書源 isolate 的請求不能開始。
    expect(await sourceRequest, greaterThanOrEqualTo(releasedAt));
  });

  group('WebView requests are served by the main isolate', () {
    tearDown(() {
      HeadlessWebViewService.delegate = null;
      BackstageWebView.delegate = null;
    });

    test('rendering a page', () async {
      // 測試裡沒有平台的 WebView：主 isolate 這一端換成假的，看請求有沒有
      // 原樣送到。
      String? renderedUrl;
      int? renderedDelay;
      HeadlessWebViewService.delegate =
          ({
            required String url,
            Map<String, String>? headers,
            String? userAgent,
            String? js,
            int delayTime = 0,
          }) async {
            renderedUrl = url;
            renderedDelay = delayTime;
            return '<html>rendered</html>';
          };

      expect(
        await _renderInSourceIsolate('https://web.test/page'),
        '<html>rendered</html>',
      );
      expect(renderedUrl, 'https://web.test/page');
      expect(renderedDelay, 5);
    });

    test('java.webView', () async {
      BackstageWebView.delegate = (request) async => {
        'body': '${request.html}|${request.sourceRegex}',
      };

      expect(await _backstageInSourceIsolate('<p>aa</p>'), '<p>aa</p>|b+');
    });
  });

  test('logs reach the main isolate', () async {
    final logs = <(String, bool)>[];
    AppLog.delegate = (message, error, stackTrace, toast) =>
        logs.add((message, toast));
    addTearDown(() => AppLog.delegate = null);

    await _logInSourceIsolate('書源 isolate 的紀錄');

    expect(logs, [('書源 isolate 的紀錄', true)]);
  });

  test('memory cache writes are mirrored both ways', () async {
    CacheManager().putMemory('mirror_from_main', '主');
    expect(await _memoryInSourceIsolate('mirror_from_main'), '主');

    await _putMemoryInSourceIsolate('mirror_from_source', '書源');
    expect(CacheManager().getFromMemory('mirror_from_source'), '書源');

    CacheManager().deleteMemory('mirror_from_main');
    expect(await _memoryInSourceIsolate('mirror_from_main'), isNull);
  });

  test('cookie store writes are mirrored to the source isolate', () async {
    await CookieStore().setCookie('https://www.store.test', 'a=1');
    expect(await _cookieStoreInSourceIsolate('https://m.store.test'), 'a=1');

    await CookieStore().removeCookie('https://www.store.test');
    expect(await _cookieStoreInSourceIsolate('https://m.store.test'), '');
  });

  test('rule JavaScript runs in the source isolate', () async {
    expect(await _evaluateJs('[1, 2, 3].map((n) => n * 2).join(",")'), '2,4,6');
  }, skip: quickJsUnavailableReason());

  test('a search runs through the source isolate', () async {
    final source = BookSource.fromJson({
      'bookSourceUrl': baseUrl,
      'bookSourceName': '本機',
      'searchUrl': '$baseUrl/search',
      'ruleSearch': {
        'bookList': 'class.item',
        'name': 'a@text',
        'author': 'class.author@text',
        'bookUrl': 'a@href',
      },
    });
    final callback = _Collect();
    final model = SearchModel(callback: callback);
    addTearDown(model.dispose);

    await model.searchSources(
      key: '夜讀',
      sources: [source],
      precisionSearch: false,
    );

    expect(callback.failures, isEmpty);
    expect(callback.published.map((b) => (b.name, b.author)), [('夜讀', '作者')]);
  });

  test('a shelf update check runs through the source isolate', () async {
    await BookSourceDao(db).upsert(
      BookSource.fromJson({
        'bookSourceUrl': baseUrl,
        'bookSourceName': '本機',
        'ruleBookInfo': {'name': 'tag.h1@text', 'author': 'class.author@text'},
        'ruleToc': {
          'chapterList': 'class.list@a',
          'chapterName': 'a@text',
          'chapterUrl': 'a@href',
        },
      }),
    );
    final book = Book(
      bookUrl: '$baseUrl/book/1',
      origin: baseUrl,
      name: '夜讀',
      author: '作者',
      isInBookshelf: true,
      totalChapterNum: 2,
    );
    await BookDao(db).upsert(book);
    final downloads = <(String, bool)>[];

    final result = await BookUpdateService(
      keepDownloaded: (url, {hasNewChapters = false}) async =>
          downloads.add((url, hasNewChapters)),
    ).check(book);

    expect(result.error, isNull);
    expect(result.newChapterCount, 1);
    expect(downloads, [(book.bookUrl, true)]);
    final chapters = await ChapterDao(db).getByBook(book.bookUrl);
    expect(chapters.map((c) => c.title), ['第一章', '第二章', '第三章']);
    expect((await BookDao(db).getByUrl(book.bookUrl))!.totalChapterNum, 3);
  });

  group('BookSourceService work goes through the source isolate', () {
    late List<String> logs;
    late BookSource source;

    setUp(() {
      logs = [];
      AppLog.delegate = (message, error, stackTrace, toast) =>
          logs.add(message);
      source = BookSource.fromJson({
        'bookSourceUrl': baseUrl,
        'bookSourceName': '本機',
        'searchUrl': '$baseUrl/search',
        'exploreUrl': '玄幻::$baseUrl/search',
        'ruleSearch': {
          'bookList': 'class.item',
          'name': 'a@text',
          'author': 'class.author@text',
          'bookUrl': 'a@href',
        },
        'ruleBookInfo': {'name': 'tag.h1@text', 'author': 'class.author@text'},
        'ruleToc': {
          'chapterList': 'class.list@a',
          'chapterName': 'a@text',
          'chapterUrl': 'a@href',
        },
        'ruleContent': {'content': 'tag.p@text'},
      });
    });

    tearDown(() {
      AppLog.delegate = null;
      // 送不進書源 isolate 時會改在主 isolate 執行並記下來，結果照樣對。
      expect(logs.where((m) => m.contains('送不進書源 isolate')), isEmpty);
    });

    test('book info, chapter list and content', () async {
      final service = BookSourceService();
      final book = Book(bookUrl: '$baseUrl/book/1', origin: baseUrl);

      final info = await service.getBookInfo(source, book);
      final chapters = await service.getChapterList(source, info);
      final content = await service.getContent(source, info, chapters.first);

      expect((info.name, info.author), ('夜讀', '作者'));
      expect(chapters.map((c) => c.title), ['第一章', '第二章', '第三章']);
      expect(content, contains('第一章的正文'));
    });

    test('searches that stop at the first exact match', () async {
      final found = await BookSourceService().preciseSearch(source, '夜讀', '作者');

      expect(found.map((b) => (b.name, b.author)), [('夜讀', '作者')]);
    });

    test('the URLs a task sent come back for source debugging', () async {
      final urls = <String>[];
      await withSourceRequestLog(
        urls.add,
        () => BookSourceService().searchBooks(source, '夜讀'),
      );

      expect(urls, ['$baseUrl/search']);
    });

    test('explore kinds and explore pages', () async {
      final service = BookSourceService();

      final kinds = await service.exploreKinds(
        source.exploreUrl,
        source: source,
      );
      final books = await service.exploreBooks(source, kinds.single.url!);

      expect(kinds.single.title, '玄幻');
      expect(books.map((b) => b.name), ['夜讀']);
    });

    test(
      'what rules write on the book and chapter comes back to the caller',
      () async {
        source.ruleContent!.content =
            'tag.p@text@js:book.putVariable("seen", "正文");'
            'chapter.putVariable("page", "1");result';
        final book = Book(
          bookUrl: '$baseUrl/book/1',
          origin: baseUrl,
          name: '夜讀',
        );
        final chapter = BookChapter(
          title: '第一章',
          url: '$baseUrl/c/1',
          bookUrl: book.bookUrl,
        );

        final content = BookSourceService().getContent(source, book, chapter);
        // 抓的期間畫面執行緒改了規則沒動的欄位，不會被複本的舊值蓋回去。
        book.name = '夜讀（改）';
        expect(await content, contains('第一章的正文'));

        expect(book.getVariable('seen'), '正文');
        expect(chapter.getVariable('page'), '1');
        expect(book.name, '夜讀（改）');
      },
      skip: quickJsUnavailableReason(),
    );

    test('a caller edit made after the work was sent is not undone', () async {
      final book = Book(
        bookUrl: '$baseUrl/book/1',
        origin: baseUrl,
        name: '夜讀',
      );
      final chapter = BookChapter(
        title: '改名',
        url: '$baseUrl/held/rename',
        bookUrl: book.bookUrl,
      );

      final content = BookSourceService().getContent(source, book, chapter);
      book.name = '夜讀（改）';
      // 工作已經送出、正在抓：書源 isolate 的複本是「夜讀（改）」。
      await gate(arrived, 'rename').future;
      book.name = '夜讀（再改）';
      gate(released, 'rename').complete();

      expect(await content, contains('rename 的正文'));
      expect(book.name, '夜讀（再改）');
    });

    test('a download keeps what rules write on the book from one chapter to '
        'the next', () async {
      source.ruleContent!.content =
          'tag.p@text@js:if (chapter.title == "第一章") '
          'book.putVariable("token", "yes");'
          'result + " token=" + book.getVariable("token")';
      await getIt<BookSourceDao>().upsert(source);
      final book = Book(
        bookUrl: '$baseUrl/book/download',
        origin: baseUrl,
        name: '下載',
        isInBookshelf: true,
      );
      await getIt<BookDao>().upsert(book);
      final chapters = [
        for (final (i, title) in ['第一章', '第二章'].indexed)
          BookChapter(
            title: title,
            url: '$baseUrl/c/${i + 1}',
            bookUrl: book.bookUrl,
            index: i,
          ),
      ];
      await getIt<ChapterDao>().insertChapters(chapters);

      final plan = await planDownloadInSourceIsolate(
        DownloadTask(bookUrl: book.bookUrl, bookName: book.name),
      );
      // 依序抓：第二章開始時第一章的規則已經寫進書了。
      for (final chapter in plan.missing) {
        final result = await downloadChapterInSourceIsolate(
          run: plan.run,
          chapterUrl: chapter.url,
          maxAttempts: 1,
        );
        expect(result.success, isTrue, reason: chapter.title);
      }
      await finishDownloadRunInSourceIsolate(plan.run);

      final second = await getIt<ReaderChapterContentDao>().getEntry(
        contentKey: ReaderChapterContentDao.contentKey(
          origin: book.origin,
          bookUrl: book.bookUrl,
          chapterUrl: chapters[1].url,
        ),
      );
      expect(second?.content, contains('token=yes'));
    }, skip: quickJsUnavailableReason());

    test(
      'chapters fetched at the same time keep the variables of both',
      () async {
        source.ruleContent!.content =
            'tag.p@text@js:book.putVariable(chapter.title, "done");result';
        final book = Book(bookUrl: '$baseUrl/book/1', origin: baseUrl);
        BookChapter chapterOf(String name) => BookChapter(
          title: name,
          url: '$baseUrl/held/$name',
          bookUrl: book.bookUrl,
        );

        final service = BookSourceService();
        final one = service.getContent(source, book, chapterOf('one'));
        final two = service.getContent(source, book, chapterOf('two'));
        // 兩章都送出後才回：兩份複本都還沒有對方的變數。
        await Future.wait([
          gate(arrived, 'one').future,
          gate(arrived, 'two').future,
        ]);
        gate(released, 'one').complete();
        await one;
        gate(released, 'two').complete();
        await two;

        expect(book.variableMap, {'one': 'done', 'two': 'done'});
      },
      skip: quickJsUnavailableReason(),
    );
  });
}

class _Collect implements SearchModelCallback {
  final List<SearchBook> published = [];
  final List<SearchFailure> failures = [];

  @override
  void onSearchSuccess(List<SearchBook> searchBooks) => published
    ..clear()
    ..addAll(searchBooks);

  @override
  void onSearchFailure(SearchFailure failure) => failures.add(failure);

  @override
  void onSearchStart() {}

  @override
  void onSearchFinish({required bool isEmpty}) {}

  @override
  void onSearchProgress({
    required List<String> waitingSources,
    required int completed,
    required int total,
    required int failed,
  }) {}
}

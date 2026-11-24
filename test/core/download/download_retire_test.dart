import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/storage/chapter_content_preparation_pipeline.dart';
import 'package:night_reader/core/download/download_service.dart';
import 'package:night_reader/core/network/network_service.dart';

import '../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

/// 每次抓正文都抓到空的（不是網路斷線那種會在請求層重試的），讓流程進到
/// 重試前的等待。
class _EmptyContentService extends BookSourceService {
  int calls = 0;

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) async {
    calls++;
    return '';
  }
}

/// 網路差時移出書架或換源：這本書正在下載的請求一直不回，不能讓移出等到
/// 它自己逾時。
void main() {
  _MinimalServicesBinding.ensureInitialized();
  final quickJsSkip = quickJsUnavailableReason();

  late DriftIsolate databaseIsolate;
  late AppDatabase db;
  late HttpServer server;
  late String base;
  final arrived = <String>[];

  setUpAll(() async {
    await GetIt.instance.reset();
    databaseIsolate = await DriftIsolate.spawn(NativeDatabase.memory);
    db = AppDatabase.connected(await databaseIsolate.connect());
    registerDatabase(db);
    await NetworkService().init(ephemeral: true);
    // `/outer/` 立刻回一頁；其他請求收下就不回（連線與接收逾時各 15 秒、
    // 共試 3 次）。
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://${server.address.address}:${server.port}';
    server.listen((request) async {
      arrived.add(request.uri.path);
      if (!request.uri.path.startsWith('/outer/')) return;
      request.response.headers.contentType = ContentType.html;
      request.response.write('<p>外層頁面</p>');
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await SourceIsolate.stop();
    SourceIsolate.enabled = false;
    await server.close(force: true);
    await db.close();
    await databaseIsolate.shutdownAll();
    await GetIt.instance.reset();
  });

  Future<void> until(bool Function() condition, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('等不到$what');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// 開始下載 [book] 的 [chapters]，等 [held] 那些請求都送到伺服器卡住後
  /// 移出書架，回傳移出花的時間。
  Future<Duration> retireWhileStalled({
    required Book book,
    required BookSource source,
    required List<BookChapter> chapters,
    required List<String> held,
  }) async {
    await getIt<BookSourceDao>().upsert(source);
    await getIt<BookDao>().upsert(book);
    await getIt<ChapterDao>().insertChapters(chapters);
    final service = DownloadService();
    final task = DownloadTask(
      bookUrl: book.bookUrl,
      bookName: book.name,
      totalCount: chapters.length,
    );
    service.tasks.add(task);
    service.isDownloading = true;
    addTearDown(() => service.isDownloading = false);

    final run = service.processTask(task);
    await until(() => held.every(arrived.contains), '卡住的請求');

    final stopwatch = Stopwatch()..start();
    await service.retireBook(book.bookUrl);
    await run;
    stopwatch.stop();

    expect(service.tasks.where((t) => t.bookUrl == book.bookUrl), isEmpty);
    // 取消不是下載失敗。
    expect(task.errorCount, 0);
    expect(task.lastErrorMessage, isNull);
    return stopwatch.elapsed;
  }

  test('removing a book stops its stalled downloads at once', () async {
    final book = Book(
      bookUrl: '$base/book/http',
      origin: '$base/source/http',
      name: '網路很差的書',
      isInBookshelf: true,
    );

    final elapsed = await retireWhileStalled(
      book: book,
      source: BookSource.fromJson({
        'bookSourceName': '慢',
        'bookSourceUrl': book.origin,
      }),
      chapters: [
        for (var i = 0; i < 3; i++)
          BookChapter(
            url: '$base/stall/$i',
            title: '第 $i 章',
            index: i,
            bookUrl: book.bookUrl,
          ),
      ],
      held: [for (var i = 0; i < 3; i++) '/stall/$i'],
    );

    // 改前要等每個請求各自逾時（至少 15 秒）。
    expect(elapsed, lessThan(const Duration(seconds: 2)));
  });

  // 規則 JS 要等的呼叫只在書源 isolate 裡能用（ADR 0034）。
  test(
    'a request the rule JS made itself stops too',
    skip: quickJsSkip,
    () async {
      SourceIsolate.enabled = true;
      SourceIsolate.start(database: Future.value(databaseIsolate));
      addTearDown(() async {
        await SourceIsolate.stop();
        SourceIsolate.enabled = false;
      });
      final book = Book(
        bookUrl: '$base/book/js',
        origin: '$base/source/js',
        name: '規則自己抓正文的書',
        isInBookshelf: true,
      );

      // 外層頁面立刻回來，規則 JS 再用 java.ajax 抓真正的正文，卡住。
      final elapsed = await retireWhileStalled(
        book: book,
        source: BookSource.fromJson({
          'bookSourceName': '規則 JS',
          'bookSourceUrl': book.origin,
          'ruleContent': {'content': "@js:java.ajax('$base/ajax/js')"},
        }),
        chapters: [
          BookChapter(
            url: '$base/outer/js',
            title: '正文',
            index: 0,
            bookUrl: book.bookUrl,
          ),
        ],
        held: ['/ajax/js'],
      );

      expect(elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  // 書源改網址（holdBooks）時最後一批章節還卡在網路上：那一輪被停下，
  // 不能把一章都沒存到的書結算成「下載完成」，放行後要排回去重抓。
  test(
    'a source change during the last chapters does not finish the book',
    () async {
      final book = Book(
        bookUrl: '$base/book/hold',
        origin: '$base/source/hold',
        name: '改網址時還在下載的書',
        isInBookshelf: true,
      );
      await getIt<BookSourceDao>().upsert(
        BookSource.fromJson({
          'bookSourceName': '改',
          'bookSourceUrl': book.origin,
        }),
      );
      await getIt<BookDao>().upsert(book);
      await getIt<ChapterDao>().insertChapters([
        BookChapter(
          url: '$base/stall/hold',
          title: '唯一一章',
          index: 0,
          bookUrl: book.bookUrl,
        ),
      ]);
      final service = DownloadService();
      final task = DownloadTask(
        bookUrl: book.bookUrl,
        bookName: book.name,
        totalCount: 1,
      );
      service.tasks.add(task);
      service.isDownloading = true;
      addTearDown(() {
        service.isDownloading = false;
        service.tasks.remove(task);
      });

      final run = service.processTask(task);
      await until(() => arrived.contains('/stall/hold'), '卡住的請求');
      final release = await service.holdBooks([book.bookUrl]);
      await run;

      expect(task.isCompleted, isFalse, reason: '一章都沒存到');
      expect(task.successCount, 0);
      expect(task.errorCount, 0, reason: '停下不是失敗');
      release();
      expect(task.isWaiting, isTrue, reason: '放行後排回去用新網址重抓');
    },
  );

  // 換源要先等這本的下載收尾，等的這段時間使用者移除了它的下載；換源最後
  // 沒換（放回原狀）時不把下載加回來。
  test('a download removed while a source switch waits stays removed when '
      'the switch is called off', () async {
    final service = DownloadService();
    final book = Book(
      bookUrl: '$base/book/removed',
      origin: '$base/source/removed',
      name: '換源時移除下載的書',
      isInBookshelf: true,
    );
    service.tasks.add(
      DownloadTask(
        bookUrl: book.bookUrl,
        bookName: book.name,
        totalCount: 3,
        status: DownloadTask.statusPaused,
      ),
    );

    final lease = await service.quiesceForSourceSwitch(book);
    service.removeTask(book.bookUrl);
    lease.rolledBack();

    expect(service.tasks.where((t) => t.bookUrl == book.bookUrl), isEmpty);
    expect(service.isTaskRetiring(book.bookUrl), isFalse);
  });

  test('a chapter waiting to retry stops when cancelled', () async {
    final book = Book(
      bookUrl: '$base/book/retry',
      origin: '$base/source/retry',
      name: '書',
    );
    final chapter = BookChapter(
      url: '$base/retry',
      title: '一章',
      index: 0,
      bookUrl: book.bookUrl,
    );
    final contentService = _EmptyContentService();
    final pipeline = ChapterContentPreparationPipeline(
      book: book,
      contentStore: null,
      sourceDao: getIt<BookSourceDao>(),
      service: contentService,
      getSource: () => BookSource.fromJson({
        'bookSourceName': '空',
        'bookSourceUrl': book.origin,
      }),
      retryDelay: (_) => const Duration(minutes: 1),
    );
    final cancelToken = CancelToken();

    final prepared = pipeline.prepare(
      chapterIndex: 0,
      chapter: chapter,
      forceRefresh: true,
      maxAttempts: 3,
      cancelToken: cancelToken,
    );
    await until(() => contentService.calls == 1, '第一次抓正文');
    cancelToken.cancel();

    await expectLater(
      prepared.timeout(const Duration(seconds: 2)),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(contentService.calls, 1);
  });
}

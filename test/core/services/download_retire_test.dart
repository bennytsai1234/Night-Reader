import 'dart:io';

import 'package:dio/dio.dart';
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
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chapter_content_preparation_pipeline.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/network_service.dart';

import '../../test_helper.dart';

class _MinimalServicesBinding extends BindingBase
    with SchedulerBinding, ServicesBinding {
  static _MinimalServicesBinding? _instance;

  static _MinimalServicesBinding ensureInitialized() {
    return _instance ??= _MinimalServicesBinding();
  }
}

/// 第一次抓正文就失敗（不是網路斷線那種會在請求層重試的），讓流程進到
/// 重試前的等待。
class _FailingContentService extends BookSourceService {
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
  setupTestDI();
  _MinimalServicesBinding.ensureInitialized();

  late AppDatabase db;
  late HttpServer server;
  late String origin;
  final requests = <HttpRequest>[];

  setUpAll(() async {
    final getIt = GetIt.instance;
    db = AppDatabase.forTesting(NativeDatabase.memory());
    getIt
      ..registerSingleton<BookDao>(BookDao(db))
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<ChapterDao>(ChapterDao(db))
      ..registerSingleton<ReaderChapterContentDao>(ReaderChapterContentDao(db))
      ..registerSingleton<DownloadDao>(DownloadDao(db));
    await NetworkService().init();
    // 收下請求就不回（連線逾時與接收逾時各 15 秒、共試 3 次）。
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin = 'http://${server.address.address}:${server.port}';
    server.listen(requests.add);
  });

  tearDownAll(() async {
    await server.close(force: true);
    await db.close();
  });

  test('removing a book stops its stalled downloads at once', () async {
    final book = Book(
      bookUrl: '$origin/book/1',
      origin: origin,
      name: '網路很差的書',
      isInBookshelf: true,
    );
    await GetIt.instance<BookSourceDao>().upsert(
      BookSource.fromJson({'bookSourceName': '慢', 'bookSourceUrl': origin}),
    );
    await GetIt.instance<BookDao>().upsert(book);
    await GetIt.instance<ChapterDao>().insertChapters([
      for (var i = 0; i < 3; i++)
        BookChapter(
          url: '$origin/c/$i',
          title: '第 $i 章',
          index: i,
          bookUrl: book.bookUrl,
        ),
    ]);
    final service = DownloadService();
    final task = DownloadTask(
      bookUrl: book.bookUrl,
      bookName: book.name,
      totalCount: 3,
    );
    service.tasks.add(task);
    service.isDownloading = true;
    addTearDown(() => service.isDownloading = false);

    final run = service.processTask(task);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (requests.length < 3) {
      if (DateTime.now().isAfter(deadline)) fail('正文請求沒有送出');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final stopwatch = Stopwatch()..start();
    await service.retireBook(book.bookUrl);
    await run;

    // 改前要等每個請求各自逾時（至少 15 秒）。
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(service.tasks.where((t) => t.bookUrl == book.bookUrl), isEmpty);
    // 取消不是下載失敗。
    expect(task.errorCount, 0);
    expect(task.lastErrorMessage, isNull);
  });

  test('a chapter waiting to retry stops when cancelled', () async {
    final book = Book(bookUrl: '$origin/book/2', origin: origin, name: '書');
    final chapter = BookChapter(
      url: '$origin/c/x',
      title: '一章',
      index: 0,
      bookUrl: book.bookUrl,
    );
    final contentService = _FailingContentService();
    final pipeline = ChapterContentPreparationPipeline(
      book: book,
      contentStore: null,
      sourceDao: GetIt.instance<BookSourceDao>(),
      service: contentService,
      getSource: () =>
          BookSource.fromJson({'bookSourceName': '慢', 'bookSourceUrl': origin}),
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
    await Future<void>.delayed(const Duration(milliseconds: 20));
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

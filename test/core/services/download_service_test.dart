import 'package:drift/native.dart';
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
import 'package:night_reader/core/services/download_service.dart';

void main() {
  late AppDatabase db;

  setUpAll(() async {
    final getIt = GetIt.instance;
    await getIt.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    getIt
      ..registerSingleton<BookDao>(BookDao(db))
      ..registerSingleton<BookSourceDao>(BookSourceDao(db))
      ..registerSingleton<ChapterDao>(ChapterDao(db))
      ..registerSingleton<ReaderChapterContentDao>(ReaderChapterContentDao(db))
      ..registerSingleton<DownloadDao>(DownloadDao(db));
  });

  tearDownAll(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  test('a task that is still downloading cannot be retried', () async {
    final service = DownloadService();
    final task = DownloadTask(
      bookUrl: 'https://book.example',
      bookName: '書',
      startChapterIndex: 0,
      endChapterIndex: 9,
      status: DownloadTask.statusDownloading,
      totalCount: 10,
      successCount: 4,
      errorCount: 1,
    );
    service.tasks.add(task);
    addTearDown(() => service.tasks.remove(task));

    // 那一輪還在跑；歸零計數會讓失敗的章節最後被標成完成。
    service.retryTask(task.bookUrl);

    expect(task.status, DownloadTask.statusDownloading);
    expect(task.successCount, 4);
    expect(task.errorCount, 1);
  });

  group('shelf auto-download decision', () {
    const day = 24 * 60 * 60 * 1000;
    const now = 100 * day;

    DownloadTask task(int status, {int lastUpdateTime = now}) => DownloadTask(
      bookUrl: 'https://book.example',
      bookName: '書',
      startChapterIndex: 0,
      endChapterIndex: 9,
      status: status,
      lastUpdateTime: lastUpdateTime,
    );

    ShelfDownloadDecision decide(
      DownloadTask? task, {
      bool running = false,
      bool hasNewChapters = false,
    }) => decideShelfDownload(
      task: task,
      running: running,
      hasNewChapters: hasNewChapters,
      now: now,
    );

    test('queues a book with no task or a finished one', () {
      expect(decide(null), ShelfDownloadDecision.queue);
      expect(
        decide(task(DownloadTask.statusCompleted)),
        ShelfDownloadDecision.queue,
      );
    });

    test('new chapters for a running task wait for the run to end', () {
      expect(
        decide(task(DownloadTask.statusWaiting)),
        ShelfDownloadDecision.afterCurrentRun,
      );
      expect(
        decide(task(DownloadTask.statusDownloading)),
        ShelfDownloadDecision.afterCurrentRun,
      );
      expect(
        decide(task(DownloadTask.statusCompleted), running: true),
        ShelfDownloadDecision.afterCurrentRun,
      );
    });

    test('never resumes a task the user paused', () {
      expect(
        decide(task(DownloadTask.statusPaused), hasNewChapters: true),
        ShelfDownloadDecision.leave,
      );
    });

    test('a failed task waits a day, unless the source just worked', () {
      final failedNow = task(DownloadTask.statusFailed);
      expect(decide(failedNow), ShelfDownloadDecision.leave);
      expect(
        decide(failedNow, hasNewChapters: true),
        ShelfDownloadDecision.queue,
      );
      expect(
        decide(task(DownloadTask.statusFailed, lastUpdateTime: now - day)),
        ShelfDownloadDecision.queue,
      );
    });
  });

  test('a run stops after ten chapters in a row fail', () async {
    const origin = 'https://broken.example';
    final book = Book(
      bookUrl: '$origin/book/1',
      origin: origin,
      name: '壞掉的書',
      isInBookshelf: true,
    );
    await GetIt.instance<BookSourceDao>().upsert(
      BookSource.fromJson({'bookSourceName': '壞', 'bookSourceUrl': origin}),
    );
    await GetIt.instance<BookDao>().upsert(book);
    // 測試裡沒有初始化網路服務：每章都立刻失敗，不會真的連網。
    await GetIt.instance<ChapterDao>().insertChapters([
      for (var i = 0; i < 40; i++)
        BookChapter(
          url: 'unsupported://chapter/$i',
          title: '第 $i 章',
          index: i,
          bookUrl: book.bookUrl,
        ),
    ]);
    final service = DownloadService();
    final task = DownloadTask(
      bookUrl: book.bookUrl,
      bookName: book.name,
      startChapterIndex: 0,
      endChapterIndex: 39,
      totalCount: 40,
    );
    service.tasks.add(task);
    service.isDownloading = true;
    addTearDown(() {
      service.isDownloading = false;
      service.tasks.removeWhere((t) => t.bookUrl == book.bookUrl);
    });

    await service.processTask(task);

    final finished = service.tasks.firstWhere((t) => t.bookUrl == book.bookUrl);
    expect(finished.isFailed, isTrue);
    expect(finished.successCount, 0);
    // 停下時已在抓的章節（最多 5 章）照樣跑完。
    expect(finished.errorCount, inInclusiveRange(10, 15));
  });

  group('keepShelfBookDownloaded', () {
    const origin = 'https://shelf.example';

    Future<Book> seed(String path, {required bool inShelf}) async {
      final book = Book(
        bookUrl: '$origin/$path',
        origin: origin,
        name: path,
        isInBookshelf: inShelf,
      );
      await GetIt.instance<BookSourceDao>().upsert(
        BookSource.fromJson({'bookSourceName': '架', 'bookSourceUrl': origin}),
      );
      await GetIt.instance<BookDao>().upsert(book);
      await GetIt.instance<ChapterDao>().insertChapters([
        for (var i = 0; i < 3; i++)
          BookChapter(
            url: '$origin/$path/$i',
            title: '第 $i 章',
            index: i,
            bookUrl: book.bookUrl,
          ),
      ]);
      return book;
    }

    Future<void> settle(DownloadService service) async {
      // 排進去的任務會立刻開跑並失敗（測試沒有網路服務）；等佇列停下。
      for (var i = 0; i < 50 && service.isDownloading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    test('queues the missing chapters of a shelf book', () async {
      final book = await seed('book/on-shelf', inShelf: true);
      final service = DownloadService();
      addTearDown(() => settle(service));

      await service.keepShelfBookDownloaded(book.bookUrl);

      final stored = await GetIt.instance<DownloadDao>().getAll();
      final task = stored.firstWhere((t) => t.bookUrl == book.bookUrl);
      expect(task.totalCount, 3);
    });

    test(
      'new chapters found during a failed run retry right after it',
      () async {
        final book = await seed('book/failed-run', inShelf: true);
        final service = DownloadService();
        final running = DownloadTask(
          bookUrl: book.bookUrl,
          bookName: book.name,
          startChapterIndex: 0,
          endChapterIndex: 1,
          status: DownloadTask.statusDownloading,
          lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
        );
        service.tasks.add(running);
        service.activeTaskUrls.add(book.bookUrl);
        addTearDown(() async {
          await settle(service);
          service.tasks.removeWhere((t) => t.bookUrl == book.bookUrl);
        });

        // 這輪還在跑時，書架檢查抓到新章節。
        await service.keepShelfBookDownloaded(
          book.bookUrl,
          hasNewChapters: true,
        );
        // 這輪剛失敗：照一般規則要等一天，但書源剛剛還抓得到新章節。
        running
          ..status = DownloadTask.statusFailed
          ..lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
        service.activeTaskUrls.remove(book.bookUrl);
        service.onTaskFinished(running);
        for (var i = 0; i < 20; i++) {
          final stored = await GetIt.instance<DownloadDao>().getAll();
          if (stored.any((t) => t.bookUrl == book.bookUrl)) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }

        final stored = await GetIt.instance<DownloadDao>().getAll();
        final task = stored.firstWhere((t) => t.bookUrl == book.bookUrl);
        expect(task.totalCount, 3);
      },
    );

    test('a shelf book without a TOC is queued, and a failed TOC fetch '
        'waits for the retry interval', () async {
      final book = Book(
        bookUrl: '$origin/book/no-toc',
        origin: origin,
        name: '沒有目錄',
        isInBookshelf: true,
      );
      await GetIt.instance<BookSourceDao>().upsert(
        BookSource.fromJson({'bookSourceName': '架', 'bookSourceUrl': origin}),
      );
      await GetIt.instance<BookDao>().upsert(book);
      final service = DownloadService();
      addTearDown(() async {
        await settle(service);
        service.tasks.removeWhere((t) => t.bookUrl == book.bookUrl);
      });

      await service.keepShelfBookDownloaded(book.bookUrl);
      // 測試沒有網路服務：抓目錄立刻失敗。
      await settle(service);

      Future<DownloadTask> stored() async =>
          (await GetIt.instance<DownloadDao>().getAll()).firstWhere(
            (t) => t.bookUrl == book.bookUrl,
          );
      final failed = await stored();
      expect(failed.isFailed, isTrue);

      await service.keepShelfBookDownloaded(book.bookUrl);

      final after = await stored();
      expect(after.isFailed, isTrue);
      expect(after.lastUpdateTime, failed.lastUpdateTime);
    });

    test('leaves a book that is not on the shelf alone', () async {
      final book = await seed('book/off-shelf', inShelf: false);

      await DownloadService().keepShelfBookDownloaded(book.bookUrl);

      final stored = await GetIt.instance<DownloadDao>().getAll();
      expect(stored.where((t) => t.bookUrl == book.bookUrl), isEmpty);
    });
  });
}

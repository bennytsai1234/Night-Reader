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
import 'package:night_reader/core/services/motion_gate.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';

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

  testWidgets('a run waits while an animation is playing', (tester) async {
    const origin = 'https://waiting.example';
    final book = Book(
      bookUrl: '$origin/book/1',
      origin: origin,
      name: '等動畫的書',
      isInBookshelf: true,
    );
    final service = DownloadService();
    final task = DownloadTask(
      bookUrl: book.bookUrl,
      bookName: book.name,
      totalCount: 3,
    );
    await tester.runAsync(() async {
      await GetIt.instance<BookSourceDao>().upsert(
        BookSource.fromJson({'bookSourceName': '等', 'bookSourceUrl': origin}),
      );
      await GetIt.instance<BookDao>().upsert(book);
      // 測試裡沒有初始化網路服務：每章都立刻失敗，不會真的連網。
      await GetIt.instance<ChapterDao>().insertChapters([
        for (var i = 0; i < 3; i++)
          BookChapter(
            url: 'unsupported://waiting/$i',
            title: '第 $i 章',
            index: i,
            bookUrl: book.bookUrl,
          ),
      ]);
    });
    service.tasks.add(task);
    service.isDownloading = true;
    addTearDown(() {
      service.isDownloading = false;
      service.tasks.removeWhere((t) => t.bookUrl == book.bookUrl);
    });

    // 畫面上有動畫在播：一章都還沒開始抓。
    final release = MotionGate.instance.hold();
    late Future<void> run;
    await tester.runAsync(() async {
      run = service.processTask(task);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(task.errorCount + task.successCount, 0);

    // 動畫播完（再等一幀確定沒有下一段接上）才接著抓。
    release();
    await tester.pump();
    await tester.runAsync(() => run);
    expect(task.errorCount, 3);
  });

  group('the range of a task', () {
    List<BookChapter> toc(List<String> paths) => [
      for (final (i, path) in paths.indexed)
        BookChapter(url: path, title: path, index: i),
    ];
    DownloadTask range({String? from, String? to}) => DownloadTask(
      bookUrl: 'https://book.example',
      bookName: '書',
      startChapterUrl: from,
      endChapterUrl: to,
    );

    test('still means the chapters picked after the source inserts one '
        'before them, plus any inserted inside', () {
      // 排進來時是 [a, b, c, d]，選了 b–c；開跑前書源在前面與中間各插一章。
      final now = toc(['x', 'a', 'b', 'y', 'c', 'd']);

      final picked = chaptersInDownloadScope(now, range(from: 'b', to: 'c'));

      expect(picked!.map((c) => c.url), ['b', 'y', 'c']);
    });

    test('without ends is the whole book, skipping volume headings and '
        'paid chapters', () {
      final now = toc(['a', 'b', 'c', 'd']);
      now[1].isVolume = true;
      now[2].isVip = true;

      final picked = chaptersInDownloadScope(now, range());

      expect(picked!.map((c) => c.url), ['a', 'd']);
    });

    test('is gone when the source removed one of its ends', () {
      final now = toc(['a', 'c', 'd']);

      expect(chaptersInDownloadScope(now, range(from: 'b')), isNull);
      expect(chaptersInDownloadScope(now, range(to: 'b')), isNull);
    });

    test('counts every chapter in it once, downloaded ones as done, even '
        'after a chapter was inserted while queued', () async {
      const origin = 'https://count-range.example';
      final book = Book(
        bookUrl: '$origin/book/1',
        origin: origin,
        name: '插章後的整本',
      );
      await GetIt.instance<BookSourceDao>().upsert(
        BookSource.fromJson({'bookSourceName': '數', 'bookSourceUrl': origin}),
      );
      await GetIt.instance<BookDao>().upsert(book);
      final store = ReaderChapterContentStore(
        chapterDao: GetIt.instance<ChapterDao>(),
        contentDao: GetIt.instance<ReaderChapterContentDao>(),
      );
      // 排進來時 a、b、c 都下載好了（「下載全部」，總數 3）；開跑前書源在
      // 前面插了 x，x 抓不到。
      final downloaded = [
        for (final (i, path) in ['a', 'b', 'c'].indexed)
          BookChapter(
            url: '$origin/$path',
            index: i + 1,
            bookUrl: book.bookUrl,
          ),
      ];
      for (final chapter in downloaded) {
        await store.saveRawContent(book: book, chapter: chapter, content: '正文');
      }
      await GetIt.instance<ChapterDao>().insertChapters([
        BookChapter(url: 'unsupported://x', index: 0, bookUrl: book.bookUrl),
        ...downloaded,
      ]);
      final service = DownloadService();
      final task = DownloadTask(
        bookUrl: book.bookUrl,
        bookName: book.name,
        totalCount: 3,
      );
      service.tasks.add(task);
      service.isDownloading = true;
      addTearDown(() {
        service.isDownloading = false;
        service.tasks.removeWhere((t) => t.bookUrl == book.bookUrl);
      });

      await service.processTask(task);

      expect(task.totalCount, 4);
      expect(task.successCount, 3);
      expect(task.errorCount, 1);
    });

    test('whose first chapter was removed fails with a reason', () async {
      const origin = 'https://gone-range.example';
      final book = Book(
        bookUrl: '$origin/book/1',
        origin: origin,
        name: '刪了起點',
      );
      await GetIt.instance<BookSourceDao>().upsert(
        BookSource.fromJson({'bookSourceName': '刪', 'bookSourceUrl': origin}),
      );
      await GetIt.instance<BookDao>().upsert(book);
      await GetIt.instance<ChapterDao>().insertChapters([
        BookChapter(url: '$origin/c/2', index: 0, bookUrl: book.bookUrl),
      ]);
      final service = DownloadService();
      final task = DownloadTask(
        bookUrl: book.bookUrl,
        bookName: book.name,
        startChapterUrl: '$origin/c/1',
        endChapterUrl: '$origin/c/2',
        totalCount: 2,
      );
      service.tasks.add(task);
      service.isDownloading = true;
      addTearDown(() {
        service.isDownloading = false;
        service.tasks.removeWhere((t) => t.bookUrl == book.bookUrl);
      });

      await service.processTask(task);

      expect(task.isFailed, isTrue);
      expect(task.lastErrorMessage, contains('選的章節已不在目錄裡'));
    });
  });

  test(
    'a task queued before the book had a TOC covers the whole book',
    () async {
      const origin = 'https://late-toc.example';
      final book = Book(
        bookUrl: '$origin/book/1',
        origin: origin,
        name: '晚到的目錄',
        isInBookshelf: true,
      );
      await GetIt.instance<BookSourceDao>().upsert(
        BookSource.fromJson({'bookSourceName': '晚', 'bookSourceUrl': origin}),
      );
      await GetIt.instance<BookDao>().upsert(book);
      // 任務排進來時還沒有目錄；開跑前目錄已被別處（例如閱讀器）抓好。
      await GetIt.instance<ChapterDao>().insertChapters([
        for (var i = 0; i < 3; i++)
          BookChapter(
            url: 'unsupported://late/$i',
            title: '第 $i 章',
            index: i,
            bookUrl: book.bookUrl,
          ),
      ]);
      final service = DownloadService();
      final task = DownloadTask(bookUrl: book.bookUrl, bookName: book.name);
      service.tasks.add(task);
      service.isDownloading = true;
      addTearDown(() {
        service.isDownloading = false;
        service.tasks.removeWhere((t) => t.bookUrl == book.bookUrl);
      });

      await service.processTask(task);

      final finished = service.tasks.firstWhere(
        (t) => t.bookUrl == book.bookUrl,
      );
      expect(finished.totalCount, 3);
      expect(finished.errorCount, 3);
    },
  );

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

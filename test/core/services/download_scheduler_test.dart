import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/download/download_base.dart';
import 'package:night_reader/core/services/download/download_scheduler.dart';

class _FakeBookDao extends Fake implements BookDao {}

class _FakeBookSourceDao extends Fake implements BookSourceDao {}

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeReaderChapterContentDao extends Fake
    implements ReaderChapterContentDao {}

class _RecordingDownloadDao extends Fake implements DownloadDao {
  final List<DownloadTask> upserts = <DownloadTask>[];
  Completer<void>? upsertCompleter;

  @override
  Future<void> upsert(DownloadTask task) async {
    upserts.add(task);
    await upsertCompleter?.future;
  }
}

class _TestDownloadScheduler extends DownloadBase with DownloadScheduler {
  @override
  Future<void> processTask(DownloadTask task) async {}
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<BookDao>(_FakeBookDao());
    getIt.registerSingleton<BookSourceDao>(_FakeBookSourceDao());
    getIt.registerSingleton<ChapterDao>(_FakeChapterDao());
    getIt.registerSingleton<ReaderChapterContentDao>(
      _FakeReaderChapterContentDao(),
    );
    getIt.registerSingleton<DownloadDao>(_RecordingDownloadDao());
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('retiring task 不會再被加入下載佇列', () async {
    final scheduler = _TestDownloadScheduler()..isDownloading = true;
    scheduler.markTaskRetiring('book/retiring');

    await scheduler.addDownloadTask(
      Book(bookUrl: 'book/retiring', name: '換源中的書'),
      <BookChapter>[BookChapter(url: 'chapter/0', index: 0)],
    );

    final dao = getIt<DownloadDao>() as _RecordingDownloadDao;
    expect(dao.upserts, isEmpty);
    expect(scheduler.tasks, isEmpty);
    scheduler.dispose();
  });

  test('retirement signal 會喚醒全域 pause 中的 task', () async {
    final scheduler = _TestDownloadScheduler()
      ..isPaused = true
      ..pauseCompleter = Completer<void>();

    final wait = scheduler.waitUntilTaskRunnable('book/paused');
    await Future<void>.delayed(Duration.zero);
    scheduler.markTaskRetiring('book/paused');

    expect(await wait, isFalse);
    scheduler.dispose();
  });

  test('quiescence 只在 active operation 真正完成後成立', () async {
    final scheduler = _TestDownloadScheduler();
    scheduler.beginTaskActivity('book/active');
    var quiesced = false;
    final wait = scheduler.waitForTaskIdle('book/active').then((_) {
      quiesced = true;
    });

    scheduler.markTaskRetiring('book/active');
    await Future<void>.delayed(Duration.zero);
    expect(quiesced, isFalse);

    scheduler.completeTaskActivity('book/active');
    await wait;
    expect(quiesced, isTrue);
    scheduler.dispose();
  });

  test('quiescence 會等待 in-flight task creation 的 DAO write 完成', () async {
    final scheduler = _TestDownloadScheduler()..isDownloading = true;
    final dao = getIt<DownloadDao>() as _RecordingDownloadDao;
    dao.upsertCompleter = Completer<void>();
    final book = Book(bookUrl: 'book/adding', name: '建立中的任務');
    final chapters = <BookChapter>[BookChapter(url: 'chapter/0', index: 0)];

    final adding = scheduler.addDownloadTask(book, chapters);
    await Future<void>.delayed(Duration.zero);
    expect(dao.upserts, hasLength(1));

    scheduler.markTaskRetiring(book.bookUrl);
    var quiesced = false;
    final wait = scheduler.waitForTaskIdle(book.bookUrl).then((_) {
      quiesced = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(quiesced, isFalse);

    dao.upsertCompleter!.complete();
    await adding;
    await wait;
    expect(quiesced, isTrue);
    scheduler.dispose();
  });

  test('重複加入進行中的任務不會以新等待狀態覆寫資料庫', () async {
    final scheduler = _TestDownloadScheduler()..isDownloading = true;
    final existing = DownloadTask(
      bookUrl: 'book/1',
      bookName: '測試書',
      startChapterIndex: 0,
      endChapterIndex: 2,
      totalCount: 3,
      status: DownloadTask.statusDownloading,
    )..successCount = 2;
    scheduler.tasks.add(existing);

    await scheduler
        .addDownloadTask(Book(bookUrl: 'book/1', name: '測試書'), <BookChapter>[
          BookChapter(url: 'chapter/0', index: 0),
          BookChapter(url: 'chapter/1', index: 1),
          BookChapter(url: 'chapter/2', index: 2),
        ]);

    final dao = getIt<DownloadDao>() as _RecordingDownloadDao;
    expect(dao.upserts, isEmpty);
    expect(scheduler.tasks, <DownloadTask>[existing]);
    expect(scheduler.tasks.single.successCount, 2);
    scheduler.dispose();
  });

  test('背景補內容不會把使用者暫停的任務重新排成 waiting', () async {
    final scheduler = _TestDownloadScheduler()..isDownloading = true;
    final paused = DownloadTask(
      bookUrl: 'book/paused',
      bookName: '暫停中的書',
      startChapterIndex: 3,
      endChapterIndex: 5,
      totalCount: 3,
      status: DownloadTask.statusPaused,
    );
    scheduler.tasks.add(paused);

    final admitted = await scheduler.ensureDownloadTask(
      Book(bookUrl: 'book/paused', name: '暫停中的書'),
      <BookChapter>[
        BookChapter(url: 'chapter/0', index: 0),
        BookChapter(url: 'chapter/1', index: 1),
      ],
    );

    final dao = getIt<DownloadDao>() as _RecordingDownloadDao;
    expect(admitted, isFalse);
    expect(dao.upserts, isEmpty);
    expect(scheduler.tasks.single, same(paused));
    expect(scheduler.tasks.single.status, DownloadTask.statusPaused);
    expect(scheduler.tasks.single.startChapterIndex, 3);
    expect(scheduler.tasks.single.endChapterIndex, 5);
    scheduler.dispose();
  });

  test('背景補內容不會自動重試失敗任務', () async {
    final scheduler = _TestDownloadScheduler()..isDownloading = true;
    final failed = DownloadTask(
      bookUrl: 'book/failed',
      bookName: '失敗中的書',
      startChapterIndex: 0,
      endChapterIndex: 2,
      totalCount: 3,
      status: DownloadTask.statusFailed,
    )..setFailure(reason: 'network', message: 'failed');
    scheduler.tasks.add(failed);

    final admitted = await scheduler.ensureDownloadTask(
      Book(bookUrl: 'book/failed', name: '失敗中的書'),
      <BookChapter>[BookChapter(url: 'chapter/3', index: 3)],
    );

    final dao = getIt<DownloadDao>() as _RecordingDownloadDao;
    expect(admitted, isFalse);
    expect(dao.upserts, isEmpty);
    expect(scheduler.tasks.single, same(failed));
    expect(scheduler.tasks.single.isFailed, isTrue);
    scheduler.dispose();
  });

  test('使用者主動加入仍可取代已暫停任務', () async {
    final scheduler = _TestDownloadScheduler()..isDownloading = true;
    scheduler.tasks.add(
      DownloadTask(
        bookUrl: 'book/manual',
        bookName: '手動下載',
        startChapterIndex: 5,
        endChapterIndex: 8,
        totalCount: 4,
        status: DownloadTask.statusPaused,
      ),
    );

    await scheduler.addDownloadTask(
      Book(bookUrl: 'book/manual', name: '手動下載'),
      <BookChapter>[
        BookChapter(url: 'chapter/1', index: 1),
        BookChapter(url: 'chapter/2', index: 2),
      ],
    );

    final dao = getIt<DownloadDao>() as _RecordingDownloadDao;
    expect(dao.upserts, hasLength(1));
    expect(scheduler.tasks.single.status, DownloadTask.statusWaiting);
    expect(scheduler.tasks.single.startChapterIndex, 1);
    expect(scheduler.tasks.single.endChapterIndex, 2);
    scheduler.dispose();
  });

  test('重新加入已完成任務仍會建立新的等待任務', () async {
    final scheduler = _TestDownloadScheduler()..isDownloading = true;
    scheduler.tasks.add(
      DownloadTask(
        bookUrl: 'book/1',
        bookName: '測試書',
        startChapterIndex: 0,
        endChapterIndex: 0,
        totalCount: 1,
        status: DownloadTask.statusCompleted,
      ),
    );

    await scheduler.addDownloadTask(
      Book(bookUrl: 'book/1', name: '測試書'),
      <BookChapter>[BookChapter(url: 'chapter/0', index: 0)],
    );

    final dao = getIt<DownloadDao>() as _RecordingDownloadDao;
    expect(dao.upserts, hasLength(1));
    expect(scheduler.tasks.single.status, DownloadTask.statusWaiting);
    scheduler.dispose();
  });

  test('已移出清單但仍在收尾的 active 任務不會被新任務覆寫', () async {
    final scheduler = _TestDownloadScheduler()..isDownloading = true;
    scheduler.activeTaskUrls.add('book/1');

    await scheduler.addDownloadTask(
      Book(bookUrl: 'book/1', name: '測試書'),
      <BookChapter>[BookChapter(url: 'chapter/0', index: 0)],
    );

    final dao = getIt<DownloadDao>() as _RecordingDownloadDao;
    expect(dao.upserts, isEmpty);
    expect(scheduler.tasks, isEmpty);
    scheduler.dispose();
  });

  test('兩個併發加入只會保留並寫入一個等待任務', () async {
    final scheduler = _TestDownloadScheduler()..isDownloading = true;
    final dao = getIt<DownloadDao>() as _RecordingDownloadDao;
    dao.upsertCompleter = Completer<void>();
    final book = Book(bookUrl: 'book/concurrent', name: '併發測試書');
    final chapters = <BookChapter>[BookChapter(url: 'chapter/0', index: 0)];

    final first = scheduler.addDownloadTask(book, chapters);
    await Future<void>.delayed(Duration.zero);
    final second = scheduler.addDownloadTask(book, chapters);
    await second;

    expect(dao.upserts, hasLength(1));
    dao.upsertCompleter!.complete();
    await first;
    expect(scheduler.tasks, hasLength(1));
    expect(scheduler.tasks.single.status, DownloadTask.statusWaiting);
    scheduler.dispose();
  });
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
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
}

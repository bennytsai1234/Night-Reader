// 上次沒下載完的書，開 App 時先讀回來、等主頁面說進場播完才接著下載
// （ADR 0018）。下載服務是單例，建立時才讀資料庫，所以獨立一個測試檔。
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

  test('restored downloads start only when asked after launch', () async {
    // 上次關 App 時還在下載。
    await GetIt.instance<DownloadDao>().upsert(
      DownloadTask(
        bookUrl: 'https://book.example',
        bookName: '書',
        status: DownloadTask.statusDownloading,
        totalCount: 10,
      ),
    );

    final service = DownloadService();
    for (var i = 0; i < 20 && service.tasks.isEmpty; i++) {
      await pumpEventQueue();
    }
    await pumpEventQueue();
    expect(service.tasks.single.status, DownloadTask.statusWaiting);
    expect(service.isDownloading, isFalse);

    await service.resumeRestoredDownloads();
    expect(service.isDownloading, isTrue);

    // 書不在資料庫裡，這一輪立刻失敗；等排程停下，測試才能正常結束。
    for (var i = 0; i < 50 && service.isDownloading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(service.tasks.single.status, DownloadTask.statusFailed);
  });
}

// 「暫停全部」重開 App 照樣停著：恢復的任務不開跑（連目錄都不抓），按
// 「繼續全部」才接著下載。下載服務是單例，建立時才讀偏好與資料庫，所以
// 獨立一個測試檔。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      PreferKey.downloadsPausedAll: true,
    });
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

  test('paused-all survives a restart until continued', () async {
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
    expect(service.isPaused, isTrue);

    await service.resumeRestoredDownloads();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    // 沒開跑：書不在資料庫裡，開跑的話這一輪會立刻失敗。
    expect(service.tasks.single.status, DownloadTask.statusWaiting);
    expect(service.isDownloading, isFalse);

    service.togglePause();
    expect(service.isPaused, isFalse);
    for (var i = 0; i < 50 && service.tasks.single.isWaiting; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    for (var i = 0; i < 50 && service.isDownloading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(service.tasks.single.status, DownloadTask.statusFailed);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PreferKey.downloadsPausedAll), isFalse);
  });
}

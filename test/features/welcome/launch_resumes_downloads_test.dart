// 開 App 時接著下載上次沒下載完的書：整段進場都不開跑，播完才接著下載
// （ADR 0018）。下載服務是單例、建立時才讀資料庫，所以獨立一個測試檔。
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/app_providers.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/constant/book_type.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/main.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';
import 'package:provider/provider.dart';

import '../../support/app_harness.dart';

void main() {
  testWidgets('unfinished downloads continue only after the launch entrance', (
    tester,
  ) async {
    const gone = 'https://www.example.com/book/gone/';
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      // 書架上只有本地書：書架補下載不排任何任務，接著下載只能靠主頁面。
      await getIt<BookDao>().upsertAll([
        Book(
          bookUrl: 'local://夜讀.txt',
          origin: BookType.localTag,
          name: '本地書',
          isInBookshelf: true,
        ),
      ]);
      // 上次關 App 時還在下載；書已經不在，開跑後立刻失敗。
      await getIt<DownloadDao>().upsert(
        DownloadTask(
          bookUrl: gone,
          bookName: '不在了',
          status: DownloadTask.statusDownloading,
          totalCount: 10,
        ),
      );
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: AppProviders.providers,
        child: const ReaderApp(),
      ),
    );
    final service = DownloadService();
    LaunchEntranceMotion? entrance;
    var startedDuringEntrance = false;
    for (var i = 0; i < 1000 && !(entrance?.isFinished ?? false); i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 16));
      startedDuringEntrance |= service.isDownloading;
      final shelf = find.byType(BookshelfPage).evaluate();
      if (shelf.isNotEmpty) entrance ??= LaunchEntrance.maybeOf(shelf.first);
    }
    expect(entrance?.isFinished, isTrue, reason: '進場要播完');
    expect(startedDuringEntrance, isFalse, reason: '進場中不接著下載');

    await settle(tester, const Duration(seconds: 2));
    final task = service.tasks.singleWhere((t) => t.bookUrl == gone);
    expect(task.status, DownloadTask.statusFailed, reason: '進場播完要接著下載');

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, const Duration(seconds: 3));
  });
}

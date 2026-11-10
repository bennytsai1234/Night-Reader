// 下載服務整個程式只有一個，建立時從資料庫載入任務、只通知一次，所以這項
// 測試自己一個檔：別的測試先建立過它，這裡就等不到載入。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/features/cache_manager/download_manager_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:provider/provider.dart';

import '../../support/app_harness.dart';
import '../../support/screenshot.dart';

void main() {
  testWidgets('進度的單位照書的類別：小說寫章、漫畫寫話、有聲書寫集', (tester) async {
    setUpScreenshot(tester);
    late DownloadService service;
    await tester.runAsync(() async {
      await setUpApp();
      final books = getIt<BookDao>();
      final downloads = getIt<DownloadDao>();
      // 上次留在資料庫裡、暫停著的三個任務（暫停的載入後不會開跑）。
      for (final (url, name, type, total, done) in [
        ('https://novel.example/1', '小說', SourceType.book, 100, 2),
        ('https://comic.example/1', '漫畫', SourceType.image, 10, 3),
        ('https://audio.example/1', '有聲書', SourceType.audio, 20, 1),
      ]) {
        await books.upsert(
          Book(bookUrl: url, origin: url, name: name, type: type),
        );
        await downloads.upsert(
          DownloadTask(
            bookUrl: url,
            bookName: name,
            totalCount: total,
            successCount: done,
            status: DownloadTask.statusPaused,
          ),
        );
      }
      service = DownloadService();
      final loaded = Completer<void>();
      void onLoaded() => loaded.complete();
      service.addListener(onLoaded);
      await loaded.future;
      service.removeListener(onLoaded);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<DownloadService>.value(
        value: service,
        child: MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: const DownloadManagerPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已暫停 2/100 章'), findsOneWidget);
    expect(find.text('已暫停 3/10 話'), findsOneWidget);
    expect(find.text('已暫停 1/20 集'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    service.tasks.clear();
  });
}

// 背景下載佇列：二十個任務進頁，接著下載中那一本每秒抓完一章、進度更新時
// 每一幀的成本（ADR 0018、0029）：進度只該重建那一列，不是整頁。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試
// 跳過。
@Tags(['frame_budget'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/features/cache_manager/download_manager_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:provider/provider.dart';

import '../support/app_harness.dart';
import '../support/frame_budget.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

const _taskCount = 20;

DownloadTask _task(int i, int now) => DownloadTask(
  bookUrl: 'https://www.example.com/book/$i/',
  bookName: '第 $i 本書：一個有點長的書名',
  totalCount: 300,
  successCount: i == 0 ? 120 : (i * 13) % 300,
  errorCount: i == 6 || i == 7 ? 3 : 0,
  status: switch (i) {
    0 => DownloadTask.statusDownloading,
    < 3 => DownloadTask.statusWaiting,
    < 6 => DownloadTask.statusPaused,
    < 8 => DownloadTask.statusFailed,
    _ => DownloadTask.statusCompleted,
  },
  lastUpdateTime: now - i * 60000,
  sortOrder: i,
);

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('download queue while a task reports progress', (tester) async {
    setUpScreenshot(tester);
    late DownloadService service;
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      service = DownloadService();
      // 讓它從資料庫讀完（空的）再放進任務。
      final loaded = Completer<void>();
      void onLoaded() => loaded.complete();
      service.addListener(onLoaded);
      await loaded.future;
      service.removeListener(onLoaded);
    });
    final now = DateTime(2026, 10, 21, 21).millisecondsSinceEpoch;
    service.tasks.addAll([for (var i = 0; i < _taskCount; i++) _task(i, now)]);
    service.update();

    for (final round in ['第一輪', '第二輪']) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ChangeNotifierProvider<DownloadService>.value(
                            value: service,
                            child: const DownloadManagerPage(),
                          ),
                    ),
                  ),
                  child: const Text('打開下載佇列'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await measureNavigation(
        tester,
        '$round 進背景下載佇列',
        action: () => tester.tap(find.text('打開下載佇列')),
        page: find.byType(DownloadManagerPage),
      );
      await rest(tester);

      // 下載中的那一本每秒抓完一章（同 DownloadExecutor 一章抓完時做的事）。
      final task = service.tasks.first;
      final before = task.successCount;
      var updates = 0;
      final ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
        task.successCount++;
        task.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
        service.update();
        if (++updates == 3) timer.cancel();
      });
      final costs = await recordFrames(
        tester,
        realAsync: true,
        until: () => updates == 3,
        tailFrames: 60,
        note: () => '已下載 ${task.successCount}',
      );
      ticker.cancel();
      expect(updates, 3);
      expect(task.successCount, before + 3);
      // ignore: avoid_print
      print(describeFrames('$round 進度每秒更新三次', costs));

      await measureNavigation(
        tester,
        '$round 下載佇列返回',
        action: () => goBack(tester),
        settled: () => find.text('打開下載佇列').evaluate().isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }
    await tearDownApp(tester);
  });
}

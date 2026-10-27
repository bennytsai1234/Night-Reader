// 臨時：全 App 下載區的動畫儀表板探索（每個使用者操作一步）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';

import '../../support/navigation_budget.dart';
import '../../support/screenshot.dart';
import 'survey_support.dart';

const _area = 'download';
const _taskCount = 20;

/// 任務清單：第 0 本下載中、1–2 等待、3–5 暫停、6–7 失敗、其餘完成。
/// 每次開始都重排（下載服務是單例，上一輪的順序、刪除會留下來）。
DownloadTask _task(int i, int now) {
  final task = DownloadTask(
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
  // 失敗的書要有失敗原因，選單才會有「查看失敗原因」。
  if (i == 6 || i == 7) {
    task.setFailure(
      reason: '網路逾時',
      message: '第 12 章抓取失敗：連線逾時',
      chapterIndex: 11,
    );
  }
  return task;
}

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('survey: download', (tester) async {
    // 下載服務是單例，建構時要讀 GetIt，得等 runSurvey 的 setUpApp 之後才能建。
    late DownloadService service;
    final now = DateTime(2026, 10, 21, 21).millisecondsSinceEpoch;

    void resetTasks() {
      service.tasks
        ..clear()
        ..addAll([for (var i = 0; i < _taskCount; i++) _task(i, now)]);
      service.update();
    }

    // 點任務列上的小按鈕（暫停、繼續、重試）：同一個提示字可能有好幾個，點第一個。
    Finder control(String tip) => find.byTooltip(tip).first;

    await runSurvey(
      tester,
      steps: () async {
        service = DownloadService();
        // 單例第一次建立時從資料庫讀任務（空的），讀完才放進我們的任務，不然會被蓋掉。
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await rest(tester);
        resetTasks();

        await surveyStep(
          tester,
          area: _area,
          key: 'download01',
          label: '點「我的」分頁',
          action: () => tester.tap(
            find.descendant(
              of: find.byType(FloatingTabBar),
              matching: find.text('我的'),
            ),
          ),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'download02',
          label: '點「背景下載佇列」，進佇列',
          action: () => tester.tap(find.text('背景下載佇列')),
        );

        // 下載中那本每秒抓完一章（同 DownloadExecutor 一章抓完時做的事），
        // 一共三次；進度只該重建那一列。
        var updates = 0;
        Timer? ticker;
        await surveyStep(
          tester,
          area: _area,
          key: 'download03',
          label: '下載中的書每秒抓完一章，進度更新三次',
          action: () async {
            final task = service.tasks.first;
            ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
              task.successCount++;
              task.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
              service.update();
              if (++updates == 3) timer.cancel();
            });
          },
          until: () => updates == 3 && surveyQuiet(),
        );
        ticker?.cancel();

        await surveyStep(
          tester,
          area: _area,
          key: 'download04',
          label: '點下載中那本的「暫停」',
          action: () => tester.tap(control('暫停')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'download05',
          label: '點那本的「繼續」',
          action: () => tester.tap(control('繼續')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'download06',
          label: '點頂部「暫停全部」',
          action: () => tester.tap(find.byTooltip('暫停全部')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'download07',
          label: '點頂部「恢復全部」',
          action: () => tester.tap(find.byTooltip('恢復全部')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'download08',
          label: '長按等待中的書，打開任務選單',
          action: () => tester.longPress(find.text('第 2 本書：一個有點長的書名')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'download09',
          label: '選「上移」，任務排到前面',
          action: () => tester.tap(find.text('上移').last),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'download10',
          label: '長按失敗的書，打開任務選單',
          action: () => tester.longPress(find.text('第 6 本書：一個有點長的書名')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'download11',
          label: '選「查看失敗原因」',
          action: () => tester.tap(find.text('查看失敗原因').last),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'download12',
          label: '關閉失敗原因',
          action: () => goBack(tester),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'download13',
          label: '點「清除已完成」',
          action: () => tester.tap(find.byTooltip('清除已完成')),
        );
        await surveyStep(
          tester,
          area: _area,
          key: 'download14',
          label: '返回「我的」',
          action: () => goBack(tester),
        );

        await tester.runAsync(() async {});
        resetTasks();
      },
    );
  });
}

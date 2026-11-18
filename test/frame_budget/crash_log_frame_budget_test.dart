// 崩潰日誌頁：資料夾裡留滿 50 份崩潰日誌、每份都附滿崩潰前紀錄時，從點下去到
// 換頁播完、日誌顯示出來每一幀的成本（ADR 0018）。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試
// 跳過。
@Tags(['frame_budget'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/features/about/crash_log_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

import '../support/app_harness.dart';
import '../support/crash_logs.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('crash log page with a full folder of logs', (tester) async {
    setUpPhone(tester);
    late Directory directory;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('crash_log_budget');
      CrashHandler.logDirectoryForTesting = () async => directory;
      await seedFullCrashLogs(directory);
    });
    addTearDown(() async {
      CrashHandler.resetLogDirectoryForTesting();
      await tester.runAsync(() => directory.delete(recursive: true));
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const CrashLogPage()),
                ),
                child: const Text('打開崩潰日誌'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final round in ['第一輪', '第二輪']) {
      await measureNavigation(
        tester,
        '$round 進崩潰日誌',
        action: () => tester.tap(find.text('打開崩潰日誌')),
        settled: () =>
            pageSettled(find.byType(CrashLogPage)) &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
        note: () => find.byType(CircularProgressIndicator).evaluate().isEmpty
            ? null
            : '讀檔',
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '$round 崩潰日誌返回',
        action: () => goBack(tester),
        settled: () => find.text('打開崩潰日誌').evaluate().isNotEmpty,
      );
      await rest(tester);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

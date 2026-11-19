import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/download/download_failure.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/download/download_service.dart';
import 'package:night_reader/features/downloads/download_manager_page.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:provider/provider.dart';

import '../../support/app_harness.dart';
import '../../support/screenshot.dart';

/// 下載服務是單例，整個檔只載入一次（第二次不會再通知載入完成）。
DownloadService? _service;

Future<DownloadService> loadService(WidgetTester tester) async {
  if (_service case final service?) return service;
  late DownloadService service;
  await tester.runAsync(() async {
    await setUpApp();
    service = DownloadService();
    final loaded = Completer<void>();
    void onLoaded() => loaded.complete();
    service.addListener(onLoaded);
    await loaded.future;
    service.removeListener(onLoaded);
  });
  return _service = service;
}

void main() {
  testWidgets('下載進度只重建對應任務與摘要', (tester) async {
    setUpScreenshot(tester);
    final service = await loadService(tester);
    final downloading = DownloadTask(
      bookUrl: 'https://books.example/1',
      bookName: '下載中的書',
      totalCount: 100,
      successCount: 1,
      status: DownloadTask.statusDownloading,
    );
    service.tasks.addAll([
      downloading,
      DownloadTask(
        bookUrl: 'https://books.example/2',
        bookName: '等待中的書',
        totalCount: 100,
        status: DownloadTask.statusWaiting,
      ),
    ]);
    service.update();
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
    final rebuilt = <Widget>[];
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    downloading.successCount = 2;
    downloading.lastUpdateTime = DateTime(
      2026,
      10,
      21,
      21,
    ).millisecondsSinceEpoch;
    service.update();
    await tester.pumpAndSettle();

    expect(find.text('2 / 100 章'), findsOneWidget);
    expect(
      rebuilt.whereType<Text>().where((text) => text.data == '等待中的書'),
      isEmpty,
      reason: '另一個任務沒有改變，不應跟著進度重建',
    );
    expect(rebuilt.whereType<GlassNavHeader>(), isEmpty);
    expect(rebuilt.whereType<DownloadManagerPage>(), isEmpty);
    debugOnRebuildDirtyWidget = previous;
    await tester.pumpWidget(const SizedBox.shrink());
    service.tasks.clear();
  });

  testWidgets('a failed task reads progress in the plain colour, the reason '
      'in danger, and 「重試失敗的」 queues every failed task again', (tester) async {
    setUpScreenshot(tester);
    final service = await loadService(tester);
    // 重試會叫排程開跑；這個測試只看排回佇列，不真的下載。
    service.isDownloading = true;
    DownloadTask failed(String url, String name) =>
        DownloadTask(
          bookUrl: url,
          bookName: name,
          totalCount: 120,
          successCount: 12,
          errorCount: 15,
          status: DownloadTask.statusFailed,
        )..setFailure(
          reason: DownloadFailure.unreachable.reason,
          message: DownloadFailure.unreachable.message,
          chapterIndex: 26,
        );
    service.tasks.addAll([
      failed('https://books.example/a', '甲書'),
      failed('https://books.example/b', '乙書'),
    ]);
    service.update();
    final theme = buildAppTheme(AppStyle.kraft, Brightness.light);
    await tester.pumpWidget(
      ChangeNotifierProvider<DownloadService>.value(
        value: service,
        child: MaterialApp(theme: theme, home: const DownloadManagerPage()),
      ),
    );
    await tester.pumpAndSettle();

    Color colorOf(String text) =>
        tester.widget<Text>(find.text(text).first).style!.color!;
    expect(
      colorOf('下載失敗：已下載 12/120 章，15 章失敗'),
      AppChrome.of(tester.element(find.byType(DownloadManagerPage)))
          .sectionText,
    );
    expect(
      colorOf('第 27 章：${DownloadFailure.unreachable.message}'),
      AppPalette.rust,
    );

    // 讀屏聚焦到列上的重試鈕也點得了。
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.bySemanticsLabel('重試').first),
      isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
    );
    semantics.dispose();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重試失敗的'));
    await tester.pumpAndSettle();

    expect(service.tasks.every((task) => task.isWaiting), isTrue);
    expect(
      service.tasks.every((task) => task.failureSummary() == null),
      isTrue,
    );
    service.isDownloading = false;
    await tester.pumpWidget(const SizedBox.shrink());
    service.tasks.clear();
  });
}

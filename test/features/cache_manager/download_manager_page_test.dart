import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/features/cache_manager/download_manager_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:provider/provider.dart';

import '../../support/app_harness.dart';
import '../../support/screenshot.dart';

void main() {
  testWidgets('下載進度只重建對應任務與摘要', (tester) async {
    setUpScreenshot(tester);
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
}

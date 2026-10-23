// 背景下載佇列推入時的骨架（ADR 0029）：摘要與每一列各自訂閱下載服務，
// 骨架照現在的值算、不訂閱。下載服務是全域唯一的，和其他用它的測試分開
// 放在自己的檔案。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/features/cache_manager/download_manager_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:provider/provider.dart';

import '../../support/app_harness.dart';
import '../../support/screenshot.dart';
import '../../support/skeleton_match.dart';

void main() {
  testWidgets('有任務時推入，骨架就和摘要與任務列一樣', (tester) async {
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
    service.tasks.addAll([
      DownloadTask(
        bookUrl: 'https://books.example/1',
        bookName: '下載中的書',
        totalCount: 100,
        successCount: 30,
        status: DownloadTask.statusDownloading,
      ),
      DownloadTask(
        bookUrl: 'https://books.example/2',
        bookName: '已經暫停、書名很長很長很長很長很長很長很長很長的書',
        totalCount: 100,
        successCount: 5,
        status: DownloadTask.statusPaused,
      ),
    ]);
    service.update();
    await tester.pumpWidget(
      ChangeNotifierProvider<DownloadService>.value(
        value: service,
        child: MaterialApp(
          theme: buildAppTheme(AppStyle.paper, Brightness.light),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DownloadManagerPage(),
                ),
              ),
              child: const Text('開啟'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開啟'));
    await tester.pump();
    final list = find.byType(GroupedListView, skipOffstage: false);
    final route = ModalRoute.of(tester.element(list))!;
    while (!route.animation!.isCompleted) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final skeleton = skeletonLayoutOf(
      tester,
      find.descendant(of: list, matching: find.byType(SkeletonShapes)),
    );
    expect(skeleton.marks, isNotEmpty);
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonShapes), findsNothing);
    expect(
      skeletonMismatches(
        skeleton,
        contentLayoutOf(tester, list),
        visible: tester.getRect(list),
      ),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    service.tasks.clear();
  });
}

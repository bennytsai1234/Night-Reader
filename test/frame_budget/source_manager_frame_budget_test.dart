// 書源管理：三百個書源進頁（骨架、清單出現）、進出選取時列尾交叉淡換、
// 全選與批次停用、按域名分組切換、搜尋框每打一個字的重建，每一幀的成本
// （ADR 0018、0029）。用法見 `test/support/frame_budget.dart`；帶
// `frame_budget` 標籤，平常的全套測試跳過。資料庫是記憶體資料庫，在主執行
// 緒（手機上在自己的 isolate），「幀前」裡有一部分是它。
@Tags(['frame_budget'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';
import 'package:night_reader/features/source_manager/source_manager_provider.dart';
import 'package:night_reader/features/source_manager/widgets/source_item_tile.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:provider/provider.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

const _sourceCount = 300;

/// 三十個域名各十個書源；分組、發現、備註與停用的都有一些。
BookSource _source(int i) => BookSource.fromJson({
  'bookSourceUrl': 'https://www.site${i % 30}.example/path$i',
  'bookSourceName': '書源 $i',
  'bookSourceGroup': i % 4 == 0
      ? '常用'
      : i % 7 == 0
      ? '繁體,精選'
      : null,
  'bookSourceComment': i % 11 == 0 ? '備註 $i' : null,
  'customOrder': i,
  'enabled': i % 5 != 0,
  'searchUrl': '/search?q={{key}}',
  'exploreUrl': i % 3 == 0 ? '最新::/new' : null,
  'ruleBookInfo': {'name': 'tag.h1@text'},
  'ruleToc': {'chapterList': 'class.toc@tag.a'},
  'ruleContent': {'content': 'id.content@html'},
});

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('source manager with 300 sources', (tester) async {
    setUpScreenshot(tester);
    await tester.runAsync(() async {
      // 上次讀完有三百個書源：骨架照它畫列。
      await setUpApp(prefs: {'source_manager_last_count': _sourceCount});
      await getIt<BookSourceDao>().upsertAll([
        for (var i = 0; i < _sourceCount; i++) _source(i),
      ]);
    });

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
                      builder: (_) => const SourceManagerPage(),
                    ),
                  ),
                  child: const Text('打開書源管理'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await measureNavigation(
        tester,
        '$round 進書源管理',
        action: () => tester.tap(find.text('打開書源管理')),
        page: find.byType(SourceManagerPage),
      );
      await rest(tester);
      final provider = Provider.of<SourceManagerProvider>(
        tester.element(find.byType(SourceItemTile).first),
        listen: false,
      );
      expect(provider.totalSourceCount, _sourceCount);
      final firstUrl = provider.sources.first.bookSourceUrl;

      await measureActivity(
        tester,
        '$round 勾第一個進入選取',
        action: () => provider.toggleSelect(firstUrl),
        tailFrames: 40,
      );
      expect(provider.selectedUrls, {firstUrl});
      await measureActivity(
        tester,
        '$round 全選',
        action: provider.selectAll,
        tailFrames: 20,
      );
      expect(provider.selectedUrls.length, _sourceCount);
      await measureActivity(
        tester,
        '$round 批次停用',
        action: () => unawaited(provider.batchSetEnabled(false)),
        until: () => !provider.isMutationBusy,
        tailFrames: 30,
      );
      expect(provider.allSources.every((source) => !source.enabled), isTrue);
      await measureActivity(
        tester,
        '$round 批次啟用',
        action: () => unawaited(provider.batchSetEnabled(true)),
        until: () => !provider.isMutationBusy,
        tailFrames: 30,
      );
      expect(provider.allSources.every((source) => source.enabled), isTrue);
      await measureActivity(
        tester,
        '$round 取消選取退出',
        action: provider.clearSelection,
        tailFrames: 40,
      );
      expect(provider.selectedUrls, isEmpty);

      await measureActivity(
        tester,
        '$round 按域名分組',
        action: provider.toggleGroupByDomain,
        tailFrames: 30,
      );
      expect(provider.groupByDomain, isTrue);
      await measureActivity(
        tester,
        '$round 取消按域名分組',
        action: provider.toggleGroupByDomain,
        tailFrames: 30,
      );
      expect(provider.groupByDomain, isFalse);

      for (final typed in ['書', '書源', '書源 ', '書源 1', '書源 12']) {
        await measureActivity(
          tester,
          '$round 搜尋框打到「$typed」',
          action: () => tester.enterText(find.byType(TextField), typed),
          tailFrames: 15,
        );
        expect(provider.sources, isNotEmpty);
        expect(
          provider.sources.every(
            (source) => source.bookSourceName.contains(typed.trim()),
          ),
          isTrue,
        );
      }
      await measureActivity(
        tester,
        '$round 清空搜尋框',
        action: () => tester.enterText(find.byType(TextField), ''),
        tailFrames: 20,
      );
      expect(provider.sources.length, _sourceCount);

      await measureNavigation(
        tester,
        '$round 書源管理返回',
        action: () => goBack(tester),
        settled: () => find.text('打開書源管理').evaluate().isNotEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }
    await tearDownApp(tester);
  });
}

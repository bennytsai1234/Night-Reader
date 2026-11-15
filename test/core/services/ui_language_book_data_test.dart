import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/models/bookmark.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/services/ui_language.dart';
import 'package:night_reader/features/bookmarks/bookmarks_page.dart';
import 'package:night_reader/features/cache_manager/download_manager_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/toc_volume_row.dart';
import 'package:provider/provider.dart';

import '../../support/app_harness.dart';

/// 介面是簡體時，書的資料（書名、章名、摘錄）照閱讀偏好的繁簡轉換顯示，
/// 不跟著介面轉成簡體；介面字照介面語言（ADR 0066）。閱讀偏好預設是
/// 簡轉繁，簡體系統的手機裝好就是這個組合。
void main() {
  setUpAll(() {
    if (!ChineseUtils.isInitialized) {
      ChineseUtils.initializeFromDictionaryData([
        for (final path in ChineseUtils.dictionaryAssetPaths)
          File(path).readAsStringSync(),
      ]);
    }
  });
  tearDown(() => ChineseDisplay.mode.value = 0);

  Widget simplifiedApp(Widget home) => MaterialApp(
    theme: buildAppTheme(AppStyle.paper, Brightness.light),
    builder: (context, child) => UiLanguageScope(
      locale: const Locale('zh', 'CN'),
      child: ChineseDisplayScope(child: child!),
    ),
    home: home,
  );

  // (閱讀偏好的繁簡轉換, 存的資料, 該顯示的樣子)
  const cases = [(0, '燈下讀過的話', '燈下讀過的話'), (1, '灯下读过的话', '燈下讀過的話')];

  group('書籤', () {
    late AppDatabase db;

    setUp(() async {
      await GetIt.instance.reset();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      GetIt.instance
        ..registerSingleton<BookmarkDao>(BookmarkDao(db))
        ..registerSingleton<HighlightDao>(HighlightDao(db))
        ..registerSingleton<ReadRecordDao>(ReadRecordDao(db));
    });

    tearDown(() async {
      await db.close();
      await GetIt.instance.reset();
    });

    for (final (mode, stored, shown) in cases) {
      testWidgets('閱讀偏好 $mode：摘錄、章名、書名照閱讀偏好，分頁名稱是簡體', (tester) async {
        ChineseDisplay.mode.value = mode;
        final bookmark = Bookmark(
          id: 1,
          bookName: mode == 0 ? '夜雨聽書' : '夜雨听书',
          bookAuthor: '作者',
          chapterIndex: 0,
          chapterTitle: mode == 0 ? '第一章 燈下' : '第一章 灯下',
          charOffset: 0,
          excerpt: stored,
        );
        await tester.runAsync(
          () => GetIt.instance<BookmarkDao>().upsertAll([bookmark]),
        );
        await tester.pumpWidget(
          simplifiedApp(BookmarksPage(initial: [bookmark])),
        );
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(find.text(shown), findsOneWidget);
        expect(find.text('第一章 燈下'), findsOneWidget);
        expect(find.text('夜雨聽書'), findsOneWidget);
        expect(find.text('书签'), findsWidgets, reason: '介面字照介面語言');

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 10));
      });
    }
  });

  testWidgets('目錄的分卷名照閱讀偏好', (tester) async {
    for (final (mode, stored, shown) in cases) {
      ChineseDisplay.mode.value = mode;
      await tester.pumpWidget(
        simplifiedApp(
          Builder(
            builder: (context) => Scaffold(
              body: TocVolumeRow(title: context.zh(stored), count: 3),
            ),
          ),
        ),
      );
      expect(find.text(shown), findsOneWidget);
    }
  });

  testWidgets('下載佇列的書名照閱讀偏好', (tester) async {
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
    for (final (mode, stored, shown) in cases) {
      ChineseDisplay.mode.value = mode;
      service.tasks
        ..clear()
        ..add(
          DownloadTask(
            bookUrl: 'https://books.example/1',
            bookName: stored,
            totalCount: 100,
            status: DownloadTask.statusWaiting,
          ),
        );
      service.update();
      await tester.pumpWidget(
        ChangeNotifierProvider<DownloadService>.value(
          value: service,
          child: simplifiedApp(const DownloadManagerPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(shown), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    service.tasks.clear();
  });
}

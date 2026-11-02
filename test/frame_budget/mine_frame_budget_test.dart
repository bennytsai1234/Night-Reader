// 「我的」每一列點進去的頁面與搜尋頁：進場與返回每一幀的成本，從點下去到
// 換頁播完、骨架換成內容後再一秒（ADR 0018）。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試
// 跳過。
@Tags(['frame_budget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/about/about_page.dart';
import 'package:night_reader/features/cache_manager/download_manager_page.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/settings/appearance_settings_page.dart';
import 'package:night_reader/features/settings/backup_sync_page.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/features/settings/reading_stats_page.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/features/settings/tts_settings_page.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

/// 「資料與隱私」用網頁元件，測試環境畫不出來，不列。
const _rows = <(String, Type)>[
  ('閱讀偏好', ReadingSettingsPage),
  ('外觀與主題', AppearanceSettingsPage),
  ('朗讀與語音', TtsSettingsPage),
  ('閱讀統計', ReadingStatsPage),
  ('書源管理', SourceManagerPage),
  ('背景下載佇列', DownloadManagerPage),
  ('備份與同步', BackupSyncPage),
  ('關於夜讀', AboutPage),
];

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('pages behind the Me tab and search', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      await seedSiteSource();
      await installFakeSite();
    });
    await pumpApp(tester);
    await rest(tester);

    for (final round in ['第一輪', '第二輪']) {
      await measureNavigation(
        tester,
        '$round 書架→搜尋頁',
        action: () => tester.tap(find.byIcon(Icons.search_rounded).last),
        page: find.byType(SearchPage),
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '$round 搜尋頁返回書架',
        action: () => goBack(tester),
        page: find.byType(BookshelfPage),
      );
      await rest(tester);
    }

    await tester.tap(
      find.descendant(
        of: find.byType(FloatingTabBar),
        matching: find.text('我的'),
      ),
    );
    await rest(tester);
    for (final round in ['第一輪', '第二輪']) {
      for (final (row, type) in _rows) {
        await tester.ensureVisible(find.text(row));
        await tester.pump();
        await measureNavigation(
          tester,
          '$round 我的→$row',
          action: () => tester.tap(find.text(row)),
          page: find.byType(type),
        );
        await rest(tester);
        await measureNavigation(
          tester,
          '$round $row返回我的',
          action: () => goBack(tester),
          page: find.byType(SettingsPage),
        );
        await rest(tester);
      }
    }

    await tearDownApp(tester);
  });
}

// 整個 App 的固定一組畫面：改完介面後重拍，跟改之前的圖對照。
//
//   flutter test --run-skipped -t screens test/screens
//   SHOT_MODE=dark flutter test --run-skipped -t screens test/screens
//   SHOT_ONLY=r04,s12 flutter test --run-skipped -t screens test/screens
//   SHOT_STYLE=plain flutter test --run-skipped -t screens test/screens
//
// SHOT_STYLE 是 `AppStyle` 的名稱（paper、bamboo、azurite、tea、plain、rouge、
// lotus、scroll、amber、frost），預設紙墨。
//
// 圖檔寫在 [screenshotDir]，檔名是「情境_深淺.png」。這組測試帶 `screens`
// 標籤，`dart_test.yaml` 讓它平常跳過，pre-push 與 CI 的全套測試不會跑。
// 截圖環境畫不出玻璃模糊與網頁元件。文字沒有字族（例如自帶 textStyle 蓋掉主題）
// 時會畫成方塊，這在手機上看不出來，但通常表示該沿用主題字型。
@Tags(['screens'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import '../support/app_harness.dart';
import '../support/screenshot.dart';

typedef Steps = Future<void> Function(WidgetTester tester);

Future<void> tapText(WidgetTester tester, String text, {int index = 0}) async {
  await tester.tap(find.text(text).at(index), warnIfMissed: false);
  await settle(tester, const Duration(milliseconds: 900));
}

Future<void> tapIcon(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon).last, warnIfMissed: false);
  await settle(tester, const Duration(milliseconds: 900));
}

Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
  final byTooltip = find.byTooltip(tooltip);
  await tester.tap(
    byTooltip.evaluate().isNotEmpty
        ? byTooltip.last
        : find.bySemanticsLabel(tooltip).last,
    warnIfMissed: false,
  );
  await settle(tester, const Duration(milliseconds: 900));
}

Future<void> openMine(WidgetTester tester, String row) async {
  await tapText(tester, '我的');
  await tapText(tester, row);
  // 設定各頁推入時先是骨架，一格建一列（ADR 0029）；這裡一步推 50ms，比
  // 手機慢得多，等骨架換完再拍。
  for (var i = 0; i < 100; i++) {
    if (find.byType(SkeletonShapes).evaluate().isEmpty) break;
    await settle(tester, const Duration(milliseconds: 100));
  }
}

Future<void> openReaderMenu(WidgetTester tester) async {
  await openReader(tester);
  await showReaderMenu(tester);
}

final scenarios = <String, (Map<String, Object>, Steps)>{
  // 書架與主頁。
  's01_shelf_grid': (const {}, (t) async {}),
  's02_shelf_list': (const {'bookshelf_is_grid': false}, (t) async {}),
  's03_shelf_organize': (const {}, (t) async => tapTooltip(t, '整理書架')),
  's04_shelf_add': (const {}, (t) async => tapTooltip(t, '加入書籍')),
  's05_shelf_longpress': (
    const {},
    (t) async {
      await t.longPress(find.text('夜雨聽書').first);
      await settle(t, const Duration(milliseconds: 900));
    },
  ),
  's06_explore': (const {}, (t) async => tapText(t, '發現')),
  's07_mine': (const {}, (t) async => tapText(t, '我的')),
  's08_search': (const {}, (t) async => tapTooltip(t, '搜尋')),
  's09_detail': (
    const {},
    (t) async {
      await t.longPress(find.text('夜雨聽書').first);
      await settle(t, const Duration(milliseconds: 900));
      await tapText(t, '書籍詳情');
    },
  ),
  // 我的。
  's10_stats': (const {}, (t) async => openMine(t, '閱讀統計')),
  's11_reading_prefs': (const {}, (t) async => openMine(t, '閱讀偏好')),
  's12_sources': (const {}, (t) async => openMine(t, '書源管理')),
  's13_downloads': (const {}, (t) async => openMine(t, '背景下載佇列')),
  's15_appearance': (const {}, (t) async => openMine(t, '外觀與主題')),
  's16_tts': (const {}, (t) async => openMine(t, '朗讀與語音')),
  's17_backup': (const {}, (t) async => openMine(t, '備份與還原')),
  's18_about': (const {}, (t) async => openMine(t, '關於夜讀')),
  's19_release_notes': (
    const {},
    (t) async {
      await openMine(t, '關於夜讀');
      await tapText(t, '更新紀錄');
    },
  ),
  // 閱讀器。
  'r01_reader': (const {}, (t) async => openReader(t)),
  'r02_menu': (const {}, openReaderMenu),
  'r03_toc': (
    const {},
    (t) async {
      await openReaderMenu(t);
      await tapText(t, '目錄');
    },
  ),
  'r04_layout': (
    const {},
    (t) async {
      await openReaderMenu(t);
      await tapText(t, '排版');
    },
  ),
  'r06_advanced': (
    const {},
    (t) async {
      await openReaderMenu(t);
      await tapText(t, '進階');
    },
  ),
  'r07_tts': (
    const {},
    (t) async {
      await openReaderMenu(t);
      await tapText(t, '朗讀');
    },
  ),
  'r08_more': (
    const {},
    (t) async {
      await openReaderMenu(t);
      await tapTooltip(t, '更多');
    },
  ),
  'r09_replace': (
    const {},
    (t) async {
      await openReaderMenu(t);
      await tapIcon(t, Icons.find_replace);
    },
  ),
  'r10_header_hidden_bar': (
    const {'hideStatusBar': true, 'reader_header_info': '1,4'},
    (t) async => openReader(t),
  ),
  // 上下邊距各 16：正文與頁首頁尾之間有空隙，跨邊的那一行在空隙裡漸隱。
  'r12_reader_margins': (
    const {
      'reader_padding_top': 16.0,
      'reader_padding_bottom': 16.0,
      'reader_header_info': '1,4',
    },
    (t) async => openReader(t),
  ),
  'r11_menu_hidden_bar': (
    const {'hideStatusBar': true, 'reader_header_info': '1,4'},
    openReaderMenu,
  ),
};

void main() {
  setUpAll(loadScreenshotFonts);
  final mode = Platform.environment['SHOT_MODE'] ?? 'light';
  final only = Platform.environment['SHOT_ONLY']?.split(',');
  final style = Platform.environment['SHOT_STYLE'];

  // 全部情境在同一個測試裡依序拍：App 的單例服務（下載服務等）第一次用到
  // 時就綁在當下測試的非同步環境，換到下一個測試就不會再回應，開書會一直
  // 停在載入中。每個情境之間只換偏好設定、重建整個 App。
  testWidgets('app screens', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    for (final MapEntry(key: name, value: (prefs, steps))
        in scenarios.entries) {
      if (only != null && !only.any(name.startsWith)) continue;
      await tester.runAsync(
        () => resetPrefs({
          'themeMode': mode,
          PreferKey.appStyle: ?style,
          ...prefs,
        }),
      );
      await pumpApp(tester);
      await steps(tester);
      if (name.startsWith('r')) await waitForText(tester);
      await shot(tester, '${name}_$mode');
      // 拆掉整個 App，下一個情境從頭建。
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, const Duration(milliseconds: 300));
    }
    // 讓 App 留下的計時器（下載排程、重試）跑完，測試才能正常結束。
    await tester.pump(const Duration(minutes: 1));
  });
}

// 在設定頁改一個設定（開關、步進）那一幀與之後幾幀的成本（ADR 0018、
// 0029 做法 3）：改的是一小塊，整個 App 不該跟著重建。`FRAME_ATTRIBUTE=1`
// 時另外加總這段期間每個重建起點的次數，看頁面層級（App 根部、被蓋住的
// 書架與「我的」、目前這一頁）有沒有被排進重建。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試
// 跳過。
@Tags(['frame_budget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/services/tts_service.dart';
import 'package:night_reader/features/about/about_page.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/features/settings/tts_settings_page.dart';
import 'package:night_reader/features/welcome/main_page.dart';
import 'package:night_reader/main.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/frame_budget.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('changing a setting on a settings page', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    await pumpApp(tester);
    await rest(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(FloatingTabBar),
        matching: find.text('我的'),
      ),
    );
    await rest(tester);

    // 關於夜讀：「啟動時檢查書架更新」走 SettingsProvider，App 根部聽著它。
    await _open(tester, '關於夜讀', find.byType(AboutPage));
    await tester.ensureVisible(find.text('啟動時檢查書架更新'));
    await rest(tester);
    for (final round in ['第一次', '第二次']) {
      await _measureChange(
        tester,
        '關於夜讀 $round 切換「啟動時檢查書架更新」',
        action: () => tester.tap(find.text('啟動時檢查書架更新')),
      );
      await rest(tester);
    }
    await goBack(tester);
    await rest(tester);

    // 閱讀偏好：步進與開關走頁面自己的控制器。
    await _open(tester, '閱讀偏好', find.byType(ReadingSettingsPage));
    await _measureChange(
      tester,
      '閱讀偏好 字級「＋」',
      action: () => tester.tap(find.byIcon(Icons.add_rounded).first),
    );
    await rest(tester);
    await tester.ensureVisible(find.text('左右對齊'));
    await rest(tester);
    await _measureChange(
      tester,
      '閱讀偏好 切換「左右對齊」',
      action: () => tester.tap(find.text('左右對齊')),
    );
    await rest(tester);
    await goBack(tester);
    await rest(tester);

    // 朗讀與語音沒有開關，量真正的語速步進，確認值有送進朗讀服務。
    await _open(tester, '朗讀與語音', find.byType(TtsSettingsPage));
    final rate = TTSService().rate;
    await _measureChange(
      tester,
      '朗讀與語音 語速「＋」',
      action: () => tester.tap(find.byIcon(Icons.add_rounded).first),
    );
    expect(TTSService().rate, closeTo(rate + TTSService.rateStep, 0.0001));
    await rest(tester);
    await goBack(tester);
    await rest(tester);

    await tearDownApp(tester);
  });
}

/// 從「我的」點進 [row]，等換頁播完、骨架換完。
Future<void> _open(WidgetTester tester, String row, Finder page) async {
  await tester.ensureVisible(find.text(row));
  await tester.pump();
  await tester.tap(find.text(row));
  for (var i = 0; i < 200 && !(pageSettled(page) && !skeletonShown()); i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(pageSettled(page), isTrue, reason: '$row 沒有播完');
  expect(skeletonShown(), isFalse, reason: '$row 骨架沒有換完');
  await rest(tester);
}

/// 做 [action]（點開關、按步進）後量接下來的 [frames] 幀；印出摘要，
/// `FRAME_ATTRIBUTE=1` 時再印這段期間每個重建起點的合計次數。
Future<List<FrameCost>> _measureChange(
  WidgetTester tester,
  String label, {
  required Future<void> Function() action,
  int frames = 30,
}) async {
  final previousRebuild = debugOnRebuildDirtyWidget;
  final pageBuilds = {
    for (final type in [
      ReaderApp,
      MaterialApp,
      MainPage,
      BookshelfPage,
      SettingsPage,
      AboutPage,
      ReadingSettingsPage,
      TtsSettingsPage,
    ])
      type: 0,
  };
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    final type = element.widget.runtimeType;
    if (pageBuilds.containsKey(type)) {
      pageBuilds[type] = pageBuilds[type]! + 1;
    }
    previousRebuild?.call(element, builtOnce);
  };
  try {
    return await _recordChange(tester, label, action: action, frames: frames);
  } finally {
    debugOnRebuildDirtyWidget = previousRebuild;
    // ignore: avoid_print
    print(
      '  頁面重建：'
      '${pageBuilds.entries.map((entry) => '${entry.key}×${entry.value}').join('、')}',
    );
  }
}

Future<List<FrameCost>> _recordChange(
  WidgetTester tester,
  String label, {
  required Future<void> Function() action,
  required int frames,
}) async {
  final clock = Stopwatch()..start();
  await action();
  final tap = clock.elapsedMicroseconds;
  var remaining = frames;
  final costs = await recordFrames(
    tester,
    realAsync: true,
    until: () => --remaining <= 0,
  );
  final all = [
    FrameCost(
      index: -1,
      beforeFrame: tap,
      frame: 0,
      afterFrame: 0,
      async: 0,
      top: const [],
      dirty: const {},
      note: '點下去',
    ),
    ...costs,
  ];
  // ignore: avoid_print
  print(describeFrames(label, all, over: const Duration(milliseconds: 4)));
  if (frameAttribution) {
    final dirty = <String, int>{};
    for (final cost in costs) {
      for (final MapEntry(:key, :value) in cost.dirty.entries) {
        dirty[key] = (dirty[key] ?? 0) + value;
      }
    }
    final entries = dirty.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // ignore: avoid_print
    print(
      '  重建起點合計（${entries.length} 種）：'
      '${entries.map((e) => '${e.key}×${e.value}').join('、')}',
    );
  }
  return all;
}

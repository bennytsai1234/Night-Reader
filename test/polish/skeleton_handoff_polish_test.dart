// 細節檢查：骨架換成內容時長度與位置對不對得上（`test/support/skeleton_handoff.dart`）。
// 每個情境照真的流程操作，淺色、深色各跑一次。
//
//   flutter test --run-skipped -t polish test/polish
//   POLISH_ONLY=open-a flutter test --run-skipped -t polish test/polish
//   POLISH_MODES=light flutter test --run-skipped -t polish test/polish
//
// 結果印在輸出裡（`POLISH` 開頭的行），截圖與資料寫在 [polishDir]
// （系統暫存區，不在 repo 裡），`tool/polish_viewer/` 拿它做成總覽頁。這組測試
// 帶 `polish` 標籤，`dart_test.yaml` 讓它平常跳過。
//
// 電量是一個 App 一份的靜態值：這次執行裡第一次開閱讀器時還沒收到電量，
// 之後的情境都已經有了（和手機上開 App 後第一次、第二次開書一樣）。
@Tags(['polish'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';
import '../support/skeleton_handoff.dart';

/// 細節檢查的輸出資料夾。
final Directory polishDir = Directory(
  '${Directory.systemTemp.path}${Platform.pathSeparator}night-reader-polish',
);

typedef Steps = Future<void> Function(WidgetTester tester);

/// 頁首頁尾放滿每一種欄位：A、B 兩組合起來八種都有。代碼見
/// `ReaderV2InfoItem`。
const _infoA = {
  PreferKey.readerHeaderInfo: '2,8', // 書名｜電量（含圖示）
  PreferKey.readerFooterInfo: '3,6', // 章節名稱｜全書進度
};
const _infoB = {
  PreferKey.readerHeaderInfo: '4,1', // 章節序號｜時間
  PreferKey.readerFooterInfo: '5,7', // 本章進度｜電量
};

Future<void> _none(WidgetTester tester) async {}

Future<void> _tapBook(WidgetTester tester) =>
    tester.tap(find.text('夜雨聽書').first);

/// 讀過一次再回書架：閱讀器記下了離開時那一頁，下次開書骨架照它畫。
Future<void> _readOnceAndBack(WidgetTester tester) async {
  await openReader(tester);
  await goBack(tester);
  await settle(tester, const Duration(milliseconds: 1500));
}

Future<void> _openDetail(WidgetTester tester) async {
  await tester.longPress(find.text('夜雨聽書').first);
  await settle(tester, const Duration(milliseconds: 900));
  await tester.tap(find.text('書籍詳情'));
  await settle(tester, const Duration(milliseconds: 1500));
}

Future<void> _openMenu(WidgetTester tester) async {
  await openReader(tester);
  await showReaderMenu(tester);
}

/// 情境：名稱 →（總覽頁上的說明、偏好設定、操作前先做的事、要看的那一下）。
final scenarios = <String, (String, Map<String, Object>, Steps, Steps)>{
  'open-a': ('書架開書（A 組欄位）', _infoA, _none, _tapBook),
  'open-b': ('書架開書（B 組欄位）', _infoB, _none, _tapBook),
  'reopen-a': ('讀過再開（A 組欄位）', _infoA, _readOnceAndBack, _tapBook),
  'reopen-b': ('讀過再開（B 組欄位）', _infoB, _readOnceAndBack, _tapBook),
  'detail-a': (
    '書籍詳情「繼續閱讀」（A 組欄位）',
    _infoA,
    _openDetail,
    (t) => t.tap(find.text('繼續閱讀')),
  ),
  'next-a': (
    '選單「下一章」（A 組欄位）',
    _infoA,
    _openMenu,
    (t) => t.tap(find.text('下一章')),
  ),
  'next-b': (
    '選單「下一章」（B 組欄位）',
    _infoB,
    _openMenu,
    (t) => t.tap(find.text('下一章')),
  ),
};

void main() {
  setUpAll(loadScreenshotFonts);
  final only = Platform.environment['POLISH_ONLY']?.split(',');
  final modes =
      Platform.environment['POLISH_MODES']?.split(',') ??
      const ['light', 'dark'];

  // 全部情境在同一個測試裡依序跑，理由同 `test/screens/app_screens_test.dart`。
  testWidgets('skeleton handoff', (tester) async {
    setUpPhone(tester);
    mockBattery();
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      if (polishDir.existsSync()) polishDir.deleteSync(recursive: true);
      polishDir.createSync(recursive: true);
    });
    final runs = <Map<String, Object?>>[];
    final selected = [
      for (final name in scenarios.keys)
        if (only == null || only.any(name.startsWith)) name,
    ];
    var done = 0;
    for (final name in selected) {
      final (title, prefs, before, action) = scenarios[name]!;
      for (final mode in modes) {
        final run = '$name-$mode';
        await tester.runAsync(() => resetPrefs({'themeMode': mode, ...prefs}));
        await pumpApp(tester);
        await before(tester);
        final watch = await watchSkeletonHandoffs(
          tester,
          () => action(tester),
          capture: (shot) async =>
              (await saveScreenshot(tester, '$run-$shot', dir: polishDir)).path,
        );
        final findings = watch.findings();
        done += 1;
        // ignore: avoid_print
        print(
          'POLISH $done/${selected.length * modes.length} $run：'
          '${!watch.sawAny
              ? '沒看到骨架'
              : findings.isEmpty
              ? '全部對得上'
              : '${findings.length} 處對不上'}',
        );
        for (final finding in findings) {
          // ignore: avoid_print
          print('POLISH   ${finding.replaceAll('\n', '\nPOLISH   ')}');
        }
        runs.add({
          'scenario': name,
          'title': title,
          'mode': mode,
          'infoSlots': prefs,
          'check': 'skeleton_handoff',
          'sawSkeleton': watch.sawAny,
          'slots': watch.toJson(),
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester, const Duration(milliseconds: 300));
      }
    }
    await tester.runAsync(
      () =>
          File('${polishDir.path}${Platform.pathSeparator}report.json')
              .writeAsString(const JsonEncoder.withIndent(' ').convert(runs)),
    );
    // 讓 App 留下的計時器（下載排程、重試）跑完，測試才能正常結束。
    await tester.pump(const Duration(minutes: 1));
  });
}

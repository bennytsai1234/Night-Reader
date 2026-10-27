// 臨時：全 App 動畫儀表板探索的「我的」區（下半）：閱讀偏好、朗讀與語音、閱讀
// 統計、背景下載佇列、備份與還原、關於夜讀。上半（外觀與主題）在
// `mine_survey_test.dart`。不碰會連網、會開系統分享或選檔、會刪資料的項目（見
// 報告）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/read_record.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/number_stepper_row.dart';

import '../../support/navigation_budget.dart';
import '../../support/screenshot.dart';
import 'survey_support.dart';

const _area = 'mine2';

/// 目前這一頁的清單（頁面在最上層，取最後一個）。
Finder get _list => find.byType(GroupedListView).last;

/// 把 [target] 捲到看得到；還沒蓋出來的先捲過去找。
Future<void> _show(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      100,
      scrollable: find
          .descendant(of: _list, matching: find.byType(Scrollable))
          .first,
    );
  }
  await tester.ensureVisible(target.first);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _show(tester, target);
  await tester.tap(target.first);
}

/// 點清單裡的一列（或一段控制）的文字。
Future<void> _tapInList(WidgetTester tester, String text) =>
    _tap(tester, find.descendant(of: _list, matching: find.text(text)));

/// 點選單、動作表、確認框裡的一項。這些浮在最上層，同一個字在下面的列上也
/// 可能有，取最後一個（畫在最上面的那個）。
Future<void> _tapTop(WidgetTester tester, String text) =>
    tester.tap(find.text(text).last);

/// 按某個分組標題（排版、版面、點擊區域）右上角的「恢復預設」。清單是懶建的，
/// 標題捲到看得到，按鈕在它所屬的那一組裡找，不靠全畫面第幾個。
Future<void> _tapResetOf(WidgetTester tester, String header) async {
  await _show(tester, _listText(header));
  final section = find.ancestor(
    of: _listText(header),
    matching: find.byType(GroupedSection),
  );
  await tester.tap(
    find
        .descendant(
          of: section,
          matching: find.widgetWithText(TextButton, '恢復預設'),
        )
        .first,
  );
}

Finder _listText(String text) =>
    find.descendant(of: _list, matching: find.text(text));

/// 點點擊區域九宮格的第 [cell] 格（0 起算，左上到右下）。
Future<void> _tapCell(WidgetTester tester, int cell) async {
  final grid = find.byType(GridView).last;
  await _show(tester, grid);
  await tester.tap(
    find.descendant(of: grid, matching: find.byType(InkWell)).at(cell),
  );
}

/// 數值步進列的「加」鍵（按的是那一列，不是畫面上別列的）。
Finder _plus(String label) => find.descendant(
  of: find.ancestor(
    of: find.text(label),
    matching: find.byType(NumberStepperRow),
  ),
  matching: find.byIcon(Icons.add_rounded),
);

Future<void> _tapPlus(WidgetTester tester, String label) =>
    _tap(tester, _plus(label));

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('survey: mine (reading, tts, stats, about)', (tester) async {
    Future<void> tapTab(String label) => tester.tap(
      find.descendant(
        of: find.byType(FloatingTabBar),
        matching: find.text(label),
      ),
    );

    await runSurvey(
      tester,
      steps: () async {
        var i = 0;
        Future<void> step(String label, Future<void> Function() action) {
          i++;
          return surveyStep(
            tester,
            area: _area,
            key: 'minez${i.toString().padLeft(2, '0')}',
            label: label,
            action: action,
            // 點下去後第一格路由還沒蓋出來，不設下限會在 31 格就被當成停了。
            minFrames: 20,
          );
        }

        // ---------- 閱讀偏好 ----------
        await step('點分頁：書架→我的', () => tapTab('我的'));
        await step('進入閱讀偏好', () => _tapInList(tester, '閱讀偏好'));
        await step(
          '向上捲動閱讀偏好',
          () => tester.fling(_list, const Offset(0, -700), 3000),
        );
        await step(
          '向下捲回閱讀偏好頂部',
          () => tester.fling(_list, const Offset(0, 900), 3000),
        );
        await step('字號：加', () => _tapPlus(tester, '字號'));
        await step('標題字號：加', () => _tapPlus(tester, '標題字號'));
        await step('行高：加', () => _tapPlus(tester, '行高'));
        await step('字距：加', () => _tapPlus(tester, '字距'));
        await step('段距：加', () => _tapPlus(tester, '段距'));
        await step('章節間距：加', () => _tapPlus(tester, '章節間距'));
        for (final indent in const ['0 字', '1 字', '4 字', '2 字']) {
          await step('首行縮排：選$indent', () => _tapInList(tester, indent));
        }
        await step('排版：恢復預設', () => _tapResetOf(tester, '排版'));
        await step('左右邊距：加', () => _tapPlus(tester, '左右邊距'));
        await step('左右對齊：切換', () => _tapInList(tester, '左右對齊'));
        await step('上邊距：加', () => _tapPlus(tester, '上邊距'));
        await step('下邊距：加', () => _tapPlus(tester, '下邊距'));
        await step('頁尾位置：加', () => _tapPlus(tester, '頁尾位置'));
        await step('版面：恢復預設', () => _tapResetOf(tester, '版面'));
        await step('隱藏系統狀態列：切換', () => _tapInList(tester, '隱藏系統狀態列'));
        // 頁首左側：九種資訊項目各選一次，最後選回不顯示。
        for (final item in const [
          '時間',
          '書名',
          '章節名稱',
          '章節序號',
          '本章進度',
          '全書進度',
          '電量',
          '電量（含圖示）',
          '不顯示',
        ]) {
          await step('頁首左側：開選單', () => _tapInList(tester, '頁首左側'));
          await step('頁首左側：選$item', () => _tapTop(tester, item));
        }
        await step('自動翻頁速度：加', () => _tapPlus(tester, '速度'));
        for (final mode in const ['簡轉繁', '繁轉簡', '不轉換']) {
          await step('繁簡轉換：選$mode', () => _tapInList(tester, mode));
        }
        // 點擊區域：九格中的五格各換一種功能（中央格換成朗讀），再把左上角換回喚起選單。
        for (final (cell, action) in const [
          (0, '下一頁'),
          (1, '上一頁'),
          (2, '下一章'),
          (3, '上一章'),
          (4, '朗讀'),
          (0, '喚起選單'),
        ]) {
          await step('點擊區域第${cell + 1}格：開選單', () => _tapCell(tester, cell));
          await step(
            '點擊區域第${cell + 1}格：選$action',
            () => _tapTop(tester, action),
          );
        }
        await step('點擊區域：恢復預設', () => _tapResetOf(tester, '點擊區域'));
        await step('音量鍵翻頁：切換', () => _tapInList(tester, '音量鍵翻頁'));
        await step('返回我的（離開閱讀偏好）', () => goBack(tester));

        // ---------- 朗讀與語音 ----------
        await step('進入朗讀與語音', () => _tapInList(tester, '朗讀與語音'));
        await step('語速：加', () => _tapPlus(tester, '語速'));
        await step('音調：加', () => _tapPlus(tester, '音調'));
        await step('語音引擎：開選單', () => _tapInList(tester, '語音引擎'));
        await step('語音引擎：選系統預設', () => _tapTop(tester, '系統預設'));
        await step('返回我的（離開朗讀與語音）', () => goBack(tester));

        // ---------- 閱讀統計 ----------
        // 測試資料庫裡還沒有閱讀紀錄，統計頁只會是空的；放一筆固定代號的紀錄（書是
        // 書架上的「夜雨聽書」），統計頁才有列可點、可進書籍詳情。
        await tester.runAsync(
          () => getIt<ReadRecordDao>().upsert(
            ReadRecord(
              id: 1,
              bookName: '夜雨聽書',
              readTime: 1234,
              lastRead: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
        );
        await step('進入閱讀統計', () => _tapInList(tester, '閱讀統計'));
        await step(
          '點第一筆閱讀紀錄',
          () => _tap(
            tester,
            find.descendant(of: _list, matching: find.byType(GroupedRow)).first,
          ),
        );
        await step('返回閱讀統計', () => goBack(tester));
        await step('返回我的（離開閱讀統計）', () => goBack(tester));

        // ---------- 背景下載佇列 ----------
        await step('進入背景下載佇列', () => _tapInList(tester, '背景下載佇列'));
        await step('返回我的（離開下載佇列）', () => goBack(tester));

        // ---------- 備份與還原（建立備份、還原會開系統分享與選檔，不碰） ----------
        await step('進入備份與還原', () => _tapInList(tester, '備份與還原'));
        await step('返回我的（離開備份與還原）', () => goBack(tester));

        // ---------- 關於夜讀 ----------
        await step('進入關於夜讀', () => _tapInList(tester, '關於夜讀'));
        await step('開源許可證', () => _tapInList(tester, '開源許可證'));
        await step('返回關於夜讀（許可證）', () => goBack(tester));
        await step('免責聲明：開', () => _tapInList(tester, '免責聲明'));
        await step('免責聲明：我已閱讀並知曉', () => _tapTop(tester, '我已閱讀並知曉'));
        await step('隱私說明', () => _tapInList(tester, '隱私說明'));
        await step('返回關於夜讀（隱私）', () => goBack(tester));
        await step('權限', () => _tapInList(tester, '權限'));
        await step('返回關於夜讀（權限）', () => goBack(tester));
        await step('更新紀錄', () => _tapInList(tester, '更新紀錄'));
        await step('返回關於夜讀（更新紀錄）', () => goBack(tester));
        await step('崩潰日誌', () => _tapInList(tester, '崩潰日誌'));
        // 清除日誌的確認框沒有日誌時開不出來（那顆鈕停用），這裡不列。
        await step('返回關於夜讀（崩潰日誌）', () => goBack(tester));
        // 自動更新：三種模式各選一次，最後選回自動檢查。
        for (final mode in const ['不自動', 'Wi-Fi 下自動下載', '自動檢查']) {
          await step('自動更新：開選單', () => _tapInList(tester, '自動更新'));
          await step('自動更新：選$mode', () => _tapTop(tester, mode));
        }
        await step('接收測試版更新：切換', () => _tapInList(tester, '接收測試版更新'));
        await step('啟動時檢查書架更新：切換', () => _tapInList(tester, '啟動時檢查書架更新'));
        await step('清除網頁資料：開確認', () => _tapInList(tester, '清除網頁資料'));
        await step('清除網頁資料：取消', () => _tapTop(tester, '取消'));
        await step('返回我的（離開關於夜讀）', () => goBack(tester));
      },
    );
  });
}

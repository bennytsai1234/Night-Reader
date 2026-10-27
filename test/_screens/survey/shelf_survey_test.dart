// 臨時：全 App 探索「書架」區。書架上 26 本（6 本加 20 本），操作照書架上
// 的每一個按鈕、選單項目與多選工具列；不刪書、不刪書源。
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';
import '../../support/screenshot.dart';
import 'survey_support.dart';

const _area = 'shelf';

/// 書架的捲動區（書架頁裡的第一個可捲動的東西）。
Finder get _shelfScroll => find
    .descendant(
      of: find.byType(BookshelfPage),
      matching: find.byType(Scrollable),
    )
    .first;

/// 點頁首的圖示按鈕（同 `app_screens_test.dart` 的 tapTooltip）。
Future<void> _tooltip(WidgetTester tester, String tooltip) {
  final byTooltip = find.byTooltip(tooltip);
  return tester.tap(
    byTooltip.evaluate().isNotEmpty
        ? byTooltip.last
        : find.bySemanticsLabel(tooltip).last,
  );
}

/// 點畫面上的文字（選單、工具列、對話框的按鈕）；選單與對話框在最上層，取最後一個。
Future<void> _text(WidgetTester tester, String text) =>
    tester.tap(find.text(text).last);

Future<void> _longPressBook(WidgetTester tester) =>
    tester.longPress(find.text('夜雨聽書').first);

Future<void> _tapBook(WidgetTester tester, String name) =>
    tester.tap(find.text(name).first);

/// 點選單外面關掉（選單的遮罩點了就關，不選任何項目）。
Future<void> _dismiss(WidgetTester tester) =>
    tester.tapAt(const Offset(196, 780));

/// 批次檢查更新進行中（工具列的進度字樣，或結束後的整理中）。
bool _batchBusy() =>
    find.textContaining('正在檢查更新').evaluate().isNotEmpty ||
    find.textContaining('正在整理更新結果').evaluate().isNotEmpty;

/// 單本檢查更新進行中（長按選單那一本，底下的提示列）。
bool _singleCheckBusy() => find.textContaining('正在檢查《').evaluate().isNotEmpty;

Future<void> _steps(WidgetTester tester) async {
  var n = 0;
  Future<void> step(
    String label,
    Future<void> Function() action, {
    Future<void> Function(int frame)? onFrame,
    int minFrames = 0,
    bool Function()? until,
  }) {
    n++;
    return surveyStep(
      tester,
      area: _area,
      key: 'shelf${n.toString().padLeft(2, '0')}',
      label: label,
      action: action,
      onFrame: onFrame,
      minFrames: minFrames,
      until: until,
    );
  }

  Future<void> none() async {}
  Future<void> openArrange() => _tooltip(tester, '整理書架');
  Future<void> openAdd() => _tooltip(tester, '加入書籍');
  Future<void> openBookMenu() => _longPressBook(tester);

  // 捲動：甩、慢拖、再甩回頂（顯示順序從最近閱讀開始，第一本在最上面）。
  await step(
    '書架：往上甩',
    () => tester.fling(_shelfScroll, const Offset(0, -900), 4000),
  );
  await step(
    '書架：往下甩回頂',
    () => tester.fling(_shelfScroll, const Offset(0, 900), 4000),
  );
  await step(
    '書架：慢慢往上拖',
    none,
    onFrame: dragOnFrames(
      tester,
      from: tester.getCenter(find.byType(BookshelfPage)),
      delta: const Offset(0, -300),
    ),
    minFrames: 14,
  );
  await step(
    '書架：往下甩回頂',
    () => tester.fling(_shelfScroll, const Offset(0, 900), 4000),
  );

  // 網格與列表。
  await step('整理書架：打開', openArrange);
  await step('切換成列表', () => _text(tester, '列表'));
  await step('整理書架：打開', openArrange);
  await step('切換成網格', () => _text(tester, '網格'));

  // 統一封面：打開、再關回去（全域設定，還原才不影響之後的重跑）。
  await step('整理書架：打開', openArrange);
  await step('統一封面：打開', () => _text(tester, '統一封面'));
  await step('整理書架：打開', openArrange);
  await step('統一封面：關回去', () => _text(tester, '統一封面'));

  // 排序：每一項各選一次（最後以預設的「最近閱讀」收尾）。
  for (final mode in ['書名', '作者', '更新時間', '加入時間', '自訂排序', '最近閱讀']) {
    await step('整理書架：打開', openArrange);
    await step('排序：$mode', () => _text(tester, mode));
  }

  // 整理選單與加入選單：點外面關掉、進搜尋頁再返回、開網址匯入對話框再取消。
  await step('整理書架：打開', openArrange);
  await step('整理書架：點外面關掉', () => _dismiss(tester));
  await step('加入書籍：打開', openAdd);
  await step('加入書籍：點外面關掉', () => _dismiss(tester));
  await step('加入書籍：打開', openAdd);
  await step('搜尋書籍：進搜尋頁', () => _text(tester, '搜尋書籍'));
  await step('搜尋頁：返回書架', () => goBack(tester));
  await step('加入書籍：打開', openAdd);
  await step('從網址匯入書架：開對話框', () => _text(tester, '從網址匯入書架'));
  await step('網址對話框：取消', () => _text(tester, '取消'));

  // 長按書籍的選單：點外面關掉、看詳情再返回、自動檢查更新關掉再開回來、
  // 檢查更新（單本）。
  await step('長按書籍：開選單', openBookMenu);
  await step('書籍選單：點外面關掉', () => _dismiss(tester));
  await step('長按書籍：開選單', openBookMenu);
  await step('書籍選單：書籍詳情', () => _text(tester, '書籍詳情'));
  await step('詳情：返回書架', () => goBack(tester));
  await step('長按書籍：開選單', openBookMenu);
  await step('書籍選單：自動檢查更新關掉', () => _text(tester, '自動檢查更新'));
  await step('長按書籍：開選單', openBookMenu);
  await step('書籍選單：自動檢查更新開回來', () => _text(tester, '自動檢查更新'));
  await step('長按書籍：開選單', openBookMenu);
  await step(
    '書籍選單：檢查更新（單本）',
    () => _text(tester, '檢查更新'),
    until: () => surveyQuiet() && !_singleCheckBusy(),
  );

  // 多選（從長按選單進入，夜雨聽書已選）：點星河彼岸、刪除開確認框再取消、
  // 全選、全不選、各點一本、工具列檢查更新（批次結束時自動退出多選）。
  await step('長按書籍：開選單', openBookMenu);
  await step('書籍選單：選取', () => _text(tester, '選取'));
  await step('多選：點星河彼岸', () => _tapBook(tester, '星河彼岸'));
  await step('工具列：刪除，開確認框', () => _text(tester, '刪除'));
  await step('確認框：取消', () => _text(tester, '取消'));
  await step('多選：全選', () => _text(tester, '全選'));
  await step('多選：全不選', () => _text(tester, '全不選'));
  await step('多選：點夜雨聽書', () => _tapBook(tester, '夜雨聽書'));
  await step('多選：點星河彼岸', () => _tapBook(tester, '星河彼岸'));
  await step(
    '工具列：檢查更新（批次）',
    () => _text(tester, '檢查更新'),
    until: () => surveyQuiet() && !_batchBusy(),
  );

  // 整理選單的「選取」：進多選、點一本、按完成退出。
  await step('整理書架：打開', openArrange);
  await step('整理書架：選取', () => _text(tester, '選取'));
  await step('多選：點夜雨聽書', () => _tapBook(tester, '夜雨聽書'));
  await step('多選：完成退出', () => _text(tester, '完成'));

  // 再從整理選單進多選，用返回鍵退出。
  await step('整理書架：打開', openArrange);
  await step('整理書架：選取', () => _text(tester, '選取'));
  await step('多選：返回鍵退出', () => goBack(tester));

  // 下拉：背景檢查更新。
  await step(
    '書架：下拉檢查更新',
    none,
    onFrame: dragOnFrames(
      tester,
      from: const Offset(196, 300),
      delta: const Offset(0, 220),
    ),
    minFrames: 14,
  );
}

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('survey: shelf', (tester) async {
    await runSurvey(
      tester,
      launch: () async {
        // 書架 26 本，才有得捲；開 App 本身不錄（launch 區錄）。
        await tester.runAsync(() => seedMoreBooks(20));
        await pumpApp(tester);
      },
      steps: () => _steps(tester),
    );
  });
}

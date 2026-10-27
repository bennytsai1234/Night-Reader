// 臨時：全 App 探索「書籍詳情與目錄」區（test/_screens 被 git 忽略）。
//
// 從書架長按進詳情、頁首按鈕（換源、加入書架的移出確認只按取消、更多→預下載章節）、
// 目錄（定位、正序倒序、搜尋）、目錄甩動與拖快速捲軸、目錄點一章進閱讀器、從詳情的
// 「繼續閱讀」進閱讀器，再一路返回書架。
//
// 順序有講究：頁首與目錄的按鈕捲出畫面後就找不到（測試的 finder 跳過捲出去的區塊），
// 所以按鈕類步驟都排在目錄甩動之前。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/book_detail/widgets/book_read_capsule.dart';
import 'package:night_reader/features/book_detail/widgets/change_source_sheet.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/chapter_scrollbar.dart';

import '../../support/navigation_budget.dart';
import '../../support/screenshot.dart';
import 'survey_support.dart';

const _area = 'book';

/// 連續 [frames] 格「條件成立而且畫面也停了」才算停下（擋住還在動的中途）。
bool Function() _steady(bool Function() ok, {int frames = 40}) {
  var run = 0;
  return () {
    run = ok() && surveyQuiet() ? run + 1 : 0;
    return run >= frames;
  };
}

/// 拖動手勢，起點在第 0 格才決定（快速捲軸的位置要等畫面上有了才知道）。
Future<void> Function(int frame) _dragFrom(
  WidgetTester tester,
  Offset Function() from,
  Offset delta, {
  int frames = 12,
}) {
  TestGesture? gesture;
  return (frame) async {
    if (frame == 0) {
      gesture = await tester.startGesture(
        from(),
        kind: PointerDeviceKind.touch,
      );
    } else if (frame <= frames) {
      await gesture!.moveBy(delta / frames.toDouble());
    } else if (frame == frames + 1) {
      await gesture!.up();
    }
  };
}

/// 快速捲軸的拖曳鈕（[ChapterScrollbar] 裡有垂直拖動的那一個）。
Finder get _thumb => find.descendant(
  of: find.byType(ChapterScrollbar),
  matching: find.byWidgetPredicate(
    (w) => w is GestureDetector && w.onVerticalDragStart != null,
  ),
);

/// 閱讀器已經開好：路由到位、沒有在重排（紙由 surveyQuiet 管）。
/// 不用 hasStableWorld：從詳情開的閱讀器它一直是 false，但紙已經掀開、畫面不動。
bool _readerReady(WidgetTester tester) {
  if (find.byType(HybridReaderScreen).evaluate().isEmpty) return false;
  final runtime = tester
      .widget<HybridReaderScreen>(find.byType(HybridReaderScreen))
      .runtime;
  return pageSettled(find.byType(ReaderV2Page)) &&
      runtime.stateMachine.currentOperation == null;
}

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('survey: book', (tester) async {
    final detail = find.byType(BookDetailPage);
    final detailScroll = find.descendant(
      of: detail,
      matching: find.byType(CustomScrollView),
    );

    Future<void> step(
      String key,
      String label,
      Future<void> Function() action, {
      bool Function()? until,
      Future<void> Function(int frame)? onFrame,
      int minFrames = 0,
    }) => surveyStep(
      tester,
      area: _area,
      key: key,
      label: label,
      action: action,
      until: until,
      onFrame: onFrame,
      minFrames: minFrames,
    );

    await runSurvey(
      tester,
      steps: () async {
        await step(
          'book01',
          '書架長按「夜雨聽書」→打開書的選單',
          () => tester.longPress(find.text('夜雨聽書').first),
          until: _steady(() => find.text('書籍詳情').evaluate().isNotEmpty),
        );
        await step(
          'book02',
          '選單點「書籍詳情」→詳情頁進來',
          () => tester.tap(find.text('書籍詳情')),
          until: _steady(() => pageSettled(detail)),
        );
        await step(
          'book03',
          '頁首點「換源」→換源面板打開',
          () => tester.tap(find.text('換源')),
          until: _steady(
            () => find.byType(ChangeSourceSheet).evaluate().isNotEmpty,
          ),
        );
        await step(
          'book04',
          '換源面板關掉',
          () => goBack(tester),
          until: _steady(
            () => find.byType(ChangeSourceSheet).evaluate().isEmpty,
          ),
        );
        await step(
          'book05',
          '頁首點「已在書架」→移出書架的確認框打開',
          () => tester.tap(find.text('已在書架')),
          until: _steady(
            () => find.byType(AppAlert<bool>).evaluate().isNotEmpty,
          ),
        );
        await step(
          'book06',
          '確認框點「取消」（書留在書架）',
          () => tester.tap(
            find.descendant(
              of: find.byType(AppAlert<bool>),
              matching: find.text('取消'),
            ),
          ),
          until: _steady(() => find.byType(AppAlert<bool>).evaluate().isEmpty),
        );
        await step(
          'book07',
          '頁首點「更多」→選單打開',
          () => tester.tap(find.byTooltip('更多')),
          until: _steady(() => find.text('預下載章節').evaluate().isNotEmpty),
        );
        await step(
          'book08',
          '選單點「預下載章節」→下載選單打開',
          () => tester.tap(find.text('預下載章節')),
          until: _steady(() => find.text('下載全書').evaluate().isNotEmpty),
        );
        await step(
          'book09',
          '下載選單關掉',
          () => goBack(tester),
          until: _steady(() => find.text('下載全書').evaluate().isEmpty),
        );
        await step('book10', '點「目錄」→捲到目錄', () => tester.tap(find.text('目錄')));
        await step(
          'book11',
          '點「目前正序」→改成倒序',
          () => tester.tap(find.byTooltip('目前正序')),
        );
        await step(
          'book12',
          '點「目前倒序」→改回正序',
          () => tester.tap(find.byTooltip('目前倒序')),
        );
        await step(
          'book13',
          '點「搜尋目錄」→搜尋框打開',
          () => tester.tap(find.byTooltip('搜尋目錄')),
          until: _steady(
            () => find.byType(AppAlert<void>).evaluate().isNotEmpty,
          ),
        );
        await step(
          'book14',
          '搜尋框輸入「11」→目錄只剩相符的章',
          () => tester.enterText(
            find.descendant(
              of: find.byType(AppAlert<void>),
              matching: find.byType(EditableText),
            ),
            '11',
          ),
        );
        await step(
          'book15',
          '搜尋框點「關閉」',
          () => tester.tap(
            find.descendant(
              of: find.byType(AppAlert<void>),
              matching: find.text('關閉'),
            ),
          ),
          until: _steady(() => find.byType(AppAlert<void>).evaluate().isEmpty),
        );
        await step(
          'book16',
          '點「清除目錄搜尋」',
          () => tester.tap(find.byTooltip('清除目錄搜尋')),
        );
        // 定位會把列表捲走，頁首與目錄的按鈕就看不到了，所以排在最後。
        await step(
          'book17',
          '點「定位目前閱讀章節」',
          () => tester.tap(find.byTooltip('定位目前閱讀章節')),
        );
        await step(
          'book18',
          '目錄內甩動',
          () => tester.fling(detailScroll, const Offset(0, -700), 3000),
        );
        await step(
          'book19',
          '拖目錄快速捲軸（先輕捲一下讓它出現）',
          () => tester.fling(detailScroll, const Offset(0, -20), 200),
          onFrame: _dragFrom(
            tester,
            () => tester.getCenter(_thumb.first),
            const Offset(0, 120),
          ),
          minFrames: 14,
        );
        await step(
          'book20',
          '目錄點一章→閱讀器開在那一章',
          () => tester.tap(find.textContaining('書頁之間').hitTestable().first),
          until: _steady(() => _readerReady(tester)),
        );
        await step(
          'book21',
          '閱讀器返回詳情',
          () => goBack(tester),
          until: _steady(() => pageSettled(detail)),
        );
        await step(
          'book22',
          '詳情點「繼續閱讀」→閱讀器打開',
          () => tester.tap(find.byType(BookReadCapsule)),
          until: _steady(() => _readerReady(tester)),
        );
        await step(
          'book23',
          '閱讀器返回詳情',
          () => goBack(tester),
          until: _steady(() => pageSettled(detail)),
        );
        await step(
          'book24',
          '詳情返回書架',
          () => goBack(tester),
          until: _steady(() => pageSettled(find.byType(BookshelfPage))),
        );
      },
    );
  });
}

// 閱讀器裡開書與跳章以外的互動，每一幀的成本（ADR 0018、0029）：叫出與
// 收起選單、打開幾千章的目錄並在裡面甩動與拖快速捲軸、從目錄點一章、從
// 選單開外觀與排版、朗讀、替換規則面板，步進字號、行高與語速，拖章節
// 進度條、點擊翻頁與自動翻頁。量的範圍從點下去（或手勢的第一步）開始，
// 到動畫播完、正文排好，
// 再多看一秒。用法見 `test/support/frame_budget.dart`；帶 `frame_budget`
// 標籤，平常的全套測試跳過。
@Tags(['frame_budget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/loading_veil.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/hybrid_scroll_controller.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/widgets/chapter_scrollbar.dart';
import 'package:night_reader/shared/widgets/glass.dart';

import '../support/app_harness.dart';
import '../support/frame_budget.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

/// 幾千章的網路小說。
const int _chapterCount = 3000;

/// 從目錄點過去的那一章（目錄中段，和目前位置差很遠）。
const int _jumpTarget = 1500;

/// 把 `seedLibrary` 的那本書補到 [_chapterCount] 章；跳過去的那一章前後
/// 各幾章有正文（閱讀器會預先取前後幾章）。
Future<void> _seedLongBook() async {
  final book = (await getIt<BookDao>().getByUrl(kBookUrl))!;
  final chapters = [
    for (var i = kChapterTitles.length; i < _chapterCount; i++)
      BookChapter(
        url: '${kBookUrl}c$i.html',
        title: '第$i章 書頁之間（$i）',
        bookUrl: kBookUrl,
        index: i,
      ),
  ];
  await getIt<ChapterDao>().insertChapters(chapters);
  final store = ReaderChapterContentStore(
    chapterDao: getIt<ChapterDao>(),
    contentDao: getIt<ReaderChapterContentDao>(),
  );
  for (var index = _jumpTarget - 8; index <= _jumpTarget + 8; index++) {
    await store.saveRawContent(
      book: book,
      chapter: chapters[index - kChapterTitles.length],
      content: chapterText(index),
      saveChapterMetadata: false,
    );
  }
}

bool _veilCovering() => find
    .byType(LoadingVeil)
    .evaluate()
    .any((e) => (e.widget as LoadingVeil).controller.isVisible);

/// 畫面上每一塊滑進滑出的玻璃（上下選單、亮度條）都停在 [shown]。
bool _glassAt(double shown) {
  final slides = find.byType(GlassSlide).evaluate();
  return slides.isNotEmpty &&
      slides.every((e) => (e.widget as GlassSlide).shown == shown);
}

bool _menuShown() => _glassAt(1);
bool _menuHidden() => _glassAt(0);

ReaderV2Runtime _runtime(WidgetTester tester) =>
    tester.widget<HybridReaderScreen>(find.byType(HybridReaderScreen)).runtime;

HybridScrollPosition _textPosition(WidgetTester tester) {
  final view = tester.widget<CustomScrollView>(
    find.descendant(
      of: find.byType(HybridReaderScreen),
      matching: find.byType(CustomScrollView),
    ),
  );
  return view.controller!.position as HybridScrollPosition;
}

Finder get _drawerList => find.descendant(
  of: find.byType(ReaderV2ChaptersDrawer),
  matching: find.byType(ListView),
);

/// 目錄完全滑到位（抽屜左緣貼齊畫面左緣）。
bool _drawerOpen() {
  final drawers = find.byType(Drawer).evaluate();
  if (drawers.isEmpty) return false;
  final box = drawers.first.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero).dx.abs() < 0.5;
}

bool _drawerGone() => find.byType(Drawer).evaluate().isEmpty;

/// 面板所在的路由已滑到位；不讀取依賴路由狀態的 ModalRoute.of。
bool _sheetSettled() {
  final sheets = find.byType(BottomSheet).evaluate();
  if (sheets.isEmpty) return false;
  return pageRouteOf(sheets.first)?.animation?.isCompleted ?? false;
}

/// 一個手勢：第 0 幀按下，接著每幀移一步，走完放開；放開後的那一幀起
/// [released] 為 true。
class _FrameGesture {
  _FrameGesture(
    this.tester,
    this.at, {
    required this.step,
    required this.steps,
  });

  final WidgetTester tester;
  final Offset at;
  final Offset step;
  final int steps;
  TestGesture? _gesture;
  bool released = false;

  Future<void> onFrame(int frame) async {
    final timeStamp = Duration(milliseconds: 16 * frame);
    if (frame == 0) {
      _gesture = await tester.startGesture(at);
    } else if (frame <= steps) {
      await _gesture!.moveBy(step, timeStamp: timeStamp);
    } else if (!released) {
      await _gesture!.up(timeStamp: timeStamp);
      released = true;
    }
  }
}

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('reader interactions', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp(
        prefs: {
          // 右邊一欄點了翻下一頁，其餘叫出選單。
          PreferKey.readerClickActions: [
            for (var row = 0; row < 3; row++) ...[
              ReaderV2TapAction.menu.code,
              ReaderV2TapAction.menu.code,
              ReaderV2TapAction.nextPage.code,
            ],
          ].join(','),
        },
      );
      await seedLibrary();
      await _seedLongBook();
      // 沒正文的章節向書源要時走假的網路，不是沒初始化的網路層。
      await installFakeSite();
    });
    await pumpApp(tester);
    await rest(tester);
    await openReader(tester);
    await rest(tester);

    const centre = Offset(196, 420);
    final runtime = _runtime(tester);

    for (final round in ['第一輪', '第二輪']) {
      // 選單滑入、滑出。
      await measureNavigation(
        tester,
        '$round 點正文→叫出選單',
        action: () => tester.tapAt(centre),
        settled: _menuShown,
        note: () => '選單滑入',
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '$round 點正文→收起選單',
        action: () => tester.tapAt(centre),
        settled: _menuHidden,
        note: () => '選單滑出',
      );
      await rest(tester);

      // 幾千章的目錄：打開、甩動、拖快速捲軸、點一章跳過去。
      await tester.tapAt(centre);
      await settle(tester, const Duration(milliseconds: 800));
      await measureNavigation(
        tester,
        '$round 點「目錄」→目錄滑到位',
        action: () => tester.tap(find.text('目錄')),
        settled: _drawerOpen,
        note: () => '目錄滑入',
      );
      await rest(tester);

      final list = tester.widget<ListView>(_drawerList);
      final listCentre = tester.getCenter(_drawerList);
      final fling = _FrameGesture(
        tester,
        listCentre,
        step: const Offset(0, -60),
        steps: 8,
      );
      await measureNavigation(
        tester,
        '$round 目錄內甩動',
        action: () async {},
        settled: () =>
            fling.released &&
            !list.controller!.position.isScrollingNotifier.value,
        note: () => fling.released ? '慣性' : '拖動',
        onFrame: fling.onFrame,
      );

      // 停下 1.5 秒內拖曳鈕還在；拖它跨過幾百章。
      final thumb = find.descendant(
        of: find.byType(ChapterScrollbar),
        matching: find.byWidgetPredicate(
          (w) => w is GestureDetector && w.onVerticalDragStart != null,
        ),
      );
      expect(thumb, findsOneWidget, reason: '$round 快速捲軸沒出現');
      final drag = _FrameGesture(
        tester,
        tester.getCenter(thumb),
        step: const Offset(0, 6),
        steps: 20,
      );
      await measureNavigation(
        tester,
        '$round 拖目錄快速捲軸',
        action: () async {},
        settled: () => drag.released,
        note: () => '拖動',
        onFrame: drag.onFrame,
      );
      await rest(tester);

      // 捲到跳過去的那一章，點它。
      list.controller!.jumpTo((_jumpTarget - 4) * (list.itemExtent ?? 56.0));
      await settle(tester, const Duration(milliseconds: 300));
      final target = find.text('第$_jumpTarget章 書頁之間（$_jumpTarget）');
      expect(target, findsOneWidget, reason: '$round 目錄裡找不到目標章');
      await measureNavigation(
        tester,
        '$round 目錄點一章→目錄收起、紙蓋上、正文出來',
        action: () => tester.tap(target),
        settled: () =>
            _drawerGone() &&
            runtime.stateMachine.currentOperation == null &&
            !_veilCovering(),
        note: () =>
            [if (!_drawerGone()) '目錄收起', if (_veilCovering()) '紙'].join('、'),
      );
      await rest(tester);
      expect(runtime.state.visibleLocation.chapterIndex, _jumpTarget);

      // 從選單開面板：選單滑出與面板滑入同時；面板裡步進字號；關面板。
      await tester.tapAt(centre);
      await settle(tester, const Duration(milliseconds: 800));
      await measureNavigation(
        tester,
        '$round 點「排版」→面板滑入、選單滑出',
        action: () => tester.tap(find.text('排版')),
        settled: () => _sheetSettled() && _menuHidden(),
        note: () => '面板滑入',
      );
      await rest(tester);

      var relayoutSeen = false;
      await measureNavigation(
        tester,
        '$round 面板裡字號 +0.5→正文重排、紙掀開',
        action: () => tester.tap(find.bySemanticsLabel('增加字號')),
        settled: () {
          final busy = runtime.stateMachine.currentOperation != null;
          relayoutSeen |= busy;
          return relayoutSeen && !busy && !_veilCovering();
        },
        note: () => _veilCovering() ? '紙' : '等提交',
      );
      await rest(tester);
      relayoutSeen = false;
      await measureNavigation(
        tester,
        '$round 面板裡字號 −0.5→正文重排、紙掀開',
        action: () => tester.tap(find.bySemanticsLabel('減少字號')),
        settled: () {
          final busy = runtime.stateMachine.currentOperation != null;
          relayoutSeen |= busy;
          return relayoutSeen && !busy && !_veilCovering();
        },
        note: () => _veilCovering() ? '紙' : '等提交',
      );
      await rest(tester);
      relayoutSeen = false;
      await measureNavigation(
        tester,
        '$round 面板裡行高 +0.1→正文重排、紙掀開',
        action: () => tester.tap(find.bySemanticsLabel('增加行高')),
        settled: () {
          final busy = runtime.stateMachine.currentOperation != null;
          relayoutSeen |= busy;
          return relayoutSeen && !busy && !_veilCovering();
        },
        note: () => _veilCovering() ? '紙' : '等提交',
      );
      await rest(tester);
      await measureNavigation(
        tester,
        '$round 關面板→選單滑回',
        action: () => goBack(tester),
        settled: () =>
            find.byType(BottomSheet).evaluate().isEmpty && _menuShown(),
        note: () => '面板滑出',
      );
      await rest(tester);

      for (final label in ['朗讀', '替換規則']) {
        await measureNavigation(
          tester,
          '$round 點「$label」→面板滑入、選單滑出',
          action: () => tester.tap(
            label == '替換規則' ? find.byTooltip(label) : find.text(label),
          ),
          settled: () => _sheetSettled() && _menuHidden(),
          note: () => '面板滑入',
        );
        await rest(tester);
        if (label == '朗讀') {
          await tester.ensureVisible(find.bySemanticsLabel('增加語速'));
          await rest(tester);
          await measureNavigation(
            tester,
            '$round 朗讀面板步進語速',
            action: () => tester.tap(find.bySemanticsLabel('增加語速')),
            settled: () => _sheetSettled(),
          );
          await rest(tester);
        }
        await measureNavigation(
          tester,
          '$round 關「$label」面板→選單滑回',
          action: () => goBack(tester),
          settled: () =>
              find.byType(BottomSheet).evaluate().isEmpty && _menuShown(),
          note: () => '面板滑出',
        );
        await rest(tester);
      }

      // 拖章節進度條，放開後跳到那一段。
      final slider = find.byType(Slider);
      final beforeScrub = runtime.state.visibleLocation;
      final sliderBox = tester.getRect(slider);
      final scrub = _FrameGesture(
        tester,
        Offset(sliderBox.left + 24, sliderBox.center.dy),
        step: const Offset(10, 0),
        steps: 12,
      );
      var scrubSettledFrames = 0;
      await measureNavigation(
        tester,
        '$round 拖章節進度條→放開跳到那一段',
        action: () async {},
        settled: () {
          if (!scrub.released ||
              runtime.stateMachine.currentOperation != null) {
            scrubSettledFrames = 0;
            return false;
          }
          return ++scrubSettledFrames >= 3;
        },
        note: () => scrub.released ? '放開後' : '拖動',
        onFrame: scrub.onFrame,
      );
      await rest(tester);
      expect(
        runtime.state.visibleLocation,
        isNot(beforeScrub),
        reason: '$round 拖章節進度條必須真的改變閱讀位置',
      );
      await tester.tapAt(centre);
      await settle(tester, const Duration(milliseconds: 800));
      expect(_menuHidden(), isTrue);

      // 點右欄翻下一頁，連點兩下。
      final position = _textPosition(tester);
      await measureNavigation(
        tester,
        '$round 點擊翻頁（一下）',
        action: () => tester.tapAt(const Offset(340, 420)),
        settled: () => !position.isPageTurning,
        note: () => '翻頁',
      );
      await rest(tester);
      var secondTapDone = false;
      await measureNavigation(
        tester,
        '$round 點擊翻頁（連點兩下）',
        action: () => tester.tapAt(const Offset(340, 420)),
        settled: () => secondTapDone && !position.isPageTurning,
        note: () => '翻頁',
        onFrame: (frame) async {
          if (frame == 6) {
            await tester.tapAt(const Offset(340, 420));
            secondTapDone = true;
          }
        },
      );
      await rest(tester);

      // 自動翻頁：開著捲三秒。
      await tester.tapAt(centre);
      await settle(tester, const Duration(milliseconds: 800));
      await tester.tap(find.byTooltip('開始自動翻頁'));
      await settle(tester, const Duration(milliseconds: 800));
      var frames = 0;
      final costs = await recordFrames(
        tester,
        realAsync: true,
        until: () => ++frames >= 180,
      );
      // ignore: avoid_print
      print(describeFrames('$round 自動翻頁捲三秒', costs));
      await tester.tapAt(centre);
      await settle(tester, const Duration(milliseconds: 800));
      await tester.tap(find.byTooltip('停止自動翻頁'));
      await settle(tester, const Duration(milliseconds: 800));
      await tester.tapAt(centre);
      await rest(tester);
    }

    await tearDownApp(tester);
  });
}

// 臨時：全 App 探索「閱讀器」區（test/_screens 被 git 忽略）。
//
// 從書架開書，叫出與收起選單、目錄抽屜（甩動、拖快速捲軸、點一章跳章）、排版
// 面板（字號、行高、風格、關閉）、閱讀偏好（左右對齊、繁簡轉換）、朗讀、替換規則、
// 自動翻頁、下一章上一章、拖章節進度條、點邊緣翻頁、慢拖正文、日夜切換，最後返回書架。
// 點擊區域改成左欄上一頁、右欄下一頁（預設是全部喚起選單，點邊緣不會翻頁）。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/features/bookshelf/bookshelf_page.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_tap_action.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/hybrid/view/hybrid_scroll_controller.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/widgets/chapter_scrollbar.dart';
import 'package:night_reader/shared/widgets/glass.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';
import '../../support/screenshot.dart';
import 'survey_support.dart';

const _area = 'reader';

/// 正文中央（叫出、收起選單）、右欄與左欄（翻頁）。
const _centre = Offset(196, 420);
const _rightEdge = Offset(340, 420);
const _leftEdge = Offset(50, 420);

/// 點擊區域：每列 [上一頁, 喚起選單, 下一頁]，左欄上一頁、右欄下一頁。
final String _tapGrid = [
  for (var row = 0; row < 3; row++) ...[
    ReaderV2TapAction.prevPage.code,
    ReaderV2TapAction.menu.code,
    ReaderV2TapAction.nextPage.code,
  ],
].join(',');

/// 連續 [frames] 格「條件成立而且畫面也停了」才算停下。
bool Function() _steady(bool Function() ok, {int frames = 40}) {
  var run = 0;
  return () {
    run = ok() && surveyQuiet() ? run + 1 : 0;
    return run >= frames;
  };
}

/// 每次呼叫算一格，連續 [n] 格後成立（用在自動翻頁這種不會停的情況）。
bool Function() _frames(int n) {
  var i = 0;
  return () => ++i >= n;
}

/// 拖動手勢，起點在第 0 格才決定（畫面上的位置要等前面的步驟做完才知道）。
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

bool _glassAt(double shown) {
  final slides = find.byType(GlassSlide).evaluate();
  return slides.isNotEmpty &&
      slides.every((e) => (e.widget as GlassSlide).shown == shown);
}

bool _menuShown() => _glassAt(1);
bool _menuHidden() => _glassAt(0);

bool _sheetOpen() => find.byType(BottomSheet).evaluate().isNotEmpty;

bool _drawerOpen() {
  final drawers = find.byType(Drawer).evaluate();
  if (drawers.isEmpty) return false;
  final box = drawers.first.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero).dx.abs() < 0.5;
}

Finder get _drawerList => find.descendant(
  of: find.byType(ReaderV2ChaptersDrawer),
  matching: find.byType(ListView),
);

Finder get _thumb => find.descendant(
  of: find.byType(ChapterScrollbar),
  matching: find.byWidgetPredicate(
    (w) => w is GestureDetector && w.onVerticalDragStart != null,
  ),
);

Finder get _slider => find.byType(Slider);

Finder get _textScroll => find.descendant(
  of: find.byType(HybridReaderScreen),
  matching: find.byType(CustomScrollView),
);

bool _readerMounted() => find.byType(HybridReaderScreen).evaluate().isNotEmpty;

ReaderV2Runtime _runtime(WidgetTester tester) =>
    tester.widget<HybridReaderScreen>(find.byType(HybridReaderScreen)).runtime;

HybridScrollPosition _textPosition(WidgetTester tester) {
  final view = tester.widget<CustomScrollView>(_textScroll);
  return view.controller!.position as HybridScrollPosition;
}

/// 等一次操作（重排、換章、拖進度）做完：看見它開始過、之後不再忙、畫面也停了。
/// 沒有開始過的（不需要重排）就等 30 格，之後照樣算停。
bool Function() _opDone(WidgetTester tester) {
  var seen = false;
  var frames = 0;
  var run = 0;
  return () {
    frames++;
    final busy = _runtime(tester).stateMachine.currentOperation != null;
    seen |= busy;
    run = !busy && (seen || frames >= 30) && surveyQuiet() ? run + 1 : 0;
    return run >= 40;
  };
}

/// 叫選單到 [shown]：狀態不對才點正文中央一下（不錄，只是讓下一步的起點對）。
Future<void> _menu(WidgetTester tester, {required bool shown}) async {
  if (shown ? _menuShown() : _menuHidden()) return;
  await tester.tapAt(_centre);
  await settle(tester, const Duration(milliseconds: 800));
}

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('survey: reader', (tester) async {
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
      prefs: {PreferKey.readerClickActions: _tapGrid},
      steps: () async {
        await step(
          'reader01',
          '書架點「夜雨聽書」→閱讀器開好',
          () => tester.tap(find.text('夜雨聽書').first),
          until: _steady(
            () =>
                _readerMounted() &&
                pageSettled(find.byType(ReaderV2Page)) &&
                _runtime(tester).stateMachine.currentOperation == null,
          ),
        );
        await step(
          'reader02',
          '點正文中央→叫出選單',
          () => tester.tapAt(_centre),
          until: _steady(_menuShown),
        );
        await step(
          'reader03',
          '點正文中央→收起選單',
          () => tester.tapAt(_centre),
          until: _steady(_menuHidden),
        );
        await step(
          'reader04',
          '點正文中央→叫出選單',
          () => tester.tapAt(_centre),
          until: _steady(_menuShown),
        );
        await step('reader05', '點「目錄」→目錄抽屜滑入', () async {
          await _menu(tester, shown: true);
          await tester.tap(find.text('目錄'));
        }, until: _steady(_drawerOpen));
        await step(
          'reader06',
          '目錄內甩動',
          () => tester.fling(_drawerList, const Offset(0, -900), 3000),
        );
        await step(
          'reader07',
          '拖目錄快速捲軸（先輕捲一下讓它出現）',
          () => tester.fling(_drawerList, const Offset(0, -20), 200),
          onFrame: _dragFrom(
            tester,
            () => tester.getCenter(_thumb.first),
            const Offset(0, 120),
          ),
          minFrames: 14,
        );
        await step(
          'reader08',
          '目錄點一章→紙蓋上、跳到那一章',
          () => tester.tap(find.textContaining('書頁之間').hitTestable().first),
          until: _opDone(tester),
        );
        await step(
          'reader09',
          '點正文中央→叫出選單',
          () => tester.tapAt(_centre),
          until: _steady(_menuShown),
        );
        await step('reader10', '點「排版」→外觀與排版面板滑入', () async {
          await _menu(tester, shown: true);
          await tester.tap(find.text('排版'));
        }, until: _steady(() => _sheetOpen() && _menuHidden()));
        await step(
          'reader11',
          '面板裡字號加大',
          () => tester.tap(find.bySemanticsLabel('增加字號')),
          until: _opDone(tester),
        );
        await step(
          'reader12',
          '面板裡字號縮小',
          () => tester.tap(find.bySemanticsLabel('減少字號')),
          until: _opDone(tester),
        );
        await step(
          'reader13',
          '面板裡行高加大',
          () => tester.tap(find.bySemanticsLabel('增加行高')),
          until: _opDone(tester),
        );
        await step(
          'reader14',
          '面板裡風格換成「竹綠」',
          () => tester.tap(find.text(AppStyle.bamboo.label)),
          until: _steady(() => true, frames: 60),
        );
        await step(
          'reader15',
          '外觀與排版面板關掉',
          () => goBack(tester),
          until: _steady(() => !_sheetOpen() && _menuShown()),
        );
        await step('reader16', '選單點「進階」→閱讀偏好頁推入', () async {
          await _menu(tester, shown: true);
          await tester.tap(find.text('進階'));
        }, until: _steady(() => pageSettled(find.byType(ReadingSettingsPage))));
        await step(
          'reader17',
          '閱讀偏好：左右對齊開',
          () => tester.tap(find.text('左右對齊')),
          until: _steady(() => true),
        );
        await step(
          'reader18',
          '閱讀偏好：左右對齊關',
          () => tester.tap(find.text('左右對齊')),
          until: _steady(() => true),
        );
        await step('reader19', '閱讀偏好：繁簡轉換改成簡轉繁', () async {
          // 繁簡轉換在清單下面，列表是懶建的，先捲過去（不錄）。
          final list = find.descendant(
            of: find.byType(ReadingSettingsPage),
            matching: find.byType(Scrollable),
          );
          await tester.scrollUntilVisible(
            find.text('簡轉繁'),
            300,
            scrollable: list.first,
          );
          await tester.tap(find.text('簡轉繁'));
        }, until: _steady(() => true));
        await step(
          'reader20',
          '閱讀偏好返回閱讀器',
          () => goBack(tester),
          until: _opDone(tester),
        );
        await step('reader21', '選單點「朗讀」→朗讀面板滑入', () async {
          await _menu(tester, shown: true);
          await tester.tap(find.text('朗讀'));
        }, until: _steady(() => _sheetOpen() && _menuHidden()));
        await step(
          'reader22',
          '朗讀面板關掉',
          () => goBack(tester),
          until: _steady(() => !_sheetOpen()),
        );
        await step('reader23', '選單點「替換規則」→替換規則面板打開', () async {
          await _menu(tester, shown: true);
          await tester.tap(find.byTooltip('替換規則'));
        }, until: _steady(() => true));
        await step(
          'reader24',
          '替換規則面板關掉',
          () => goBack(tester),
          until: _steady(() => true),
        );
        await step('reader25', '選單點「開始自動翻頁」→自動翻頁三秒', () async {
          await _menu(tester, shown: true);
          await tester.tap(find.byTooltip('開始自動翻頁'));
        }, until: _frames(180));
        await step(
          'reader26',
          '點正文中央→叫出選單（自動翻頁中）',
          () => tester.tapAt(_centre),
          until: _steady(_menuShown),
        );
        await step('reader27', '選單點「停止自動翻頁」', () async {
          await _menu(tester, shown: true);
          await tester.tap(find.byTooltip('停止自動翻頁'));
        }, until: _steady(() => true));
        await step('reader28', '選單點「下一章」→跳到下一章', () async {
          await _menu(tester, shown: true);
          await tester.tap(find.text('下一章'));
        }, until: _opDone(tester));
        await step('reader29', '選單點「上一章」→回到上一章', () async {
          await _menu(tester, shown: true);
          await tester.tap(find.text('上一章'));
        }, until: _opDone(tester));
        await step(
          'reader30',
          '拖章節進度條→放開跳到那一段',
          () => _menu(tester, shown: true),
          onFrame: _dragFrom(tester, () {
            final r = tester.getRect(_slider);
            return Offset(r.left + 24, r.center.dy);
          }, const Offset(120, 0)),
          minFrames: 14,
          until: _opDone(tester),
        );
        await step('reader31', '點右邊緣→翻下一頁', () async {
          await _menu(tester, shown: false);
          await tester.tapAt(_rightEdge);
        }, until: _steady(() => !_textPosition(tester).isPageTurning));
        await step('reader32', '點左邊緣→翻上一頁', () async {
          await _menu(tester, shown: false);
          await tester.tapAt(_leftEdge);
        }, until: _steady(() => !_textPosition(tester).isPageTurning));
        await step(
          'reader33',
          '正文慢慢往上拖',
          () => _menu(tester, shown: false),
          onFrame: _dragFrom(
            tester,
            () => const Offset(196, 600),
            const Offset(0, -240),
          ),
          minFrames: 14,
          until: _steady(() => true),
        );
        await step('reader34', '選單點日夜切換', () async {
          await _menu(tester, shown: true);
          final dark = find.byTooltip('切換深色模式');
          await tester.tap(
            dark.evaluate().isNotEmpty ? dark : find.byTooltip('切換淺色模式'),
          );
        }, until: _steady(() => true, frames: 60));
        await step('reader35', '選單點「返回」→離開閱讀器回書架', () async {
          await _menu(tester, shown: true);
          await tester.tap(find.byTooltip('返回'));
        }, until: _steady(() => pageSettled(find.byType(BookshelfPage))));
      },
    );
  });
}

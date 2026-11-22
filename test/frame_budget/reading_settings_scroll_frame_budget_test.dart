// 「我的」底下比一個畫面長的設定頁，進頁後用手指一路捲到底、再捲回頂端：
// 每一幀的成本（ADR 0037 策略四：手指在動的每一幀都在上限內）。捲到下一組
// 設定時那一組要建出來；另量換成內容後馬上開始捲（還沒有靜止的時間可以先
// 準備）。閱讀偏好另量從背景回來與往右拖返回。淺色、深色各量一次。用法見
// `test/support/frame_budget.dart`；帶 `frame_budget` 標籤，平常的全套測試
// 跳過。
@Tags(['frame_budget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/about/about_page.dart';
import 'package:night_reader/features/settings/appearance_settings_page.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/features/settings/settings_page.dart';
import 'package:night_reader/features/source_manager/source_editor_page.dart';
import 'package:night_reader/shared/widgets/glass/floating_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

/// 量的頁：名稱、頁面，與從「我的」依序點哪幾列進去。「我的」底下其他的頁
/// （朗讀與語音、閱讀紀錄、AI 服務、備份與同步）一個畫面放得下，不用捲。
const _pages = <(String, Type, List<String>)>[
  ('閱讀偏好', ReadingSettingsPage, ['閱讀偏好']),
  ('外觀與主題', AppearanceSettingsPage, ['外觀與主題']),
  ('關於夜讀', AboutPage, ['關於夜讀']),
  ('書源編輯', SourceEditorPage, ['書源管理', kSiteName]),
];

/// 一下接一下拖，每下按住、每幀拖 [step]、拖 [steps] 幀後放開，等 [gap]
/// 幀再拖下一下，直到清單捲到盡頭。手指一般捲設定頁的速度：每幀 12 像素
/// （約每秒 750 像素），一下拖 0.4 秒。
class _Scroll {
  _Scroll(this.tester, this.at, this.position, {required this.down});

  static const steps = 24;
  static const gap = 6;

  final WidgetTester tester;
  final Offset at;
  final ScrollPosition position;
  final bool down;
  TestGesture? _gesture;
  int _phase = 0;
  bool done = false;

  Offset get _step => Offset(0, down ? -12 : 12);

  bool get atEnd => down
      ? position.pixels >= position.maxScrollExtent - 0.5
      : position.pixels <= position.minScrollExtent + 0.5;

  Future<void> onFrame(int frame) async {
    if (done) return;
    final timeStamp = Duration(milliseconds: 16 * frame);
    final phase = _phase++ % (steps + 1 + gap);
    if (phase == 0) {
      if (atEnd) {
        done = true;
        return;
      }
      _gesture = await tester.startGesture(at);
    } else if (phase <= steps) {
      await _gesture!.moveBy(_step, timeStamp: timeStamp);
    } else if (phase == steps + 1) {
      await _gesture!.up(timeStamp: timeStamp);
    }
  }
}

/// 從左緣往右拖，每幀 20 像素、拖 15 幀後放開。
class _SwipeBack {
  _SwipeBack(this.tester);

  final WidgetTester tester;
  TestGesture? _gesture;
  bool released = false;

  Future<void> onFrame(int frame) async {
    final timeStamp = Duration(milliseconds: 16 * frame);
    if (frame == 0) {
      _gesture = await tester.startGesture(const Offset(5, 300));
    } else if (frame <= 15) {
      await _gesture!.moveBy(const Offset(20, 0), timeStamp: timeStamp);
    } else if (!released) {
      await _gesture!.up(timeStamp: timeStamp);
      released = true;
    }
  }
}

/// 從「我的」依序點 [rows]，一格一格推進到 [page] 的骨架換成內容。
Future<void> _open(WidgetTester tester, List<String> rows, Finder page) async {
  for (final (i, row) in rows.indexed) {
    await tester.ensureVisible(find.text(row).last);
    await tester.pump();
    await tester.tap(find.text(row).last);
    if (i < rows.length - 1) await rest(tester);
  }
  for (var i = 0; i < 300 && !(pageSettled(page) && !skeletonShown()); i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(skeletonShown(), isFalse, reason: '${rows.last} 的骨架沒有換完');
}

/// 返回 [times] 層。
Future<void> _back(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await goBack(tester);
    await rest(tester);
  }
}

/// 捲到盡頭；[label] 是 null 時只暖機、不量。
Future<void> _scroll(
  WidgetTester tester,
  Finder page,
  String? label, {
  required bool down,
}) async {
  // 直向的那一個（書源編輯的分頁本身是橫向的）。
  final list = find.descendant(
    of: page,
    matching: find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    ),
  );
  final position = tester.state<ScrollableState>(list.first).position;
  // 一個畫面放得下的頁不用捲。
  if (position.maxScrollExtent < 1) return;
  final scroll = _Scroll(
    tester,
    tester.getCenter(list.first),
    position,
    down: down,
  );
  if (label == null) {
    for (var i = 0; i < 2000 && !scroll.done; i++) {
      await scroll.onFrame(i);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await settle(tester, const Duration(seconds: 1));
    return;
  }
  await measureNavigation(
    tester,
    label,
    action: () async {},
    settled: () => scroll.done && !position.isScrollingNotifier.value,
    note: () => scroll.done ? '慣性' : '捲動',
    onFrame: scroll.onFrame,
    tailFrames: 10,
  );
  expect(scroll.atEnd, isTrue, reason: '$label 沒捲到盡頭');
}

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('scrolling long settings pages', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp(databaseInIsolate: true);
      await seedLibrary();
      await seedSiteSource();
    });
    // 第一趟只暖機不印：第一次跑到的程式碼還在編譯，數字偏高，和手機上
    // 已經編好的正式版差很多；淺色排在第一個會被拖累。
    for (final (mode, theme) in [
      ('light', null),
      ('light', '淺色'),
      ('dark', '深色'),
    ]) {
      String? label(String text) => theme == null ? null : '$theme $text';
      await tester.runAsync(() => resetPrefs({'themeMode': mode}));
      await pumpApp(tester);
      await rest(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(FloatingTabBar),
          matching: find.text('我的'),
        ),
      );
      await rest(tester);

      for (final (name, type, rows) in _pages) {
        final page = find.byType(type);
        await _open(tester, rows, page);
        await rest(tester);
        await _scroll(tester, page, label('$name往下捲到底'), down: true);
        await rest(tester);
        await _scroll(tester, page, label('$name捲回頂端'), down: false);
        await _back(tester, 1);

        await _open(tester, rows.sublist(rows.length - 1), page);
        await _scroll(tester, page, label('$name換成內容後馬上往下捲'), down: true);
        await _back(tester, rows.length);
      }

      // 閱讀偏好：從背景回來、往右拖返回。
      const row = '閱讀偏好';
      final page = find.byType(ReadingSettingsPage);
      await _open(tester, [row], page);
      await rest(tester);
      final binding = tester.binding;
      final resume = label('$row從背景回來');
      if (resume != null) {
        binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
          ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await rest(tester);
        await measureActivity(
          tester,
          resume,
          action: () => binding
            ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
            ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
            ..handleAppLifecycleStateChanged(AppLifecycleState.resumed),
        );
        await rest(tester);
      }
      final swipe = _SwipeBack(tester);
      final back = label('$row往右拖返回我的');
      if (back == null) {
        await goBack(tester);
      } else {
        await measureNavigation(
          tester,
          back,
          action: () async {},
          page: find.byType(SettingsPage),
          note: () => swipe.released ? '收尾' : '拖動',
          onFrame: swipe.onFrame,
        );
      }
      await rest(tester);
    }
    await tearDownApp(tester);
  });
}

// 「我的 → 閱讀偏好」進頁後用手指一路捲到底、再捲回頂端：每一幀的成本
// （ADR 0037 策略四：手指在動的每一幀都在上限內）。捲到下一組設定時那一組
// 要建出來；另量換成內容後馬上開始捲（還沒有靜止的時間可以先準備）。淺色、
// 深色各量一次。用法見 `test/support/frame_budget.dart`；帶 `frame_budget`
// 標籤，平常的全套測試跳過。
@Tags(['frame_budget'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/settings/reading_settings_page.dart';
import 'package:night_reader/shared/widgets/glass/floating_tab_bar.dart';

import '../support/app_harness.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

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

final _page = find.byType(ReadingSettingsPage);

/// 從「我的」點進閱讀偏好，一格一格推進到骨架換成內容。
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('閱讀偏好'));
  for (var i = 0; i < 300 && !(pageSettled(_page) && !skeletonShown()); i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(skeletonShown(), isFalse, reason: '閱讀偏好的骨架沒有換完');
}

/// 捲到盡頭；[label] 是 null 時只暖機、不量。
Future<void> _scroll(
  WidgetTester tester,
  String? label, {
  required bool down,
}) async {
  final list = find.descendant(of: _page, matching: find.byType(Scrollable));
  final position = tester.state<ScrollableState>(list.first).position;
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

  testWidgets('scrolling the reading settings page', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp(databaseInIsolate: true);
      await seedLibrary();
    });
    // 第一趟只暖機不印：第一次跑到的程式碼還在編譯，數字偏高，和手機上
    // 已經編好的正式版差很多；淺色排在第一個會被拖累。
    for (final (mode, label) in [
      ('light', null),
      ('light', '淺色'),
      ('dark', '深色'),
    ]) {
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

      await _open(tester);
      await rest(tester);
      await _scroll(
        tester,
        label == null ? null : '$label 閱讀偏好往下捲到底',
        down: true,
      );
      await rest(tester);
      await _scroll(
        tester,
        label == null ? null : '$label 閱讀偏好捲回頂端',
        down: false,
      );
      await goBack(tester);
      await rest(tester);

      await _open(tester);
      await _scroll(
        tester,
        label == null ? null : '$label 閱讀偏好換成內容後馬上往下捲',
        down: true,
      );
      await goBack(tester);
      await rest(tester);
    }
    await tearDownApp(tester);
  });
}

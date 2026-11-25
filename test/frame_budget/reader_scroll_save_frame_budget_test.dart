// 閱讀器正文持續捲動時存閱讀進度的成本（ADR 0018、0037 策略四）：手指不放
// 連續拖六秒、連甩八下，每一幀的成本，以及進度寫進資料庫的那幾幀；最後在
// 拖動中按返回，量按下去到頁面開始退出隔多久（另一次同時有一筆大量寫入
// 佔著資料庫）。用法見 `test/support/frame_budget.dart`；帶 `frame_budget`
// 標籤，平常的全套測試跳過。
@Tags(['frame_budget'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/reader/screen/reader_page.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';

import '../support/app_harness.dart';
import '../support/frame_budget.dart';
import '../support/navigation_budget.dart';
import '../support/progress_writes.dart';
import '../support/screenshot.dart';

bool _scrolling() => find
    .byType(Scrollable)
    .evaluate()
    .map((e) => (e as StatefulElement).state as ScrollableState)
    .any((s) => s.position.isScrollingNotifier.value);

/// 閱讀頁所在的路由開始退出（或已經不在）。
bool _leaving() {
  final pages = find.byType(ReaderPage).evaluate();
  if (pages.isEmpty) return true;
  final status = pageRouteOf(pages.first)?.animation?.status;
  return status == AnimationStatus.reverse ||
      status == AnimationStatus.dismissed;
}

const _start = Offset(196, 700);

/// 手指按著、每幀往上推一段，拖 [frames] 幀。
Future<List<FrameCost>> _measureDrag(
  WidgetTester tester,
  String label,
  ProgressWrites writes, {
  required int frames,
  required double step,
}) async {
  TestGesture? gesture;
  var released = false;
  final before = writes.count;
  var duringMove = 0;
  writes.takeNew();
  final costs = await recordFrames(
    tester,
    realAsync: true,
    until: () => released && !_scrolling(),
    tailFrames: 60,
    note: () => withWriteNote(released ? '放開後' : '拖動', writes),
    onFrame: (frame) async {
      final timeStamp = Duration(milliseconds: 16 * frame);
      if (frame == 0) {
        gesture = await tester.startGesture(_start);
      } else if (frame <= frames) {
        await gesture!.moveBy(Offset(0, -step), timeStamp: timeStamp);
      } else if (!released) {
        duringMove = writes.count - before;
        await gesture!.up(timeStamp: timeStamp);
        released = true;
      }
    },
  );
  // ignore: avoid_print
  print(describeFrames(label, costs));
  // ignore: avoid_print
  print(describeWriteFrames(label, costs));
  // ignore: avoid_print
  print('$label：手指在動時寫 $duringMove 次，整段 ${writes.count - before} 次');
  return costs;
}

/// 連甩 [flings] 下：每下按住、每幀往上拖 [step]、拖 [steps] 幀後放開，
/// 隔 [pause] 幀再甩下一下。
Future<List<FrameCost>> _measureFlings(
  WidgetTester tester,
  String label,
  ProgressWrites writes, {
  required int flings,
  required double step,
  required int steps,
  required int pause,
}) async {
  final period = steps + 1 + pause;
  TestGesture? gesture;
  var done = false;
  final before = writes.count;
  var beforeRest = 0;
  writes.takeNew();
  final costs = await recordFrames(
    tester,
    realAsync: true,
    until: () => done && !_scrolling(),
    tailFrames: 60,
    note: () => withWriteNote(done ? '慣性' : '甩動', writes),
    onFrame: (frame) async {
      if (done) return;
      final round = frame ~/ period;
      final within = frame % period;
      final timeStamp = Duration(milliseconds: 16 * frame);
      if (round >= flings) {
        done = true;
        return;
      }
      if (within == 0) {
        gesture = await tester.startGesture(_start);
      } else if (within <= steps) {
        await gesture!.moveBy(Offset(0, -step), timeStamp: timeStamp);
      } else if (within == steps + 1) {
        await gesture!.up(timeStamp: timeStamp);
      }
    },
    afterFrame: (_) async {
      if (!done) beforeRest = writes.count - before;
    },
  );
  // ignore: avoid_print
  print(describeFrames(label, costs));
  // ignore: avoid_print
  print(describeWriteFrames(label, costs));
  // ignore: avoid_print
  print('$label：連甩途中寫 $beforeRest 次，整段 ${writes.count - before} 次');
  return costs;
}

/// 手指按著拖 [frames] 幀後按返回（手指還沒放），量按返回到閱讀頁開始退出
/// 的真實時間。等待時每一步只推 1ms 假時間、讓出 1ms 真實時間，資料庫的
/// 回覆照真實時間到。[busy] 在按返回前開始（在真實時間裡），代表同時佔著
/// 資料庫的寫入。
Future<void> _measureExit(
  WidgetTester tester,
  String label, {
  required int frames,
  Future<void> Function()? busy,
}) async {
  final gesture = await tester.startGesture(_start);
  for (var frame = 1; frame <= frames; frame++) {
    await gesture.moveBy(
      const Offset(0, -6),
      timeStamp: Duration(milliseconds: 16 * frame),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));
  }
  Future<void>? occupying;
  if (busy != null) {
    await tester.runAsync(() async => occupying = busy());
  }
  final clock = Stopwatch()..start();
  unawaited(goBack(tester));
  var steps = 0;
  while (!_leaving() && steps < 5000) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 1));
    steps++;
  }
  clock.stop();
  // ignore: avoid_print
  print(
    '$label：按返回到開始退出 '
    '${(clock.elapsedMicroseconds / 1000).toStringAsFixed(1)}ms（真實時間）',
  );
  expect(_leaving(), isTrue, reason: '$label 按返回後沒有退出');
  await gesture.up();
  if (occupying case final pending?) await tester.runAsync(() => pending);
  await rest(tester);
}

/// 一筆大量寫入：另一本書的三千章目錄。
Future<void> _bulkInsert(int round) => getIt<ChapterDao>().insertChapters([
  for (var i = 0; i < 3000; i++)
    BookChapter(
      url: 'https://bulk.test/$round/c$i.html',
      title: '第$i章',
      bookUrl: 'https://bulk.test/$round/',
      index: i,
    ),
]);

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('reader scroll saves', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp(databaseInIsolate: true);
      await seedLibrary();
      await installFakeSite();
    });
    await pumpApp(tester);
    await rest(tester);
    await openReader(tester);
    await rest(tester);

    final writes = ProgressWrites();

    // 手指不放、每幀推 10 點，拖六秒（約每秒 600 點）。
    await _measureDrag(tester, '正文連續拖動 6 秒', writes, frames: 375, step: 10);
    await rest(tester);
    // 每下拖 8 幀、每幀 60 點放手，隔 20 幀再甩。
    await _measureFlings(
      tester,
      '正文連甩 8 下',
      writes,
      flings: 8,
      step: 60,
      steps: 8,
      pause: 20,
    );
    await rest(tester);

    // 2 秒一次的定期寫入在第 125 幀前後送出；拖到第 127 幀按返回。
    await _measureExit(tester, '拖動中按返回', frames: 127);
    await openReader(tester);
    await rest(tester);
    await _measureExit(
      tester,
      '拖動中按返回（資料庫同時有一筆大量寫入）',
      frames: 127,
      busy: () => _bulkInsert(1),
    );

    await tester.runAsync(writes.cancel);
    await tearDownApp(tester);
  });
}

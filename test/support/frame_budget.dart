// 量動畫期間每一幀主執行緒忙多久（ADR 0018）：宣稱工作已離開主執行緒、
// 或要拿掉一段等待之前，用 test/frame_budget/ 的情境實際量一次。
//
//   flutter test --run-skipped -t frame_budget test/frame_budget
//   FRAME_ATTRIBUTE=1 flutter test --run-skipped -t frame_budget test/frame_budget
//
// 量到的是電腦上 debug 模式的時間，手機上會慢好幾倍，看的是相對大小與尖峰
// 出現在哪一段。FRAME_ATTRIBUTE=1 時另外列出尖峰幀裡耗時最多的 widget 與
// render object，以及重建從哪些 widget 開始（誰呼叫了 setState）；打開這些
// 紀錄本身會讓數字變大（幀前多了印堆疊的時間），只拿來找是誰。測試環境
// 沒有開書源 isolate（`SourceIsolate.enabled`），書源工作在原地執行，會算進
// 主執行緒。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一幀的成本，單位微秒。
class FrameCost {
  const FrameCost({
    required this.index,
    required this.beforeFrame,
    required this.frame,
    required this.afterFrame,
    required this.async,
    required this.top,
    required this.dirty,
    this.note,
  });

  final int index;

  /// 這一幀開始前的計時器與 microtask（資料工作多半在這裡）。
  final int beforeFrame;

  /// 動畫、build、layout、paint。
  final int frame;

  /// 這一幀之後的 post-frame callback 與 microtask。
  final int afterFrame;

  /// 讓出真實時間給資料庫等 isolate 時，回到主執行緒的後續工作。
  final int async;

  /// [FRAME_ATTRIBUTE] 開著時，這一幀耗時最多的區塊。
  final List<AggregatedTimedBlock> top;

  /// [FRAME_ATTRIBUTE] 開著時，這一幀被標成要重建的 widget（重建從哪裡
  /// 開始，誰呼叫了 setState 或 markNeedsBuild）與次數。
  final Map<String, int> dirty;

  /// 這一幀畫完時畫面在哪一段（[recordFrames] 的 `note`），例如換頁中、
  /// 骨架、換場。
  final String? note;

  int get total => beforeFrame + frame + afterFrame + async;
}

/// 環境變數 `FRAME_ATTRIBUTE=1` 時列出尖峰幀裡耗時最多的區塊。
final bool frameAttribution = Platform.environment['FRAME_ATTRIBUTE'] == '1';

/// 一幀一幀推進（每幀 [frameDuration]），直到 [until] 成立後再多 [tailFrames]
/// 幀，記下每一幀的成本。[realAsync] 時每幀之間讓出真實時間，給跑在真的
/// isolate 裡的資料庫回應（`app_harness.dart` 的整個 App 需要）。[note] 在
/// 每一幀畫完時記下畫面在哪一段，摘要裡跟著尖峰幀列出。
Future<List<FrameCost>> recordFrames(
  WidgetTester tester, {
  required bool Function() until,
  String? Function()? note,
  int tailFrames = 0,
  int maxFrames = 1200,
  Duration frameDuration = const Duration(milliseconds: 16),
  bool realAsync = false,
}) async {
  final previous = (
    FlutterTimeline.debugCollectionEnabled,
    debugProfileBuildsEnabled,
    debugProfileLayoutsEnabled,
    debugProfilePaintsEnabled,
    debugPrintScheduleBuildForStacks,
    debugPrint,
  );
  var dirty = <String, int>{};
  if (frameAttribution) {
    FlutterTimeline.debugCollectionEnabled = true;
    debugProfileBuildsEnabled = true;
    debugProfileLayoutsEnabled = true;
    debugProfilePaintsEnabled = true;
    // 框架每次排重建都印一段堆疊，只留第一行的 widget 名稱。
    debugPrintScheduleBuildForStacks = true;
    const prefix = 'scheduleBuildFor() called for ';
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message == null || !message.startsWith(prefix)) return;
      final name = message
          .substring(prefix.length)
          .split(RegExp(r'[(-]'))
          .first;
      dirty[name] = (dirty[name] ?? 0) + 1;
    };
  }
  final costs = <FrameCost>[];
  final clock = Stopwatch()..start();
  try {
    var tail = -1;
    for (var index = 0; index < maxFrames; index++) {
      var asyncCost = 0;
      if (realAsync) {
        final start = clock.elapsedMicroseconds;
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        asyncCost = clock.elapsedMicroseconds - start;
      }
      var begin = -1;
      var end = -1;
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        begin = clock.elapsedMicroseconds;
      }, scheduleNewFrame: false);
      SchedulerBinding.instance.addPostFrameCallback((_) {
        end = clock.elapsedMicroseconds;
      });
      if (frameAttribution) FlutterTimeline.debugReset();
      final start = clock.elapsedMicroseconds;
      await tester.pump(frameDuration);
      final stop = clock.elapsedMicroseconds;
      final top = frameAttribution
          ? ([...FlutterTimeline.debugCollect().aggregatedBlocks]
                  ..sort((a, b) => b.duration.compareTo(a.duration)))
                .take(12)
                .toList()
          : const <AggregatedTimedBlock>[];
      // 沒有排到幀（畫面靜止）時整段都算在幀前。
      if (begin < 0 || end < 0) begin = end = stop;
      costs.add(
        FrameCost(
          index: index,
          beforeFrame: begin - start,
          frame: end - begin,
          afterFrame: stop - end,
          async: asyncCost,
          top: top,
          dirty: dirty,
          note: note?.call(),
        ),
      );
      dirty = <String, int>{};
      if (tail < 0 && until()) tail = 0;
      if (tail >= 0 && tail++ >= tailFrames) break;
    }
  } finally {
    FlutterTimeline.debugCollectionEnabled = previous.$1;
    debugProfileBuildsEnabled = previous.$2;
    debugProfileLayoutsEnabled = previous.$3;
    debugProfilePaintsEnabled = previous.$4;
    debugPrintScheduleBuildForStacks = previous.$5;
    debugPrint = previous.$6;
  }
  return costs;
}

/// 摘要：幀數、中位數、最大值，以及超過 [over] 的每一幀各段成本。
String describeFrames(
  String label,
  List<FrameCost> costs, {
  Duration over = const Duration(milliseconds: 8),
}) {
  String ms(int us) => (us / 1000).toStringAsFixed(1);
  final totals = [for (final cost in costs) cost.total]..sort();
  final spikes = costs.where((c) => c.total > over.inMicroseconds);
  final lines = [
    '$label：${costs.length} 幀，中位數 ${ms(totals[totals.length ~/ 2])}ms，'
        '最大 ${ms(totals.last)}ms，超過 ${over.inMilliseconds}ms 的 ${spikes.length} 幀',
    for (final cost in spikes) ...[
      '  第 ${cost.index} 幀${cost.note == null ? '' : '（${cost.note}）'} '
          '${ms(cost.total)}ms：幀前 ${ms(cost.beforeFrame)}、'
          '幀 ${ms(cost.frame)}、幀後 ${ms(cost.afterFrame)}、'
          '非同步 ${ms(cost.async)}',
      if (cost.top.isNotEmpty)
        '    耗時：${cost.top.map((b) => '${b.name} ${(b.duration / 1000).toStringAsFixed(1)}×${b.count}').join('、')}',
      if (cost.dirty.isNotEmpty)
        '    重建起點：${cost.dirty.entries.map((e) => '${e.key}×${e.value}').join('、')}',
    ],
  ];
  return lines.join('\n');
}

// 臨時：全 App 動畫儀表板探索的共用工具（test/_screens 被 git 忽略）。
//
// 每一區一個 `<區>_survey_test.dart`，整區在同一個 testWidgets 裡用
// [runSurvey] 依序操作，每個操作呼叫一次 [surveyStep]：先做動作，再逐格錄到
// 畫面停下來。範例是 `tabs_survey_test.dart`。
//
//   SURVEY_MODE=light|dark   淺色或深色（預設 light）
//   SURVEY_DRY=1             不存畫面，只把流程跑過、印出每步的結果（寫腳本時用）
//
// 錄影寫在 %TEMP%\night-reader-frames\<步驟鍵>-<mode>\，跑的時候把 TEMP、TMP
// 指到 D:\nr-survey\tmp。每步印一行 `SURVEY <鍵> ...`，並把步驟附加到
// night-reader-frames\survey-manifest.jsonl。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/loading_veil.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

import '../../support/app_harness.dart';
import '../../support/frame_budget.dart';
import '../../support/frame_recording.dart';
import '../../support/navigation_budget.dart';

final String surveyMode = Platform.environment['SURVEY_MODE'] ?? 'light';
final bool surveyDry = Platform.environment['SURVEY_DRY'] == '1';

/// 一步最多錄幾格才算「停不下來」：300 格約 4.8 秒，再加尾段。
const int surveyMaxFrames = 300;

/// 暖身中：[surveyStep] 照做動作、推到停下，但不錄、不印。
bool _warming = false;

/// 跑一區：開整個 App（淺色或深色照 [surveyMode]，書架有書、有一個假書源
/// 網站），先把 [steps] 整個跑一次暖身（電腦上第一次跑一段程式含編譯時間，
/// 手機上沒有），拆掉 App、偏好設定還原後重開，再跑一次正式錄。
/// [steps] 要能從剛開好 App 的書架開始重跑：改過的設定照常，資料庫裡的書與
/// 書源不要刪。`SURVEY_DRY=1` 時不暖身。[launch] 換掉開 App 的方式（錄開
/// App 進場用），預設 [pumpApp]。
Future<void> runSurvey(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  required Future<void> Function() steps,
  Future<void> Function()? launch,
}) async {
  final open = launch ?? () => pumpApp(tester);
  setUpPhone(tester);
  await tester.runAsync(() async {
    await setUpApp(prefs: {'themeMode': surveyMode, ...prefs});
    await seedLibrary();
    await seedSiteSource();
    await installFakeSite();
  });
  // SURVEY_WARM=1：乾跑也先暖身（只量時間、不錄影時，要和錄影一樣先暖身）。
  if (!surveyDry || Platform.environment['SURVEY_WARM'] == '1') {
    _warming = true;
    await open();
    await rest(tester);
    await steps();
    _warming = false;
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, const Duration(milliseconds: 300));
    await tester.runAsync(
      () => resetPrefs({'themeMode': surveyMode, ...prefs}),
    );
  }
  await open();
  await rest(tester);
  await steps();
  await tearDownApp(tester);
}

bool _routeMoving() {
  for (final e in find.byType(Navigator).evaluate()) {
    final nav = (e as StatefulElement).state as NavigatorState;
    if (nav.userGestureInProgress) return true;
  }
  for (final e in find.byType(ModalBarrier, skipOffstage: false).evaluate()) {
    final route = ModalRoute.of(e);
    if (route == null) continue;
    final a = route.animation;
    final s = route.secondaryAnimation;
    if ((a != null && a.isAnimating) || (s != null && s.isAnimating)) {
      return true;
    }
  }
  return false;
}

bool _tabSwitching() => find
    .byType(AppTransitionSwitch)
    .evaluate()
    .any((e) => (e.widget as AppTransitionSwitch).outgoing != null);

bool _revealing() => find
    .byType(SkeletonRevealLayer)
    .evaluate()
    .any((e) => (e.widget as SkeletonRevealLayer).presence.isAnimating);

String? _veil() {
  for (final e in find.byType(LoadingVeil).evaluate()) {
    final veil = (e.widget as LoadingVeil).controller;
    if (veil.isRevealing) return '掀紙';
    if (veil.isVisible) return '紙';
  }
  return null;
}

bool _scrolling() {
  for (final e in find.byType(Scrollable).evaluate()) {
    final state = (e as StatefulElement).state as ScrollableState;
    if (state.position.isScrollingNotifier.value) return true;
  }
  return false;
}

/// 這一格畫面在哪一段。
String surveyPhase() {
  if (_routeMoving()) return '換頁';
  if (_tabSwitching()) return '換分頁';
  final veil = _veil();
  if (veil != null) return veil;
  if (_revealing()) return '換場';
  if (skeletonShown()) return '骨架';
  if (_scrolling()) return '捲動';
  if (SchedulerBinding.instance.transientCallbackCount > 0) return '動畫';
  return '靜止';
}

/// 畫面停下來了：沒有換頁、骨架、紙、捲動，也沒有任何動畫在走（選單與
/// 面板的滑入、開關這類小動畫都是 ticker）。書架靜止時沒有常駐的 ticker。
bool surveyQuiet() =>
    !_routeMoving() &&
    !_tabSwitching() &&
    _veil() == null &&
    !_revealing() &&
    !skeletonShown() &&
    !_scrolling() &&
    SchedulerBinding.instance.transientCallbackCount == 0;

/// 做 [action]，再逐格錄到 [until]（預設 [surveyQuiet]）成立後多 [tailFrames]
/// 格。[key] 是這步的代號（英數字，不能有 `-`），[label] 是給人看的名稱。
/// [onFrame] 在每格開始前呼叫，拖動這類手勢一格送一步（見 [dragOnFrames]）。
Future<void> surveyStep(
  WidgetTester tester, {
  required String area,
  required String key,
  required String label,
  required Future<void> Function() action,
  bool Function()? until,
  Future<void> Function(int frame)? onFrame,
  // 點下去後要等資料才推頁面的，第一格畫面還沒動；至少錄 20 格（0.32 秒）。
  int minFrames = 20,
  int tailFrames = 30,
}) async {
  assert(!key.contains('-'), '步驟鍵不能有 -：$key');
  final done = until ?? surveyQuiet;
  var frames = 0;
  var timedOut = false;
  bool stop() {
    if (frames < minFrames) return false;
    if (done()) return true;
    if (frames >= surveyMaxFrames) return timedOut = true;
    return false;
  }

  final clock = Stopwatch()..start();
  await action();
  final tapMs = clock.elapsedMicroseconds / 1000;
  List<double> costs;
  if (_warming) {
    await recordFrames(
      tester,
      until: stop,
      onFrame: (i) async {
        frames++;
        await onFrame?.call(i);
      },
      tailFrames: tailFrames,
      realAsync: true,
    );
    await rest(tester);
    return;
  }
  if (surveyDry) {
    final result = await recordFrames(
      tester,
      until: stop,
      note: surveyPhase,
      onFrame: (i) async {
        frames++;
        await onFrame?.call(i);
      },
      tailFrames: tailFrames,
      realAsync: true,
    );
    costs = [for (final c in result) c.total / 1000];
    // ignore: avoid_print
    print(describeFrames('$area/$key', result));
  } else {
    final name = '$key-$surveyMode';
    await recordAnimation(
      tester,
      name: name,
      phase: () {
        frames++;
        return surveyPhase();
      },
      until: stop,
      onFrame: onFrame,
      tailFrames: tailFrames,
      realAsync: true,
    );
    final meta = jsonDecode(
      File(
        '${frameRecordingDir.path}${Platform.pathSeparator}$name'
        '${Platform.pathSeparator}meta.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>;
    costs = [for (final c in meta['costs'] as List) (c as num).toDouble()];
  }
  final peak = costs.fold<double>(0, (a, b) => a > b ? a : b);
  final over = costs.where((c) => c > 8).length;
  // ignore: avoid_print
  print(
    'SURVEY $area/$key 「$label」 $surveyMode 格數=${costs.length} '
    '點下去=${tapMs.toStringAsFixed(1)}ms 最忙=${peak.toStringAsFixed(1)}ms '
    '超過8ms=$over格${timedOut ? ' 停不下來' : ''}',
  );
  if (!surveyDry) {
    frameRecordingDir.createSync(recursive: true);
    File(
      '${frameRecordingDir.path}${Platform.pathSeparator}survey-manifest.jsonl',
    ).writeAsStringSync(
      '${jsonEncode({'area': area, 'key': key, 'label': label, 'mode': surveyMode, 'tapMs': tapMs, 'timedOut': timedOut})}\n',
      mode: FileMode.append,
    );
  }
  await rest(tester);
}

/// 拖動手勢：從 [from] 開始，在 [frames] 格內等速移動 [delta] 後放開，一格
/// 送一步，交給 [surveyStep] 的 `onFrame`。動作本身（`action`）傳空函式，
/// `minFrames` 給 `frames + 2`，不然手勢還沒開始畫面就被當成停了。
Future<void> Function(int frame) dragOnFrames(
  WidgetTester tester, {
  required Offset from,
  required Offset delta,
  int frames = 12,
}) {
  TestGesture? gesture;
  return (frame) async {
    if (frame == 0) {
      gesture = await tester.startGesture(from, kind: PointerDeviceKind.touch);
    } else if (frame <= frames) {
      await gesture!.moveBy(delta / frames.toDouble());
    } else if (frame == frames + 1) {
      await gesture!.up();
    }
  };
}

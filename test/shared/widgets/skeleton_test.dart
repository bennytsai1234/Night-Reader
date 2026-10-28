import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

import '../../support/theme_with.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  testWidgets(
    'every strength is visible in every style and brightness, each a step '
    'deeper than the last',
    (tester) async {
      for (final style in AppStyle.values) {
        for (final brightness in Brightness.values) {
          var previous = <double>[1, 1];
          for (final strength in SkeletonStrength.values) {
            late Color skeleton;
            late AppChrome chrome;
            await tester.pumpWidget(
              MaterialApp(
                // 和 App 一樣直接換主題；預設的主題漸變會讓這一幀量到的
                // 還是上一輪的風格。
                themeAnimationStyle: AnimationStyle.noAnimation,
                theme: themeWith(style, brightness, [
                  SkeletonLook(strength: strength),
                ]),
                home: Builder(
                  builder: (context) {
                    skeleton = Skeleton.colorOf(context);
                    chrome = AppChrome.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            );
            final reason = '${style.name} ${brightness.name} ${strength.name}';
            final contrasts = [
              for (final background in [
                chrome.groupedBackground,
                chrome.groupedSurface,
              ])
                _contrast(Color.alphaBlend(skeleton, background), background),
            ];
            for (var i = 0; i < contrasts.length; i++) {
              expect(contrasts[i], greaterThan(1.06), reason: reason);
              expect(contrasts[i], greaterThan(previous[i]), reason: reason);
            }
            previous = contrasts;
          }
        }
      }
    },
  );

  test('whole breathing pulses every position together', () {
    for (final phase in [0.0, 0.2, 0.5, 0.8]) {
      expect(
        Skeleton.breathAt(phase, 1, SkeletonBreath.whole),
        Skeleton.breathAt(phase, 0, SkeletonBreath.whole),
      );
    }
    expect(Skeleton.breathAt(0, 0, SkeletonBreath.whole), 1);
    expect(
      Skeleton.breathAt(0.5, 0, SkeletonBreath.whole),
      closeTo(0.55, 1e-9),
    );
  });

  testWidgets('left-to-right breathing follows the screen position while '
      'the page is scaled', (tester) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    const black = Color(0xFF000000);
    // 換頁途中整頁縮小一半：上排一條 400 寬、下排兩條各 200 寬，在同一個
    // 螢幕位置要一樣深。
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundary,
          child: ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: Align(
              alignment: Alignment.topLeft,
              child: Transform.scale(
                scale: 0.5,
                alignment: Alignment.topLeft,
                child: const Skeleton(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 400, height: 40, color: black),
                      SizedBox(height: 20),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SkeletonBox(width: 200, height: 40, color: black),
                          SkeletonBox(width: 200, height: 40, color: black),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    final bytes = await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      return image.toByteData();
    });
    int red(int x, int y) => bytes!.getUint8((y * 400 + x) * 4);
    for (final x in [10, 60, 120, 180]) {
      expect(red(x, 10), closeTo(red(x, 40), 2), reason: 'x=$x');
    }
    // 由左而右：左右兩端深淺不同。
    expect(red(10, 10), isNot(closeTo(red(180, 10), 2)));
  });

  test('left-to-right breathing reaches the right edge later by its lag', () {
    for (final breath in [
      SkeletonBreath.gentleSweep,
      SkeletonBreath.waveSweep,
    ]) {
      for (final phase in [0.1, 0.3, 0.6, 0.9]) {
        expect(
          Skeleton.breathAt(phase + breath.lag, 1, breath),
          closeTo(Skeleton.breathAt(phase, 0, breath), 1e-9),
          reason: breath.name,
        );
      }
    }
    // 緩：左右兩端一深一淺。
    expect(Skeleton.breathAt(0, 0, SkeletonBreath.gentleSweep), 1);
    expect(
      Skeleton.breathAt(0, 1, SkeletonBreath.gentleSweep),
      closeTo(0.55, 1e-9),
    );
  });

  group('resting the breath (launch reveal)', () {
    const frame = Duration(milliseconds: 16);
    // 開 App 進場一輪呼吸的格數，加一格捨入：收住最多再呼一輪。
    final cycleFrames =
        (LaunchEntranceMotion.breathCycle.inMicroseconds / frame.inMicroseconds)
            .ceil() +
        1;
    // 黑色骨架照一般節奏呼吸時，一格最多變約 4/255（曲線最陡處）；開 App
    // 的呼吸快幾倍，一格就多變幾倍，再加一的捨入。
    final maxStep =
        (4 *
                Skeleton.breathCycle.inMicroseconds /
                LaunchEntranceMotion.breathCycle.inMicroseconds)
            .ceil() +
        1;
    final boundary = GlobalKey();
    late LaunchEntranceMotion motion;

    /// 兩條 400 寬的黑色骨架疊在白底上（第二條 [second] 時才有），包在
    /// 開 App 的進場底下。[ticking] 是外層的 TickerMode，[reduce] 是減少
    /// 動態；重新 pump 時元件樹不變，骨架的狀態留著。
    Widget host({
      bool ticking = true,
      bool reduce = false,
      bool second = false,
    }) {
      const black = Color(0xFF000000);
      return MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
            child: LaunchEntrance(
              child: Builder(
                builder: (context) {
                  motion = LaunchEntrance.maybeOf(context)!;
                  return RepaintBoundary(
                    key: boundary,
                    child: ColoredBox(
                      color: const Color(0xFFFFFFFF),
                      child: TickerMode(
                        enabled: ticking,
                        child: Column(
                          children: [
                            const Skeleton(
                              child: SkeletonBox(
                                width: 400,
                                height: 20,
                                color: black,
                              ),
                            ),
                            if (second)
                              const Skeleton(
                                child: SkeletonBox(
                                  width: 400,
                                  height: 20,
                                  color: black,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    const xs = [5, 100, 200, 300, 395];

    /// 第 [row] 條骨架在 [xs] 的紅色：黑色骨架疊在白底上，越小越深，
    /// 最深是 0。
    Future<List<int>> sample(WidgetTester tester, {int row = 0}) async {
      final bytes = await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        return image.toByteData();
      });
      final y = 10 + row * 20;
      return [for (final x in xs) bytes!.getUint8((y * 400 + x) * 4)];
    }

    Future<void> setUpView(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 40);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    /// 一格一格推進到開 App 的骨架長完、停過 idle、開始呼吸的那一格。
    Future<void> grow(WidgetTester tester) async {
      for (var i = 0; i < 100 && !motion.breathing.value; i++) {
        await tester.pump(frame);
      }
      expect(motion.breathing.value, isTrue);
      await tester.pump(frame);
    }

    /// 一格一格推進 [frames] 格，每一格每個取樣點都和上一格接得上：一格
    /// 最多變 [maxStep]。
    Future<List<int>> pumpSmoothly(
      WidgetTester tester,
      List<int> previous,
      int frames,
    ) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(frame);
        final now = await sample(tester);
        for (var j = 0; j < xs.length; j++) {
          expect(
            (now[j] - previous[j]).abs(),
            lessThanOrEqualTo(maxStep),
            reason: '第 $i 格 x=${xs[j]}',
          );
        }
        previous = now;
      }
      return previous;
    }

    testWidgets('grows in at the deepest and only then starts breathing, from '
        'the left and without a jump', (tester) async {
      await setUpView(tester);
      await tester.pumpWidget(host());
      await tester.pump();
      // 長出期間不呼吸：每一格都停在最深。
      var frames = 0;
      while (!motion.skeleton.isCompleted) {
        expect(await sample(tester), everyElement(0), reason: '長出第 $frames 格');
        await tester.pump(frame);
        frames++;
      }
      expect(frames, greaterThan(30), reason: '長出要播完一整段');
      // 長完先停 idle（這一格整片重建），停的期間整片最深。
      var previous = await sample(tester);
      expect(previous, everyElement(0));
      var still = 0;
      while (!motion.breathing.value) {
        await tester.pump(frame);
        expect(await sample(tester), everyElement(0), reason: '長完停的第 $still 格');
        still++;
      }
      expect(still, greaterThan(4), reason: '停滿 idle 才呼吸');
      // 開始呼吸：從整片最深開始，左邊先變淺、右邊還沒輪到，一路接得上。
      previous = await pumpSmoothly(tester, previous, 12);
      expect(previous.first, greaterThan(0), reason: '左邊先開始變淺');
      expect(previous.last, 0, reason: '右邊還沒輪到');
      previous = await pumpSmoothly(tester, previous, cycleFrames);
      expect(previous.toSet(), hasLength(greaterThan(1)), reason: '照常由左而右呼吸');
    });

    testWidgets('finishes each position\'s breath and stops it at the '
        'deepest, without a jump', (tester) async {
      await setUpView(tester);
      await tester.pumpWidget(host());
      await grow(tester);
      // 呼吸到一半：左右兩端深淺不同，都還在變。
      await tester.pump(const Duration(milliseconds: 300));
      var previous = await sample(tester);
      expect(previous.toSet(), hasLength(greaterThan(1)), reason: '由左而右呼吸');

      var rested = false;
      unawaited(motion.rest.settle().then((_) => rested = true));
      final stopped = <int>{};
      var frames = 0;
      while (!rested) {
        await tester.pump(frame);
        expect(++frames, lessThanOrEqualTo(cycleFrames), reason: '最多再呼一輪');
        final now = await sample(tester);
        for (var i = 0; i < xs.length; i++) {
          expect((now[i] - previous[i]).abs(), lessThanOrEqualTo(maxStep));
          // 停在最深的位置不再動。
          if (stopped.contains(i)) expect(now[i], 0, reason: 'x=${xs[i]}');
          if (now[i] == 0) stopped.add(i);
        }
        previous = now;
      }
      await tester.pump(frame);
      expect(await sample(tester), everyElement(0), reason: '整條都停在最深');
      await tester.pump(const Duration(milliseconds: 500));
      expect(await sample(tester), everyElement(0), reason: '停住不再呼吸');
      expect(tester.hasRunningAnimations, isFalse);

      // 換場後還留著的骨架接著呼吸：從整片最深由左而右重新開始，不跳。
      motion.rest.release();
      previous = await pumpSmoothly(tester, previous, cycleFrames * 2);
      expect(previous.toSet(), hasLength(greaterThan(1)), reason: '又在呼吸');
    });

    testWidgets('a rest that starts before the right edge\'s turn still lets '
        'every position breathe once', (tester) async {
      await setUpView(tester);
      await tester.pumpWidget(host());
      await grow(tester);
      // 剛開始呼吸就收住：右邊還沒輪到，也要呼完第一口才停。
      var rested = false;
      unawaited(motion.rest.settle().then((_) => rested = true));
      final lightest = List.filled(xs.length, 0);
      var previous = await sample(tester);
      var frames = 0;
      while (!rested) {
        await tester.pump(frame);
        expect(++frames, lessThanOrEqualTo(cycleFrames * 3 ~/ 2 + 1));
        final now = await sample(tester);
        for (var i = 0; i < xs.length; i++) {
          expect((now[i] - previous[i]).abs(), lessThanOrEqualTo(maxStep));
          if (now[i] > lightest[i]) lightest[i] = now[i];
        }
        previous = now;
      }
      for (var i = 0; i < xs.length; i++) {
        expect(lightest[i], greaterThan(50), reason: 'x=${xs[i]} 要呼一口');
      }
      await tester.pump(frame);
      expect(await sample(tester), everyElement(0), reason: '整條都停在最深');
    });

    testWidgets('a skeleton hidden mid-rest counts as rested instead of '
        'holding the launch forever', (tester) async {
      await setUpView(tester);
      await tester.pumpWidget(host());
      await grow(tester);
      await tester.pump(const Duration(milliseconds: 300));
      var rested = false;
      unawaited(motion.rest.settle().then((_) => rested = true));
      await tester.pump(frame);
      await tester.pump(frame);
      expect(rested, isFalse);

      await tester.pumpWidget(host(ticking: false));
      await tester.pump(frame);
      expect(rested, isTrue);
      // 再出現時停在最深，不接著呼吸。
      await tester.pumpWidget(host());
      await tester.pump(frame);
      expect(await sample(tester), everyElement(0));
    });

    testWidgets('turning animations off mid-rest leaves nothing ticking after '
        'the release', (tester) async {
      await setUpView(tester);
      await tester.pumpWidget(host());
      await grow(tester);
      await tester.pump(const Duration(milliseconds: 700));
      var rested = false;
      unawaited(motion.rest.settle().then((_) => rested = true));
      await tester.pump(frame);

      await tester.pumpWidget(host(reduce: true));
      await tester.pump(frame);
      expect(rested, isTrue);
      motion.rest.release();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a skeleton that appears mid-rest starts at the deepest and '
        'does not stretch the rest', (tester) async {
      await setUpView(tester);
      await tester.pumpWidget(host());
      await grow(tester);
      await tester.pump(const Duration(milliseconds: 300));
      var rested = false;
      unawaited(motion.rest.settle().then((_) => rested = true));
      await tester.pump(const Duration(milliseconds: 480));

      await tester.pumpWidget(host(second: true));
      expect(await sample(tester, row: 1), everyElement(0), reason: '一出現就最深');
      var frames = 30;
      while (!rested) {
        await tester.pump(frame);
        expect(++frames, lessThanOrEqualTo(cycleFrames), reason: '總共最多再呼一輪');
        expect(await sample(tester, row: 1), everyElement(0));
      }
    });

    testWidgets('tearing the launch down mid-rest ends the reveal quietly', (
      tester,
    ) async {
      await setUpView(tester);
      await tester.pumpWidget(host());
      // 隔 idle 長出（0.6 秒）、停 idle、呼吸半輪後開始收住。
      unawaited(
        motion.reveal(
          change: () {},
          duration: const Duration(milliseconds: 600),
          sweep: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 820));
      await tester.pump(frame);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(frame);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  });

  Widget host(Widget child, {bool disableAnimations = false}) => MaterialApp(
    theme: buildAppTheme(AppStyle.paper, Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  );

  testWidgets('switcher fades the content in over the skeleton', (
    tester,
  ) async {
    Widget switcher(bool loading) => host(
      SkeletonSwitcher(
        loading: loading,
        skeleton: const SkeletonBox(width: 40, height: 40),
        builder: (_) => const Text('內容'),
      ),
    );

    await tester.pumpWidget(switcher(true));
    expect(find.byType(SkeletonBox), findsOneWidget);
    expect(find.text('內容'), findsNothing);
    // 骨架在呼吸。
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(switcher(false));
    await tester.pump(AppMotion.fade ~/ 2);
    expect(find.byType(SkeletonBox), findsOneWidget);
    expect(find.text('內容'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(SkeletonBox), findsNothing);
    expect(find.text('內容'), findsOneWidget);
  });

  group('waitForCovers', () {
    // 假封面：建好時登記，[decoded] 變成 true 時回報解碼好。
    final decoded = ValueNotifier(false);
    setUp(() => decoded.value = false);

    Widget switcher(bool loading) => host(
      SkeletonSwitcher(
        loading: loading,
        waitForCovers: CoverWait.onDevice,
        skeleton: const SkeletonBox(width: 40, height: 40),
        builder: (_) => ValueListenableBuilder<bool>(
          valueListenable: decoded,
          builder: (context, done, _) {
            final reveal = CoverRevealScope.waitingOf(context);
            done ? reveal?.remove('cover') : reveal?.add('cover');
            return const Text('內容');
          },
        ),
      ),
    );

    double contentOpacity(WidgetTester tester) => tester
        .widget<SkeletonRevealLayer>(
          find
              .ancestor(
                of: find.text('內容'),
                matching: find.byType(SkeletonRevealLayer),
              )
              .first,
        )
        .presence
        .value;

    testWidgets('the page waits for its covers, then fades in once', (
      tester,
    ) async {
      await tester.pumpWidget(switcher(true));
      await tester.pumpWidget(switcher(false));
      await tester.pump(const Duration(milliseconds: 100));
      // 內容已經建在骨架底下，還全透明，也點不到。
      expect(contentOpacity(tester), 0);
      expect(find.byType(SkeletonBox), findsOneWidget);
      expect(
        tester
            .hitTestOnBinding(tester.getCenter(find.text('內容')))
            .path
            .any((entry) => entry.target is RenderParagraph),
        isFalse,
      );

      decoded.value = true;
      await tester.pump();
      await tester.pump();
      await tester.pump(SkeletonReveal.defaultDuration ~/ 2);
      expect(contentOpacity(tester), inExclusiveRange(0, 1));
      expect(find.byType(SkeletonBox), findsOneWidget);

      await tester.pumpAndSettle();
      expect(contentOpacity(tester), 1);
      expect(find.byType(SkeletonBox), findsNothing);
    });

    testWidgets('a reload that finishes mid-fade still waits fully hidden', (
      tester,
    ) async {
      decoded.value = true;
      await tester.pumpWidget(switcher(false));
      decoded.value = false;
      await tester.pumpWidget(switcher(true));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.pumpWidget(switcher(false));
      await tester.pump(const Duration(milliseconds: 20));
      expect(contentOpacity(tester), 0);

      decoded.value = true;
      await tester.pumpAndSettle();
      expect(contentOpacity(tester), 1);
    });

    testWidgets('a slow cover holds the page however long it takes; one that '
        'fails or goes away stops holding it', (tester) async {
      await tester.pumpWidget(switcher(true));
      await tester.pumpWidget(switcher(false));
      // 沒有時間上限：解碼得再久也等（原本 300ms 就不等了）。
      await tester.pump(const Duration(seconds: 3));
      expect(contentOpacity(tester), 0);
      expect(find.byType(SkeletonBox), findsOneWidget);

      // 失敗也算畫得出來（改畫預設封面）：不再等它。
      decoded.value = true;
      await tester.pump();
      await tester.pump();
      await tester.pump(SkeletonReveal.defaultDuration ~/ 2);
      expect(contentOpacity(tester), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonBox), findsNothing);
    });

    testWidgets('a cover taken off the page stops holding it', (tester) async {
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      await tester.pumpWidget(
        host(
          SkeletonSwitcher(
            loading: true,
            waitForCovers: CoverWait.onDevice,
            skeleton: const SkeletonBox(width: 40, height: 40),
            builder: (_) => const SizedBox(),
          ),
        ),
      );
      await tester.pumpWidget(
        host(
          SkeletonSwitcher(
            loading: false,
            waitForCovers: CoverWait.onDevice,
            skeleton: const SkeletonBox(width: 40, height: 40),
            builder: (_) => ValueListenableBuilder<bool>(
              valueListenable: shown,
              builder: (context, visible, _) =>
                  visible ? const _PendingCover() : const Text('內容'),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(SkeletonBox), findsOneWidget, reason: '封面還沒好');

      shown.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonBox), findsNothing);
    });
  });

  testWidgets('the skeleton stays still when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Skeleton(child: SkeletonBox(width: 40, height: 40)),
        disableAnimations: true,
      ),
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  // 骨架每一幀重用同一支畫筆（_breathingPaint）：上一筆留下的半透明顏色會
  // 乘到漸層上，讓呼吸的骨架變淡（PR #150 審查時 Codex 重現的）。
  group('the reused brush', () {
    for (final dark in [false, true]) {
      final label = dark ? 'dark' : 'light';
      final background = dark ? Colors.black : Colors.white;

      Future<List<int>> redAt(
        WidgetTester tester,
        GlobalKey boundary,
        List<Offset> points,
      ) async => (await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        image.dispose();
        return [
          for (final p in points)
            bytes!.getUint8(((p.dy.toInt()) * 200 + p.dx.toInt()) * 4),
        ];
      }))!;

      testWidgets('breathing after animations come back is as deep as a '
          'fresh skeleton ($label)', (tester) async {
        tester.view.physicalSize = const Size(200, 200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final boundary = GlobalKey();
        Widget page({required bool still, required Key key}) => MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(200, 200),
              disableAnimations: still,
            ),
            child: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: background,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Skeleton(
                    key: key,
                    child: const SkeletonBox(width: 100, height: 20),
                  ),
                ),
              ),
            ),
          ),
        );
        // 減少動態時畫的是半透明的單色，接著換回呼吸。
        await tester.pumpWidget(page(still: true, key: const ValueKey(1)));
        await tester.pumpWidget(page(still: false, key: const ValueKey(1)));
        final reused = await redAt(tester, boundary, const [Offset(10, 10)]);
        await tester.pumpWidget(page(still: false, key: const ValueKey(2)));
        final fresh = await redAt(tester, boundary, const [Offset(10, 10)]);
        expect(reused, fresh);
      });

      testWidgets('a see-through filled shape does not fade the breathing '
          'shape after it ($label)', (tester) async {
        tester.view.physicalSize = const Size(200, 200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: background,
                child: Skeleton(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonShapes(
                        height: 40,
                        shapes: (_) => const [
                          SkeletonShape(
                            Rect.fromLTWH(0, 0, 100, 10),
                            fill: Color(0x80000000),
                          ),
                          SkeletonShape(Rect.fromLTWH(0, 20, 100, 20)),
                        ],
                      ),
                      // 同一個位置、自己一支畫筆的骨架當對照。
                      const SkeletonBox(width: 100, height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final [shape, reference] = await redAt(tester, boundary, const [
          Offset(10, 30),
          Offset(10, 50),
        ]);
        expect(shape, reference);
      });
    }
  });
}

/// 一張還畫不出來的封面：建好時登記在等待裡，拆掉時拿掉（像
/// `BookCoverWidget`）。
class _PendingCover extends StatefulWidget {
  const _PendingCover();

  @override
  State<_PendingCover> createState() => _PendingCoverState();
}

class _PendingCoverState extends State<_PendingCover> {
  CoverReveal? _waitingOn;

  @override
  void dispose() {
    _waitingOn?.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _waitingOn ??= CoverRevealScope.waitingOf(context)?..add(this);
    return const SizedBox(width: 40, height: 40);
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';
import 'package:night_reader/shared/widgets/painted_when.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

import '../../support/glass_motion.dart';

void main() {
  var leftTaps = 0;
  var finished = 0;

  /// 書架的內容建了幾次（[SkeletonSwitcher.builder]）。
  var contentBuilds = 0;

  /// 像主頁：頁首左右各一顆玻璃按鈕，內容是書架的骨架換場。
  Widget host({
    required bool loading,
    Widget? later,
    CoverWait? waitForCovers,
  }) => MaterialApp(
    theme: buildAppTheme(AppStyle.paper, Brightness.light),
    home: LaunchEntrance(
      onFinished: () => finished++,
      child: Scaffold(
        appBar: GlassNavHeader(
          morph: true,
          title: '書架',
          leading: GlassIconButton(
            icon: Icons.menu,
            onPressed: () => leftTaps++,
          ),
          actions: [GlassIconButton(icon: Icons.add, onPressed: () {})],
        ),
        bottomNavigationBar: FloatingTabBar(
          items: const [
            FloatingTabItem(
              icon: Icons.book_outlined,
              selectedIcon: Icons.book,
              label: '書',
            ),
            FloatingTabItem(
              icon: Icons.explore_outlined,
              selectedIcon: Icons.explore,
              label: '發現',
            ),
          ],
          currentIndex: 0,
          onTap: (_) {},
          onSearch: () {},
        ),
        body: Stack(
          children: [
            Builder(
              builder: (context) => SkeletonSwitcher(
                loading: loading,
                waitForCovers: waitForCovers,
                entrance: LaunchEntrance.maybeOf(context),
                skeleton: const SkeletonBox(width: 40, height: 40),
                builder: (_) {
                  contentBuilds++;
                  return const Text('內容');
                },
              ),
            ),
            ?later,
          ],
        ),
      ),
    ),
  );

  setUp(() {
    leftTaps = 0;
    finished = 0;
    contentBuilds = 0;
  });

  /// 這一格畫面上有幾塊玻璃在取樣背景（真的畫出來的背景模糊）。
  int paintedGlass(WidgetTester tester) {
    var count = 0;
    void visit(Layer? layer) {
      for (; layer != null; layer = layer.nextSibling) {
        if (layer is BackdropFilterLayer) count++;
        if (layer is ContainerLayer) visit(layer.firstChild);
      }
    }

    visit(tester.binding.renderViews.first.debugLayer);
    return count;
  }

  LaunchEntranceMotion motionOf(WidgetTester tester) =>
      LaunchEntrance.maybeOf(tester.element(find.byType(SkeletonSwitcher)))!;

  /// 換場中：螢幕上只貼兩張圖（拍好後停住的那幾格也算），內容在底下建好
  /// 了，畫面上沒有在畫的玻璃（圖裡的玻璃不另外取樣背景）。
  bool crossfading(WidgetTester tester) =>
      motionOf(tester).screen.playing &&
      find.text('內容').evaluate().isNotEmpty &&
      paintedGlass(tester) == 0;

  /// 長完到換場開始最多幾格：拍圖、停 idle、呼吸半輪，收住（最多再一輪
  /// 半），或呼吸收住後才拍圖。
  final untilCrossfade =
      (LaunchEntranceMotion.idle * 2 +
                  LaunchEntranceMotion.pause +
                  LaunchEntranceMotion.breathCycle * 1.5)
              .inMilliseconds ~/
          16 +
      10;

  /// 推進一格。定格畫面照一般的畫法拍（ADR 0035），圖要讓出真實時間才拿
  /// 得到。
  Future<void> frame(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// 第一幀之後：準備工作做完的那一格畫完、拍好長出前的兩張圖、隔 idle，
  /// 推進到開始長骨架的那一格。
  Future<void> startGrowing(WidgetTester tester) async {
    final motion = motionOf(tester);
    for (var i = 0; i < 60 && motion.skeleton.value == 0; i++) {
      await frame(tester);
    }
    expect(motion.skeleton.value, greaterThan(0), reason: '開始長骨架');
  }

  /// 一格一格推進，直到換場開始（最多 [frames] 格）；回傳推進了幾格。
  Future<int> pumpUntilCrossfading(WidgetTester tester, {int? frames}) async {
    frames ??= untilCrossfade;
    for (var i = 0; i < frames; i++) {
      if (crossfading(tester)) return i;
      await frame(tester);
    }
    return frames;
  }

  /// 一格一格推進到進場結束（最多 [frames] 格）。
  Future<void> pumpUntilFinished(
    WidgetTester tester, {
    int frames = 300,
  }) async {
    for (var i = 0; i < frames && finished == 0; i++) {
      await frame(tester);
    }
    await tester.pump();
  }

  /// 按鈕位置上骨架的濃度；骨架拿掉後是 0。
  double buttonSkeleton(WidgetTester tester, IconData icon) {
    final boxes = find.descendant(
      of: find.ancestor(
        of: find.byIcon(icon),
        matching: find.byType(LaunchSkeleton),
      ),
      matching: find.byType(SkeletonBox),
    );
    if (boxes.evaluate().isEmpty) return 0;
    return tester.widget<SkeletonBox>(boxes).color!.a;
  }

  RenderSkeletonRevealLayer shelfSkeleton(WidgetTester tester) =>
      tester.renderObject(
        find
            .ancestor(
              of: find.byWidgetPredicate(
                (widget) => widget is SkeletonBox && widget.width == 40,
              ),
              matching: find.byType(SkeletonRevealLayer),
            )
            .first,
      );

  testWidgets('the first frame is only the background', (tester) async {
    await tester.pumpWidget(host(loading: true));
    expect(shelfSkeleton(tester).alphaAt(0), 0, reason: '和系統啟動畫面一樣只有底色');
    expect(buttonSkeleton(tester, Icons.menu), 0);
    expect(paintedGlass(tester), 0, reason: '玻璃還沒畫、不取樣背景');
  });

  testWidgets('starts growing only once the startup work is done, the frame '
      'after it is drawn and idle has passed', (tester) async {
    final prepared = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: LaunchEntrance(
          prepared: () => prepared.future,
          child: Builder(
            builder: (context) => SkeletonSwitcher(
              loading: true,
              entrance: LaunchEntrance.maybeOf(context),
              skeleton: const SkeletonBox(width: 40, height: 40),
              builder: (_) => const SizedBox(),
            ),
          ),
        ),
      ),
    );
    final motion = LaunchEntrance.maybeOf(
      tester.element(find.byType(SkeletonSwitcher)),
    )!;
    await tester.pump(const Duration(seconds: 1));
    expect(motion.skeleton.value, 0, reason: '準備工作還沒做完');

    prepared.complete();
    // 一格一格推進：做完、那一格畫完，拍長出前的兩張圖（底色那張等一格、
    // 骨架那張再等一格、換回底色再一格），再隔 idle 才開始長。
    const frame = Duration(milliseconds: 16);
    var waited = Duration.zero;
    while (!motion.skeleton.isAnimating &&
        waited < const Duration(seconds: 1)) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(frame);
      waited += frame;
    }
    expect(waited, greaterThanOrEqualTo(LaunchEntranceMotion.idle));
    expect(waited, lessThanOrEqualTo(LaunchEntranceMotion.idle + frame * 6));
    await tester.pump(frame);
    expect(motion.skeleton.value, greaterThan(0));
  });

  testWidgets('still grows when the startup work fails', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LaunchEntrance(
          prepared: () => Future.error(StateError('讀不到')),
          child: Builder(
            builder: (context) => SkeletonSwitcher(
              loading: true,
              entrance: LaunchEntrance.maybeOf(context),
              skeleton: const SkeletonBox(width: 40, height: 40),
              builder: (_) => const SizedBox(),
            ),
          ),
        ),
      ),
    );
    final motion = LaunchEntrance.maybeOf(
      tester.element(find.byType(SkeletonSwitcher)),
    )!;
    await tester.pump();
    expect(tester.takeException(), isStateError, reason: '錯誤照樣回報');
    for (var i = 0; i < 20 && motion.skeleton.value == 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(motion.skeleton.value, greaterThan(0), reason: '不能停在底色');
  });

  testWidgets('breathes only idle after the skeleton has grown', (
    tester,
  ) async {
    await tester.pumpWidget(host(loading: true));
    await startGrowing(tester);
    final motion = LaunchEntrance.maybeOf(
      tester.element(find.byType(SkeletonSwitcher)),
    )!;
    while (!motion.skeleton.isCompleted) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(motion.breathing.value, isFalse, reason: '長完先停一下，重建落在靜止的畫面');
    await tester.pump(
      LaunchEntranceMotion.idle - const Duration(milliseconds: 10),
    );
    expect(motion.breathing.value, isFalse);
    await tester.pump(const Duration(milliseconds: 10));
    expect(motion.breathing.value, isTrue);
    await tester.pumpWidget(host(loading: false));
    await tester.pump(LaunchEntranceMotion.pause);
    await pumpUntilCrossfading(tester);
    await tester.pump(LaunchEntranceMotion.idle);
    await tester.pumpAndSettle();
  });

  testWidgets('buttons grow in as skeletons with the shelf; then the whole '
      'screen turns into content as one crossfade of two still pictures', (
    tester,
  ) async {
    await tester.pumpWidget(host(loading: true));
    await startGrowing(tester);
    await tester.pump(const Duration(milliseconds: 200));
    final growing = shelfSkeleton(tester);
    expect(growing.alphaAt(0), greaterThan(growing.alphaAt(1)));
    expect(
      buttonSkeleton(tester, Icons.menu),
      greaterThan(buttonSkeleton(tester, Icons.add)),
      reason: '左邊的按鈕骨架先長出來',
    );
    expect(paintedGlass(tester), 0, reason: '玻璃還沒出現');
    final titleBar = tester.getRect(
      find.descendant(
        of: find.ancestor(
          of: find.text('書架'),
          matching: find.byType(LaunchSkeleton),
        ),
        matching: find.byType(SkeletonBox),
      ),
    );
    final titleText = tester.getRect(find.text('書架'));
    expect(titleBar.width, titleText.width, reason: '長條和字同寬');
    expect(titleBar.height, lessThan(titleText.height), reason: '約字身高');
    expect(titleBar.center.dy, closeTo(titleText.center.dy, 0.5));

    // 骨架還在出現時書就到了：先不建內容。
    await tester.pumpWidget(host(loading: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('內容'), findsNothing);

    // 骨架出現播完（0.6 秒）：長完停的時候拍下骨架畫面、換成內容拍下換好
    // 的畫面、換回骨架；停 idle 後呼吸一口，收住就換場，之後只貼兩張圖。
    final motion = motionOf(tester);
    while (!motion.breathing.value) {
      await frame(tester);
    }
    expect(find.byType(SkeletonBox), findsWidgets, reason: '換回骨架照常呼吸');
    expect(motion.revealed.value, isFalse, reason: '頁首與分頁列也換回骨架');
    expect(crossfading(tester), isFalse);
    expect(await pumpUntilCrossfading(tester), lessThan(untilCrossfade));
    expect(find.text('內容'), findsOneWidget, reason: '底下已經換成內容');

    // 換上骨架那張圖的那一格畫完，下一格開始掃。
    await frame(tester);
    await frame(tester);
    await tester.pump(SkeletonReveal.defaultDuration ~/ 2);
    expect(crossfading(tester), isTrue, reason: '換場的 0.6 秒裡只貼兩張圖');
    await tester.tap(find.byIcon(Icons.menu), warnIfMissed: false);
    expect(leftTaps, 0, reason: '換場中不接點擊');
    expect(finished, 0);

    await tester.pump(SkeletonReveal.defaultDuration ~/ 2);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(paintedGlass(tester), greaterThan(0), reason: '換回真的畫面，玻璃照常畫');
    expectNoGlassUnderFade(tester);
    await tester.pump();
    expect(finished, 1, reason: '換場播完才開始背景工作');
    await tester.tap(find.byIcon(Icons.menu));
    expect(leftTaps, 1);
  });

  testWidgets('pictures taken before the breath: the sweep starts as soon as '
      'the breath rests', (tester) async {
    await tester.pumpWidget(host(loading: false));
    await startGrowing(tester);
    final motion = motionOf(tester);
    while (!motion.breathing.value) {
      await frame(tester);
    }
    expect(await pumpUntilCrossfading(tester), lessThan(untilCrossfade));
    // 換上「之前」那張圖的那一格畫完，下一格就開始掃。
    await frame(tester);
    await frame(tester);
    expect(tester.hasRunningAnimations, isTrue, reason: '不再停 idle');
    await pumpUntilFinished(tester);
    expect(finished, 1);
  });

  testWidgets('books read only after the breath began: the sweep starts only '
      'idle after both pictures are taken', (tester) async {
    await tester.pumpWidget(host(loading: true));
    await startGrowing(tester);
    final motion = motionOf(tester);
    while (!motion.breathing.value) {
      await frame(tester);
    }
    await tester.pumpWidget(host(loading: false));
    // 兩張都拍好、只貼「之前」那張圖的第一格（玻璃不再畫）：間隔從拍好
    // 「之後」那一格開始算，最多早這一格。
    expect(await pumpUntilCrossfading(tester), lessThan(untilCrossfade));
    expect(tester.hasRunningAnimations, isFalse, reason: '拍好後的間隔裡畫面不動');
    await tester.pump(
      LaunchEntranceMotion.idle - const Duration(milliseconds: 40),
    );
    expect(tester.hasRunningAnimations, isFalse, reason: '還沒滿 idle');
    await tester.pump(const Duration(milliseconds: 56));
    expect(tester.hasRunningAnimations, isTrue, reason: '滿 idle 才開始掃');
    await pumpUntilFinished(tester);
    expect(finished, 1);
  });

  testWidgets('a screen size change mid-crossfade ends it and shows the real '
      'screen at once', (tester) async {
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(loading: false));
    await startGrowing(tester);
    await tester.pump(const Duration(milliseconds: 620));
    await tester.pump(LaunchEntranceMotion.idle);
    await tester.pump(LaunchEntranceMotion.pause);
    expect(await pumpUntilCrossfading(tester), lessThan(untilCrossfade));
    await tester.pump(const Duration(milliseconds: 100));
    expect(crossfading(tester), isTrue);

    // 例如旋轉：兩張圖對不上新的大小。
    tester.view.physicalSize = const Size(1600, 900);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(paintedGlass(tester), greaterThan(0), reason: '換回真的畫面');
    await tester.pump();
    expect(finished, 1);
  });

  testWidgets('says it finished only once, not again on later reloads', (
    tester,
  ) async {
    await tester.pumpWidget(host(loading: true));
    await startGrowing(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(finished, 0, reason: '骨架出現播完、書還沒到');

    await tester.pumpWidget(host(loading: false));
    await pumpUntilFinished(tester);
    expect(finished, 1);

    // 重新載入時骨架一直呼吸，用固定時間走完換回骨架。
    await tester.pumpWidget(host(loading: true));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(host(loading: false));
    await tester.pumpAndSettle();
    expect(finished, 1, reason: '之後重新載入書架不算');
    expect(find.text('內容'), findsOneWidget);
    expect(find.byType(SkeletonBox), findsNothing);
  });

  testWidgets('reloading mid-reveal ends the crossfade and grows the skeleton '
      'back live, without errors', (tester) async {
    Widget at({required bool loading}) =>
        host(loading: loading, waitForCovers: CoverWait.onDevice);
    await tester.pumpWidget(at(loading: false));
    await startGrowing(tester);
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(LaunchEntranceMotion.idle);
    await tester.pump(LaunchEntranceMotion.pause);
    expect(await pumpUntilCrossfading(tester), lessThan(untilCrossfade));
    await tester.pump(const Duration(milliseconds: 200));
    expect(crossfading(tester), isTrue);

    await tester.pumpWidget(at(loading: true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(paintedGlass(tester), greaterThan(0), reason: '換回真的畫面');
    await tester.pumpWidget(at(loading: false));
    await tester.pumpAndSettle();
    expect(find.text('內容'), findsOneWidget);
    expect(find.byType(SkeletonBox), findsNothing);
  });

  testWidgets('glass built after the entrance is drawn directly', (
    tester,
  ) async {
    await tester.pumpWidget(host(loading: false));
    // 進場裡的間隔是計時器，沒有畫面要畫：一格一格推進到進場結束。
    await pumpUntilFinished(tester);
    expect(finished, 1);
    // 例如進場結束後才第一次打開的分頁。
    await tester.pumpWidget(
      host(
        loading: false,
        later: LaunchSkeleton(
          child: GlassIconButton(icon: Icons.close, onPressed: () {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SkeletonBox), findsNothing);
    expect(find.byIcon(Icons.close).hitTestable(), findsOneWidget);
  });

  group('when the shelf is prepared', () {
    /// 一格一格推進，直到內容又建了一次（比 [before] 多）；回傳那一格之前，
    /// 畫面是不是已經靜止（沒有動畫在跑）。長出、呼吸與收住的每一格，內容
    /// 都不能建。
    Future<bool> pumpUntilBuilt(WidgetTester tester, {int before = 0}) async {
      for (var i = 0; i < 300; i++) {
        final stillBefore = !tester.hasRunningAnimations;
        await frame(tester);
        if (contentBuilds > before) return stillBefore;
      }
      fail('內容一直沒有建');
    }

    testWidgets('books read before the skeleton has grown: nothing is built '
        'while it grows; once it has grown and that frame is drawn, the shelf '
        'is built and both pictures taken while the screen is still, and the '
        'breath that follows builds nothing', (tester) async {
      await tester.pumpWidget(
        host(loading: false, waitForCovers: CoverWait.onDevice),
      );
      await startGrowing(tester);
      final motion = motionOf(tester);
      expect(
        await pumpUntilBuilt(tester),
        isTrue,
        reason: '長完那一格畫完、畫面靜止了，下一格才建書架',
      );
      expect(motion.skeleton.isCompleted, isTrue);
      expect(motion.breathing.value, isFalse, reason: '呼吸前就建好');
      while (!motion.breathing.value) {
        await frame(tester);
      }
      final built = contentBuilds;
      expect(await pumpUntilCrossfading(tester), lessThan(untilCrossfade));
      expect(contentBuilds, built, reason: '呼吸與收住時不再建');
      expect(tester.takeException(), isNull);
      await pumpUntilFinished(tester);
      expect(finished, 1);
    });

    testWidgets('the shelf built under the breathing skeleton is neither drawn '
        'nor tappable', (tester) async {
      await tester.pumpWidget(host(loading: false));
      await startGrowing(tester);
      final motion = motionOf(tester);
      while (!motion.breathing.value) {
        await frame(tester);
      }
      expect(find.text('內容'), findsOneWidget, reason: '建好了');
      bool painted() => tester
          .widget<PaintedWhen>(
            find
                .ancestor(
                  of: find.text('內容'),
                  matching: find.byType(PaintedWhen),
                )
                .first,
          )
          .shown;
      expect(painted(), isFalse, reason: '被骨架蓋住，不畫');
      expect(find.text('內容').hitTestable(), findsNothing, reason: '點不到');
      await pumpUntilFinished(tester);
      expect(painted(), isTrue);
      expect(find.text('內容').hitTestable(), findsOneWidget);
    });

    testWidgets('books read only after the pause: the rest starts then, and '
        'nothing is built until it is still', (tester) async {
      await tester.pumpWidget(
        host(loading: true, waitForCovers: CoverWait.onDevice),
      );
      await startGrowing(tester);
      await tester.pump(const Duration(milliseconds: 620));
      await tester.pump(LaunchEntranceMotion.idle);
      await tester.pump(LaunchEntranceMotion.pause * 2);
      expect(tester.hasRunningAnimations, isTrue, reason: '書還沒到，骨架照常呼吸');

      await tester.pumpWidget(
        host(loading: false, waitForCovers: CoverWait.onDevice),
      );
      expect(await pumpUntilBuilt(tester), isTrue);
      await pumpUntilFinished(tester);
      expect(finished, 1);
    });

    testWidgets('a reload during the breath drops the pictures taken before '
        'it, prepares again once the breath rests, and still ends the '
        'entrance once', (tester) async {
      Widget at({required bool loading}) =>
          host(loading: loading, waitForCovers: CoverWait.onDevice);
      await tester.pumpWidget(at(loading: false));
      await startGrowing(tester);
      final motion = motionOf(tester);
      while (!motion.breathing.value) {
        await frame(tester);
      }
      // 呼吸的頭一段一格一格推進：開始呼吸後才算停頓。
      for (var i = 0; i < 6; i++) {
        await frame(tester);
      }
      expect(tester.hasRunningAnimations, isTrue, reason: '還在呼吸');
      expect(motion.screen.captured, isTrue);

      await tester.pumpWidget(at(loading: true));
      await tester.pump(const Duration(milliseconds: 50));
      expect(motion.screen.captured, isFalse, reason: '拍好的圖放掉');
      await tester.pumpWidget(at(loading: false));
      final built = contentBuilds;
      expect(await pumpUntilBuilt(tester, before: built), isTrue);
      await pumpUntilFinished(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('內容'), findsOneWidget);
      expect(finished, 1);
    });
  });

  group('preparation that cannot go on', () {
    /// 頁首一顆按鈕骨架加上書架；[reduce] 是系統要求減少動態，[shelf] 為
    /// false 時拆掉書架、留下進場與頁首。
    Widget bare({
      required bool loading,
      bool reduce = false,
      bool shelf = true,
    }) => MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: LaunchEntrance(
            onFinished: () => finished++,
            child: Column(
              children: [
                const LaunchSkeleton(child: SizedBox(width: 40, height: 40)),
                Expanded(
                  child: shelf
                      ? Builder(
                          builder: (context) => SkeletonSwitcher(
                            loading: loading,
                            entrance: LaunchEntrance.maybeOf(context),
                            waitForCovers: CoverWait.onDevice,
                            skeleton: const SkeletonBox(width: 40, height: 40),
                            builder: (_) => const Text('內容'),
                          ),
                        )
                      : const SizedBox(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    LaunchEntranceMotion motionIn(WidgetTester tester) =>
        LaunchEntrance.maybeOf(tester.element(find.byType(LaunchSkeleton)))!;

    /// 推進到呼吸前拍圖拍到一半：頁首已經暫時換成真的、還沒換回骨架。
    Future<void> pumpUntilHalfCaptured(WidgetTester tester) async {
      final motion = motionIn(tester);
      for (var i = 0; i < 200; i++) {
        await frame(tester);
        if (motion.revealed.value && !motion.revealStarted) return;
      }
      fail('沒有拍到一半的時候');
    }

    testWidgets('reduced motion with the books arriving later still turns '
        'into content and finishes once', (tester) async {
      await tester.pumpWidget(bare(loading: true, reduce: true));
      await tester.pumpWidget(bare(loading: false, reduce: true));
      for (var i = 0; i < 150; i++) {
        await frame(tester);
      }
      expect(find.text('內容'), findsOneWidget);
      expect(finished, 1);
    });

    testWidgets('a reload halfway through the pictures turns the header back '
        'into a skeleton and the breath still starts', (tester) async {
      await tester.pumpWidget(bare(loading: false));
      await pumpUntilHalfCaptured(tester);
      final motion = motionIn(tester);
      expect(motion.breathing.value, isFalse);
      await tester.pumpWidget(bare(loading: true));
      for (var i = 0; i < 30; i++) {
        await frame(tester);
      }
      expect(motion.breathing.value, isTrue);
      expect(motion.revealed.value, isFalse, reason: '頁首換回骨架');
      expect(motion.screen.captured, isFalse);
    });

    testWidgets('removing the shelf halfway through the pictures drops them '
        'and the breath still starts', (tester) async {
      await tester.pumpWidget(bare(loading: false));
      await pumpUntilHalfCaptured(tester);
      final motion = motionIn(tester);
      await tester.pumpWidget(bare(loading: false, shelf: false));
      for (var i = 0; i < 30; i++) {
        await frame(tester);
      }
      expect(motion.screen.captured, isFalse, reason: '兩張圖放掉');
      expect(motion.revealed.value, isFalse);
      expect(motion.breathing.value, isTrue);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/launch_entrance.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

import '../../support/glass_motion.dart';

void main() {
  var leftTaps = 0;
  var finished = 0;

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
                builder: (_) => const Text('內容'),
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

  /// 換場中：骨架已經換掉（只在第一張圖裡）、內容在底下建好了，但畫面上
  /// 沒有在畫的玻璃（兩張圖裡的玻璃不另外取樣背景）。
  bool crossfading(WidgetTester tester) =>
      find.byType(SkeletonBox).evaluate().isEmpty &&
      find.text('內容').evaluate().isNotEmpty &&
      paintedGlass(tester) == 0;

  /// 停頓結束到換場開始最多幾格：先收住呼吸（最多再呼一輪），再拍圖。
  final untilCrossfade = Skeleton.breathCycle.inMilliseconds ~/ 16 + 10;

  /// 一格一格推進，直到換場開始（最多 [frames] 格）；回傳推進了幾格。
  Future<int> pumpUntilCrossfading(WidgetTester tester, {int? frames}) async {
    frames ??= untilCrossfade;
    for (var i = 0; i < frames; i++) {
      if (crossfading(tester)) return i;
      await tester.pump(const Duration(milliseconds: 16));
    }
    return frames;
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

  testWidgets('buttons grow in as skeletons with the shelf; then the whole '
      'screen turns into content as one crossfade of two still pictures', (
    tester,
  ) async {
    await tester.pumpWidget(host(loading: true));
    await tester.pump();
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

    // 骨架出現播完（0.6 秒）後再停一個骨架呼吸（0.8 秒）才換場，書早就
    // 準備好了也一樣。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(
      LaunchEntranceMotion.pause - const Duration(milliseconds: 50),
    );
    expect(find.byType(SkeletonBox), findsWidgets, reason: '還在停頓，骨架照常呼吸');
    expect(crossfading(tester), isFalse);

    // 停完：收住呼吸，拍下骨架畫面、換成內容、拍下換好的畫面，之後只貼兩張
    // 圖；畫面先靜止至少 hold 才開始掃。
    await tester.pump(const Duration(milliseconds: 50));
    expect(await pumpUntilCrossfading(tester), lessThan(untilCrossfade));
    expect(find.text('內容'), findsOneWidget, reason: '底下已經換成內容');
    await tester.pump(LaunchEntranceMotion.hold);

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

  testWidgets('a screen size change mid-crossfade ends it and shows the real '
      'screen at once', (tester) async {
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(loading: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 620));
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(finished, 0, reason: '骨架出現播完、書還沒到');

    await tester.pumpWidget(host(loading: false));
    await tester.pumpAndSettle();
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
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
    await tester.pumpAndSettle();
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
}

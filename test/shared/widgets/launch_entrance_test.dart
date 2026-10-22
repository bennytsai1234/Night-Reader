import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
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
    bool waitForCovers = false,
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

  LaunchEntranceMotion motion(WidgetTester tester) =>
      LaunchEntrance.maybeOf(tester.element(find.byType(Scaffold).first))!;

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
    expect(motion(tester).revealStarted, isFalse);

    // 骨架出現播完（0.6 秒）才換場：拍下骨架畫面、換成內容、拍下換好的
    // 畫面，之後兩張圖混合。
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 4 && motion(tester).screen.progress == null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(motion(tester).screen.progress, 0, reason: '拍好兩張圖，從頭開始混合');
    expect(find.text('內容'), findsOneWidget, reason: '底下已經換成內容');
    expect(find.byType(SkeletonBox), findsNothing, reason: '骨架只在第一張圖裡');

    // 下一格開始計時、只貼兩張圖。
    await tester.pump(const Duration(milliseconds: 16));
    expect(motion(tester).screen.progress, 0);
    expect(paintedGlass(tester), 0, reason: '換場中只貼兩張圖，玻璃已經畫在圖裡');

    await tester.pump(SkeletonReveal.defaultDuration ~/ 2);
    expect(motion(tester).screen.progress, closeTo(0.5, 0.05));
    expect(paintedGlass(tester), 0);
    await tester.tap(find.byIcon(Icons.menu), warnIfMissed: false);
    expect(leftTaps, 0, reason: '換場中不接點擊');
    expect(finished, 0);

    await tester.pump(SkeletonReveal.defaultDuration ~/ 2);
    await tester.pump(const Duration(milliseconds: 16));
    expect(motion(tester).screen.progress, isNull, reason: '換回真的畫面');
    expect(paintedGlass(tester), greaterThan(0), reason: '玻璃照常畫');
    expectNoGlassUnderFade(tester);
    await tester.pump();
    expect(finished, 1, reason: '換場播完才開始背景工作');
    await tester.tap(find.byIcon(Icons.menu));
    expect(leftTaps, 1);
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
        host(loading: loading, waitForCovers: true);
    await tester.pumpWidget(at(loading: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    for (var i = 0; i < 6 && motion(tester).screen.progress == null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));
    expect(motion(tester).screen.progress, inExclusiveRange(0, 1));

    await tester.pumpWidget(at(loading: true));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(motion(tester).screen.progress, isNull, reason: '換回真的畫面');
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

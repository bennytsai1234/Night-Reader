import 'package:flutter/material.dart';
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

  /// 按鈕那塊玻璃的濃度（連同模糊一起淡入）。
  double glass(WidgetTester tester, IconData icon) => tester
      .widgetList<GlassReveal>(
        find.ancestor(
          of: find.byIcon(icon),
          matching: find.byType(GlassReveal),
        ),
      )
      .firstWhere((reveal) => reveal.animation != null)
      .animation!
      .value;

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

  /// 標題外面所有淡入淡出相乘的濃度（標題自己也有一層顯示與否的淡入）。
  double titleOpacity(WidgetTester tester) => tester
      .widgetList<FadeTransition>(
        find.ancestor(
          of: find.text('書架'),
          matching: find.byType(FadeTransition),
        ),
      )
      .fold(1.0, (opacity, fade) => opacity * fade.opacity.value);

  testWidgets('the first frame is only the background', (tester) async {
    await tester.pumpWidget(host(loading: true));
    expect(shelfSkeleton(tester).alphaAt(0), 0, reason: '和系統啟動畫面一樣只有底色');
    expect(buttonSkeleton(tester, Icons.menu), 0);
    expect(glass(tester, Icons.menu), 0);
    expect(titleOpacity(tester), 0);
  });

  testWidgets(
    'buttons grow in as skeletons with the shelf and turn into glass with it',
    (tester) async {
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
      expect(glass(tester, Icons.menu), 0, reason: '玻璃還沒出現');
      expect(titleOpacity(tester), 0, reason: '標題也先是骨架');
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

      // 骨架出現播完（0.6 秒）才換場；按鈕跟著書架一起換。
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('內容'), findsNothing);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 300));
      final left = glass(tester, Icons.menu);
      final right = glass(tester, Icons.add);
      expect(left, inExclusiveRange(0, 1));
      expect(left, greaterThan(right), reason: '和書架一樣由左而右');
      expectNoGlassUnderFade(tester);
      expect(
        glass(tester, Icons.search_rounded),
        inExclusiveRange(0, 1),
        reason: '分頁列與搜尋鈕跟著同一段換成玻璃',
      );
      expect(
        buttonSkeleton(tester, Icons.menu),
        lessThan(buttonSkeleton(tester, Icons.add)),
      );
      await tester.tap(find.byIcon(Icons.menu), warnIfMissed: false);
      expect(leftTaps, 0, reason: '玻璃換好之前不接點擊');

      // 骨架拿掉後不再呼吸，等得到靜止。
      await tester.pumpAndSettle();
      expect(glass(tester, Icons.menu), 1, reason: '最後一幀就是靜止的玻璃');
      expect(glass(tester, Icons.add), 1);
      expect(find.byType(SkeletonBox), findsNothing);
      expect(find.text('內容'), findsOneWidget);
      expect(titleOpacity(tester), 1);
      await tester.tap(find.byIcon(Icons.menu));
      expect(leftTaps, 1);
    },
  );

  testWidgets('says it finished only after the shelf has turned into content, '
      'once', (tester) async {
    await tester.pumpWidget(host(loading: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(finished, 0, reason: '骨架出現播完、書還沒到');

    await tester.pumpWidget(host(loading: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(finished, 0, reason: '書架換場播到一半，背景工作還不能開始');

    await tester.pumpAndSettle();
    expect(finished, 1);

    // 重新載入時骨架一直呼吸，用固定時間走完換回骨架。
    await tester.pumpWidget(host(loading: true));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(host(loading: false));
    await tester.pumpAndSettle();
    expect(finished, 1, reason: '之後重新載入書架不算');
  });

  testWidgets('reloading mid-reveal sends the buttons back with the shelf '
      'without rebuilding them during build', (tester) async {
    Widget at({required bool loading}) =>
        host(loading: loading, waitForCovers: true);
    await tester.pumpWidget(at(loading: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));
    expect(glass(tester, Icons.menu), inExclusiveRange(0, 1), reason: '換場中');

    // 第一次換場途中重新載入、又馬上載完（例如空書架再讀一次）。
    await tester.pumpWidget(at(loading: true));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(at(loading: false));
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(glass(tester, Icons.menu), 0, reason: '和書架的內容一起從頭等');

    await tester.pumpAndSettle();
    expect(glass(tester, Icons.menu), 1);
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
    expect(
      find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(GlassReveal),
      ),
      findsNothing,
    );
    expect(find.byType(SkeletonBox), findsNothing);
  });
}

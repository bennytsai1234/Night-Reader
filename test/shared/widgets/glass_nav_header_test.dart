import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';

void main() {
  late NavHeaderCollapse collapse;

  setUp(() => collapse = NavHeaderCollapse());
  tearDown(() => collapse.dispose());

  Widget page({bool sheen = false, bool disableAnimations = false}) {
    return MaterialApp(
      theme: buildAppTheme(AppStyle.paper, Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassNavHeader(
            title: '書架',
            largeTitle: true,
            collapse: collapse,
            titleSheen: sheen,
          ),
          body: NotificationListener<Notification>(
            onNotification: collapse.handle,
            child: ListView.builder(
              itemCount: 60,
              itemBuilder: (_, i) => SizedBox(height: 50, child: Text('列$i')),
            ),
          ),
        ),
      ),
    );
  }

  final backdrop = find.descendant(
    of: find.byType(GlassNavHeader),
    matching: find.byType(EdgeFade),
  );

  double smallTitleOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(NavHeaderTitle),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  testWidgets('the large title scrolls away and the small title fades in', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    // 頂端：大標題在工具列下方，小標題透明。
    expect(find.text('書架'), findsNWidgets(2));
    expect(smallTitleOpacity(tester), 0);
    final firstRowGap =
        tester.getTopLeft(find.text('列0')).dy -
        tester.getBottomLeft(backdrop).dy;

    // 捲一小段：頁首跟著收，第一列與頁首的相對位置不變（內容不跳動）。
    await tester.drag(find.text('列3'), const Offset(0, -20));
    await tester.pump();
    expect(collapse.value, closeTo(20, 0.5));
    expect(
      tester.getTopLeft(find.text('列0')).dy - tester.getBottomLeft(backdrop).dy,
      closeTo(firstRowGap, 0.5),
    );
    expect(smallTitleOpacity(tester), 0);

    // 捲過大標題的高度：收合完成，小標題淡入。
    await tester.drag(find.text('列5'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(collapse.value, AppGlass.largeTitleHeight);
    expect(smallTitleOpacity(tester), 1);

    // 回到頂端：大標題回來，小標題再藏起來。
    await tester.drag(find.text('列6'), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(collapse.value, 0);
    expect(smallTitleOpacity(tester), 0);
  });

  testWidgets('the header keeps its height while collapsing', (tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    final height = tester.getSize(find.byType(GlassNavHeader)).height;

    await tester.drag(find.text('列3'), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(GlassNavHeader)).height, height);
    expect(
      tester.getSize(backdrop).height,
      closeTo(height - AppGlass.largeTitleHeight, 0.5),
    );
  });

  testWidgets('the sheen finishes its sweep after checking ends', (
    tester,
  ) async {
    final sheenMask = find.descendant(
      of: find.byType(GlassNavHeader),
      matching: find.byType(ShaderMask),
    );

    await tester.pumpWidget(page(sheen: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(sheenMask, findsWidgets);

    // 一輪掃完會重新開始。
    await tester.pump(AppMotion.sheen);
    expect(sheenMask, findsWidgets);

    // 檢查結束：這一輪還在掃，掃完才停。
    await tester.pumpWidget(page());
    await tester.pump(const Duration(milliseconds: 100));
    expect(sheenMask, findsWidgets);
    await tester.pump(AppMotion.sheen);
    expect(sheenMask, findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('no sheen when the system turns animations off', (tester) async {
    await tester.pumpWidget(page(sheen: true, disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.descendant(
        of: find.byType(GlassNavHeader),
        matching: find.byType(ShaderMask),
      ),
      findsNothing,
    );
  });
}

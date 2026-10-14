import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';

void main() {
  Widget page(GlassNavHeader header, {bool disableAnimations = false}) {
    return MaterialApp(
      theme: buildAppTheme(AppStyle.paper, Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          padding: const EdgeInsets.only(top: 24),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: header,
          body: const SizedBox.expand(),
        ),
      ),
    );
  }

  final sheenMask = find.descendant(
    of: find.byType(GlassNavHeader),
    matching: find.byType(ShaderMask),
  );

  testWidgets('the title stays a single centred title', (tester) async {
    await tester.pumpWidget(page(const GlassNavHeader(title: '書架')));

    expect(find.text('書架'), findsOneWidget);
    expect(
      tester.getCenter(find.text('書架')).dx,
      closeTo(tester.getCenter(find.byType(GlassNavHeader)).dx, 0.5),
    );
  });

  testWidgets('a header with nothing in its toolbar keeps only the status '
      'bar and the fade', (tester) async {
    await tester.pumpWidget(
      page(const GlassNavHeader(automaticallyImplyLeading: false)),
    );

    expect(
      tester.getSize(find.byType(GlassNavHeader)).height,
      24 + AppGlass.headerFadeHeight,
    );
  });

  testWidgets('the sheen finishes its sweep after checking ends', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(const GlassNavHeader(title: '書架', titleSheen: true)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(sheenMask, findsOneWidget);

    // 一輪掃完會重新開始。
    await tester.pump(AppMotion.sheen);
    expect(sheenMask, findsOneWidget);

    // 檢查結束：這一輪還在掃，掃完才停。
    await tester.pumpWidget(page(const GlassNavHeader(title: '書架')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(sheenMask, findsOneWidget);
    await tester.pump(AppMotion.sheen);
    expect(sheenMask, findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('no sheen when the system turns animations off', (tester) async {
    await tester.pumpWidget(
      page(
        const GlassNavHeader(title: '書架', titleSheen: true),
        disableAnimations: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(sheenMask, findsNothing);
  });
}

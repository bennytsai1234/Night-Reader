import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

void main() {
  group('由左而右', () {
    double at(double progress, double u) =>
        SkeletonReveal.incomingOpacityAt(progress, u);

    test('the left edge starts first and both edges land together', () {
      expect(at(0, 0), 0);
      expect(at(0.25, 0), 0.5);
      expect(at(0.25, 1), 0, reason: '右緣到一半才開始');
      expect(at(0.5, 0), 1);
      expect(at(0.75, 1), 0.5);
      expect(at(1, 0), 1);
      expect(at(1, 1), 1, reason: '最後一幀整片都是內容');
    });

    test('a whole-page fade is the same everywhere', () {
      expect(SkeletonReveal.incomingOpacityAt(0.3, 0, sweep: false), 0.3);
      expect(SkeletonReveal.incomingOpacityAt(0.3, 1, sweep: false), 0.3);
    });

    test('the gradient stops follow the bends of the ramp', () {
      expect(SkeletonReveal.sweepStops(0.25), [
        (0.0, 0.5),
        (0.5, 0.0),
        (1.0, 0.0),
      ]);
      expect(SkeletonReveal.sweepStops(0.75), [
        (0.0, 1.0),
        (0.5, 1.0),
        (1.0, 0.5),
      ]);
      expect(SkeletonReveal.sweepStops(1), [(0.0, 1.0), (1.0, 1.0)]);
    });
  });

  group('SkeletonSwitcher', () {
    Widget host(SkeletonReveal reveal, {required bool loading}) => MaterialApp(
      theme: buildAppTheme(
        AppStyle.paper,
        Brightness.light,
        skeletonReveal: reveal,
      ),
      home: Scaffold(
        body: SkeletonSwitcher(
          loading: loading,
          skeleton: const SkeletonBox(width: 40, height: 40),
          builder: (_) => const Text('內容'),
        ),
      ),
    );

    RenderSkeletonRevealLayer contentLayer(WidgetTester tester) =>
        tester.renderObject(
          find
              .ancestor(
                of: find.text('內容'),
                matching: find.byType(SkeletonRevealLayer),
              )
              .first,
        );

    testWidgets('takes the chosen time to reveal', (tester) async {
      const reveal = SkeletonReveal(
        style: SkeletonRevealStyle.fade,
        duration: Duration(milliseconds: 1000),
      );
      await tester.pumpWidget(host(reveal, loading: true));
      await tester.pumpWidget(host(reveal, loading: false));
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byType(SkeletonBox), findsOneWidget, reason: '還在換場');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(SkeletonBox), findsNothing);
    });

    RenderSkeletonRevealLayer skeletonLayer(WidgetTester tester) =>
        tester.renderObject(
          find
              .ancestor(
                of: find.byType(SkeletonBox),
                matching: find.byType(SkeletonRevealLayer),
              )
              .first,
        );

    testWidgets('reloading grows the skeleton back from the left', (
      tester,
    ) async {
      const reveal = SkeletonReveal(duration: Duration(milliseconds: 1000));
      await tester.pumpWidget(host(reveal, loading: true));
      await tester.pumpWidget(host(reveal, loading: false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(reveal, loading: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final skeleton = skeletonLayer(tester);
      expect(skeleton.alphaAt(0), greaterThan(skeleton.alphaAt(1)));
      expect(
        contentLayer(tester).alphaAt(1),
        greaterThan(contentLayer(tester).alphaAt(0)),
        reason: '內容在右邊留得最久',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('內容'), findsOneWidget, reason: '照選的時長，還沒換完');
      // 骨架會一直呼吸，等不到 pumpAndSettle。
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('內容'), findsNothing);
    });

    testWidgets('content waits for the skeleton entrance to finish', (
      tester,
    ) async {
      final entrance = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 500),
      );
      addTearDown(entrance.dispose);
      Widget entering({required bool loading}) => MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          body: SkeletonSwitcher(
            loading: loading,
            entrance: entrance,
            skeleton: const SkeletonBox(width: 40, height: 40),
            builder: (_) => const Text('內容'),
          ),
        ),
      );
      await tester.pumpWidget(entering(loading: true));
      expect(skeletonLayer(tester).alphaAt(0), 0, reason: '第一幀只有底色');
      unawaited(entrance.forward());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final growing = skeletonLayer(tester);
      expect(growing.alphaAt(0), greaterThan(growing.alphaAt(1)));

      await tester.pumpWidget(entering(loading: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('內容'), findsNothing, reason: '骨架還在進場，先不建內容');

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('內容'), findsOneWidget);
      expect(find.byType(SkeletonBox), findsNothing);
    });

    testWidgets('the sweep masks the content only while it is moving', (
      tester,
    ) async {
      const reveal = SkeletonReveal();
      await tester.pumpWidget(host(reveal, loading: true));
      await tester.pumpWidget(host(reveal, loading: false));
      await tester.pump(reveal.duration ~/ 2);
      expect(contentLayer(tester).alwaysNeedsCompositing, isTrue);

      await tester.pumpAndSettle();
      expect(
        contentLayer(tester).alwaysNeedsCompositing,
        isFalse,
        reason: '換場結束後直接畫，不留一層遮罩',
      );
    });
  });
}

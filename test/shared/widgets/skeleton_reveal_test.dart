import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

import '../../support/theme_with.dart';

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
      theme: themeWith(AppStyle.paper, Brightness.light, [reveal]),
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

    testWidgets('with a backdrop only the skeleton is masked, on top', (
      tester,
    ) async {
      var taps = 0;
      Widget backed({required bool loading}) => MaterialApp(
        home: Scaffold(
          body: SkeletonSwitcher(
            loading: loading,
            backdrop: const Color(0xFFE5E1D9),
            skeleton: const SkeletonBox(width: 40, height: 40),
            builder: (_) =>
                GestureDetector(onTap: () => taps++, child: const Text('內容')),
          ),
        ),
      );
      await tester.pumpWidget(backed(loading: true));
      await tester.pumpWidget(backed(loading: false));
      await tester.pump(const SkeletonReveal().duration ~/ 2);

      // 內容照常畫、不開圖層；骨架墊著底色蓋在上面，由左而右退開。
      expect(contentLayer(tester).alwaysNeedsCompositing, isFalse);
      final skeleton = skeletonLayer(tester);
      expect(skeleton.alwaysNeedsCompositing, isTrue);
      expect(skeleton.alphaAt(0), lessThan(skeleton.alphaAt(1)));
      final stack = tester.widget<Stack>(
        find
            .ancestor(
              of: find.byType(SkeletonBox),
              matching: find.byType(Stack),
            )
            .first,
      );
      expect((stack.children.last.key! as ValueKey<String>).value, 'skeleton');

      // 蓋在上面的骨架不擋點擊。
      await tester.tap(find.text('內容'), warnIfMissed: false);
      expect(taps, 1);

      await tester.pump(const SkeletonReveal().duration);
      expect(find.byType(SkeletonBox), findsNothing);
    });
  });

  group('SliverSkeletonSwitcher', () {
    Widget host(SkeletonReveal reveal, {required bool loading}) => MaterialApp(
      theme: themeWith(AppStyle.paper, Brightness.light, [reveal]),
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
            SliverSkeletonSwitcher(
              loading: loading,
              skeleton: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 20),
                  SkeletonBox(key: Key('bar'), width: 80, height: 20),
                ],
              ),
              builder: (_) => [
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
                const SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      key: Key('row'),
                      width: 80,
                      height: 20,
                      child: Text('內容'),
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: 60,
                  itemBuilder: (_, i) =>
                      SizedBox(height: 40, child: Text('$i')),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    /// 骨架那一層的濃度（內容那一層是 1 減它）。
    double skeletonOpacity(WidgetTester tester) => tester
        .widget<SkeletonRevealLayer>(
          find
              .ancestor(
                of: find.byKey(const Key('bar')),
                matching: find.byType(SkeletonRevealLayer),
              )
              .first,
        )
        .opacity
        .value;

    int fadeLayers(WidgetTester tester) =>
        tester.layers.whereType<OpacityLayer>().length;

    testWidgets('the skeleton stays on top of the laid-out content, then '
        'fades into it', (tester) async {
      const reveal = SkeletonReveal(style: SkeletonRevealStyle.fade);
      await tester.pumpWidget(host(reveal, loading: true));
      final skeletonBar = tester.getRect(find.byKey(const Key('bar')));
      expect(find.text('內容'), findsNothing);

      await tester.pumpWidget(host(reveal, loading: false));
      // 內容排好、骨架還整個蓋著，兩者在同一個位置。
      expect(find.byKey(const Key('bar')), findsOneWidget);
      expect(tester.getRect(find.byKey(const Key('row'))), skeletonBar);
      expect(tester.getRect(find.byKey(const Key('bar'))), skeletonBar);
      expect(skeletonOpacity(tester), 1);
      expect(fadeLayers(tester), 0, reason: '內容全透明時不畫');

      await tester.pump();
      await tester.pump(reveal.duration ~/ 2);
      expect(skeletonOpacity(tester), inExclusiveRange(0, 1));
      expect(fadeLayers(tester), 2, reason: '內容淡入、骨架淡出');
      // 換場中捲動：骨架跟著內容走。
      tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .jumpTo(30);
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const Key('bar'))),
        tester.getRect(find.byKey(const Key('row'))),
      );

      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bar')), findsNothing);
      expect(fadeLayers(tester), 0, reason: '換場結束後直接畫，不留圖層');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the content is tappable only through itself', (tester) async {
      const reveal = SkeletonReveal();
      await tester.pumpWidget(host(reveal, loading: true));
      await tester.pumpWidget(host(reveal, loading: false));
      await tester.pump();
      await tester.pump(reveal.duration ~/ 2);
      // 疊在上面的骨架不攔點擊：點中的是內容那一列。
      final hit = tester.hitTestOnBinding(
        tester.getCenter(find.byKey(const Key('row'))),
      );
      expect(
        hit.path.any(
          (entry) =>
              entry.target == tester.renderObject(find.byKey(const Key('row'))),
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
    });
  });
}

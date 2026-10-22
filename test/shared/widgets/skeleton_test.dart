import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';
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
        waitForCovers: true,
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

    testWidgets('a cover that never decodes stops holding the page', (
      tester,
    ) async {
      await tester.pumpWidget(switcher(true));
      await tester.pumpWidget(switcher(false));
      await tester.pump();
      await tester.pump(AppMotion.revealCoverWait);
      await tester.pump();
      await tester.pump(SkeletonReveal.defaultDuration ~/ 2);
      expect(contentOpacity(tester), inExclusiveRange(0, 1));
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
}

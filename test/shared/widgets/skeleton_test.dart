import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/cover_reveal.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  testWidgets(
    'placeholders are visible but faint in every style and brightness',
    (tester) async {
      for (final style in AppStyle.values) {
        for (final brightness in Brightness.values) {
          late Color skeleton;
          late AppChrome chrome;
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(style, brightness),
              home: Builder(
                builder: (context) {
                  skeleton = Skeleton.colorOf(context);
                  chrome = AppChrome.of(context);
                  return const SizedBox();
                },
              ),
            ),
          );
          for (final background in [
            chrome.groupedBackground,
            chrome.groupedSurface,
          ]) {
            final shown = Color.alphaBlend(skeleton, background);
            expect(
              _contrast(shown, background),
              inInclusiveRange(1.06, 1.4),
              reason: '${style.name} ${brightness.name}',
            );
          }
        }
      }
    },
  );

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
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.text('內容'),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
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
      await tester.pump(AppMotion.reveal ~/ 2);
      expect(contentOpacity(tester), inExclusiveRange(0, 1));
      expect(find.byType(SkeletonBox), findsOneWidget);

      await tester.pumpAndSettle();
      expect(contentOpacity(tester), 1);
      expect(find.byType(SkeletonBox), findsNothing);
    });

    testWidgets('a cover that never decodes stops holding the page', (
      tester,
    ) async {
      await tester.pumpWidget(switcher(true));
      await tester.pumpWidget(switcher(false));
      await tester.pump();
      await tester.pump(AppMotion.revealCoverWait);
      await tester.pump();
      await tester.pump(AppMotion.reveal ~/ 2);
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

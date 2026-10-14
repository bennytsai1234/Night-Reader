import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/loading_veil.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

void main() {
  final spec = ReaderV2LayoutSpec(
    viewportSize: const Size(400, 800),
    contentWidth: 360,
    contentHeight: 800,
    style: const ReaderV2LayoutStyle(
      fontSize: 18,
      lineHeight: 1.6,
      letterSpacing: 0,
      paragraphSpacing: 0.5,
      paddingTop: 0,
      paddingBottom: 0,
      paddingLeft: 20,
      paddingRight: 20,
      textIndent: 2,
    ),
  );
  const frame = Duration(milliseconds: 16);
  final noSkeleton = paintsExactlyCountTimes(#drawRRect, 0);

  late LoadingVeilController veil;
  late int hiddenCount;

  void makeVeil(WidgetTester tester, {bool reduceMotion = false}) {
    hiddenCount = 0;
    veil = LoadingVeilController(vsync: tester, onHidden: () => hiddenCount++)
      ..reduceMotion = reduceMotion
      ..cover();
  }

  Future<void> pumpVeil(WidgetTester tester, {bool mounted = true}) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: mounted
            ? LoadingVeil(
                controller: veil,
                spec: spec,
                backgroundColor: const Color(0xFFF6F1E7),
                textColor: const Color(0xFF2B2622),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  /// 一幀一幀推進：動畫從開始後的第一幀才起算。
  Future<void> advance(WidgetTester tester, Duration duration) async {
    for (var elapsed = Duration.zero; elapsed < duration; elapsed += frame) {
      await tester.pump(frame);
    }
  }

  Future<void> finish(WidgetTester tester) async {
    await pumpVeil(tester, mounted: false);
    veil.dispose();
  }

  testWidgets('plain paper until the skeleton delay, then text-shaped lines', (
    tester,
  ) async {
    makeVeil(tester);
    await pumpVeil(tester);
    expect(find.byType(LoadingVeil), paints..rect());
    expect(find.byType(LoadingVeil), noSkeleton);

    await tester.pump(AppMotion.readerSkeletonDelay - frame);
    expect(find.byType(LoadingVeil), noSkeleton, reason: '排得快的書不閃骨架');

    await advance(tester, frame + AppMotion.fade);
    expect(
      find.byType(LoadingVeil),
      paints
        ..rect()
        ..rrect()
        ..rrect(),
    );
    expect(tester.hasRunningAnimations, isTrue, reason: '骨架在呼吸');
    await finish(tester);
  });

  testWidgets('reveal fades the paper out and stops every animation', (
    tester,
  ) async {
    makeVeil(tester);
    await pumpVeil(tester);
    await advance(tester, AppMotion.readerSkeletonDelay + AppMotion.fade);

    veil.reveal();
    await advance(tester, AppMotion.fade ~/ 2);
    expect(veil.isVisible, isTrue);
    expect(hiddenCount, 0);

    await advance(tester, AppMotion.fade);
    expect(veil.isVisible, isFalse);
    expect(hiddenCount, 1);
    expect(tester.hasRunningAnimations, isFalse);
    await finish(tester);
  });

  testWidgets('a quick load never shows the skeleton', (tester) async {
    makeVeil(tester);
    await pumpVeil(tester);
    await advance(tester, const Duration(milliseconds: 200));
    veil.reveal();
    await advance(tester, AppMotion.fade ~/ 2);
    expect(find.byType(LoadingVeil), noSkeleton);

    await advance(tester, AppMotion.readerSkeletonDelay);
    expect(veil.isVisible, isFalse);
    expect(tester.hasRunningAnimations, isFalse);
    await finish(tester);
  });

  testWidgets('covering again restarts the skeleton delay', (tester) async {
    makeVeil(tester);
    await pumpVeil(tester);
    await advance(tester, AppMotion.readerSkeletonDelay + AppMotion.fade);
    veil.reveal();
    await advance(tester, AppMotion.fade * 2);

    veil.cover();
    await tester.pump();
    expect(veil.isVisible, isTrue);
    expect(find.byType(LoadingVeil), noSkeleton);
    await finish(tester);
  });

  testWidgets('the skeleton only breathes while a veil is on screen', (
    tester,
  ) async {
    makeVeil(tester);
    await pumpVeil(tester, mounted: false);
    await advance(tester, AppMotion.readerSkeletonDelay + AppMotion.fade * 2);
    expect(tester.hasRunningAnimations, isFalse);

    await pumpVeil(tester);
    expect(tester.hasRunningAnimations, isTrue);
    await finish(tester);
  });

  testWidgets('with animations disabled everything lands at once', (
    tester,
  ) async {
    makeVeil(tester, reduceMotion: true);
    await pumpVeil(tester);
    await tester.pump(AppMotion.readerSkeletonDelay);
    expect(find.byType(LoadingVeil), paints..rrect());
    expect(tester.hasRunningAnimations, isFalse);

    veil.reveal();
    expect(veil.isVisible, isFalse);
    expect(hiddenCount, 1);
    await finish(tester);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/loading_veil.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

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
  // 骨架出現與掀紙都照骨架換場的預設時長。
  const revealTime = SkeletonReveal.defaultDuration;
  final noSkeleton = paintsExactlyCountTimes(#drawRRect, 0);

  // 一頁的兩行正文。
  const twoLines = [
    Rect.fromLTRB(56, 10, 380, 28),
    Rect.fromLTRB(20, 39, 210, 57),
  ];

  late LoadingVeilController veil;
  late int hiddenCount;

  void makeVeil(
    WidgetTester tester, {
    bool reduceMotion = false,
    bool skeleton = true,
  }) {
    hiddenCount = 0;
    veil = LoadingVeilController(vsync: tester, onHidden: () => hiddenCount++)
      ..reduceMotion = reduceMotion
      ..cover(skeleton: skeleton);
  }

  Future<void> pumpVeil(
    WidgetTester tester, {
    bool mounted = true,
    List<Rect>? lines = twoLines,
    Set<int> titleLines = const <int>{},
  }) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: mounted
            ? LoadingVeil(
                controller: veil,
                spec: spec,
                lines: lines,
                titleLines: titleLines,
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

  testWidgets('covering fades text-shaped lines in on the paper right away', (
    tester,
  ) async {
    makeVeil(tester);
    await pumpVeil(tester);
    expect(find.byType(LoadingVeil), paints..rect());

    await advance(tester, revealTime);
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
    await advance(tester, revealTime);

    veil.reveal();
    await advance(tester, revealTime ~/ 2);
    expect(veil.isVisible, isTrue);
    expect(hiddenCount, 0);

    await advance(tester, revealTime);
    expect(veil.isVisible, isFalse);
    expect(hiddenCount, 1);
    expect(tester.hasRunningAnimations, isFalse);
    await finish(tester);
  });

  testWidgets('a quick load fades the skeleton out with the paper', (
    tester,
  ) async {
    makeVeil(tester);
    await pumpVeil(tester);
    await advance(tester, revealTime ~/ 2);
    veil.reveal();
    await advance(tester, revealTime * 2);
    expect(veil.isVisible, isFalse);
    expect(find.byType(LoadingVeil), noSkeleton);
    expect(tester.hasRunningAnimations, isFalse);
    await finish(tester);
  });

  testWidgets('covering again mid-fade keeps the skeleton on the paper', (
    tester,
  ) async {
    makeVeil(tester);
    await pumpVeil(tester);
    await advance(tester, revealTime);
    veil.reveal();
    await advance(tester, revealTime ~/ 2);

    veil.cover();
    await tester.pump();
    expect(veil.isVisible, isTrue);
    expect(find.byType(LoadingVeil), paints..rrect(), reason: '不先閃空再淡入');
    await finish(tester);
  });

  testWidgets('the skeleton only breathes while a veil is on screen', (
    tester,
  ) async {
    makeVeil(tester);
    await pumpVeil(tester, mounted: false);
    await advance(tester, revealTime * 2);
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
    expect(find.byType(LoadingVeil), paints..rrect());
    expect(tester.hasRunningAnimations, isFalse);

    veil.reveal();
    expect(veil.isVisible, isFalse);
    expect(hiddenCount, 1);
    await finish(tester);
  });

  testWidgets('turning animations off mid-fade lands the skeleton at once', (
    tester,
  ) async {
    makeVeil(tester);
    await pumpVeil(tester);
    await advance(tester, revealTime ~/ 2);
    expect(tester.hasRunningAnimations, isTrue);

    veil.reduceMotion = true;
    await tester.pump();
    expect(find.byType(LoadingVeil), paints..rrect());
    expect(tester.hasRunningAnimations, isFalse);
    await finish(tester);
  });

  testWidgets('turning animations off mid-reveal hides the paper at once', (
    tester,
  ) async {
    makeVeil(tester);
    await pumpVeil(tester);
    await advance(tester, revealTime);
    veil.reveal();
    await advance(tester, revealTime ~/ 2);
    expect(veil.isVisible, isTrue);

    veil.reduceMotion = true;
    expect(veil.isVisible, isFalse);
    expect(hiddenCount, 1);
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    await finish(tester);
  });

  testWidgets('each line is drawn where its text is, titles scaled up', (
    tester,
  ) async {
    makeVeil(tester);
    // 一行章名、兩行正文。
    await pumpVeil(
      tester,
      lines: const [
        Rect.fromLTRB(20, 10, 300, 40),
        Rect.fromLTRB(56, 60, 380, 78),
        Rect.fromLTRB(20, 90, 200, 108),
      ],
      titleLines: const {0},
    );
    await advance(tester, revealTime);
    // 正文的長條是字級的 0.75（18 → 13.5），章名照章名與正文的字級比放大。
    final title = 13.5 * spec.style.titleFontSize / spec.style.fontSize / 2;
    final radius = AppRadius.cardXs.topLeft;
    expect(
      find.byType(LoadingVeil),
      paints
        ..rect()
        ..rrect(rrect: RRect.fromLTRBR(20, 25 - title, 300, 25 + title, radius))
        ..rrect(rrect: RRect.fromLTRBR(56, 69 - 6.75, 380, 69 + 6.75, radius))
        ..rrect(rrect: RRect.fromLTRBR(20, 99 - 6.75, 200, 99 + 6.75, radius)),
    );
    expect(find.byType(LoadingVeil), paintsExactlyCountTimes(#drawRRect, 3));
    await finish(tester);
  });

  testWidgets('a title with a single line under it is still scaled up', (
    tester,
  ) async {
    makeVeil(tester);
    await pumpVeil(
      tester,
      lines: const [
        Rect.fromLTRB(20, 10, 300, 40),
        Rect.fromLTRB(20, 60, 200, 78),
      ],
      titleLines: const {0},
    );
    await advance(tester, revealTime);
    final title = 13.5 * spec.style.titleFontSize / spec.style.fontSize / 2;
    final radius = AppRadius.cardXs.topLeft;
    expect(
      find.byType(LoadingVeil),
      paints
        ..rect()
        ..rrect(rrect: RRect.fromLTRBR(20, 25 - title, 300, 25 + title, radius))
        ..rrect(rrect: RRect.fromLTRBR(20, 69 - 6.75, 200, 69 + 6.75, radius)),
    );
    await finish(tester);
  });

  testWidgets('without lines the paper stays plain', (tester) async {
    makeVeil(tester);
    await pumpVeil(tester, lines: null);
    await advance(tester, revealTime);
    expect(find.byType(LoadingVeil), paints..rect());
    expect(find.byType(LoadingVeil), noSkeleton);
    await finish(tester);
  });

  testWidgets('a paper covered without skeleton fades it in on request', (
    tester,
  ) async {
    makeVeil(tester, skeleton: false);
    await pumpVeil(tester);
    await advance(tester, revealTime);
    expect(find.byType(LoadingVeil), paints..rect());
    expect(find.byType(LoadingVeil), noSkeleton, reason: '第一頁排好前中間空著');
    expect(veil.isSkeletonFading, isFalse);

    veil.showSkeleton();
    await tester.pump(frame);
    expect(veil.isSkeletonFading, isTrue);
    await advance(tester, revealTime);
    expect(veil.isSkeletonFading, isFalse);
    expect(
      find.byType(LoadingVeil),
      paints
        ..rect()
        ..rrect()
        ..rrect(),
    );
    await finish(tester);
  });

  testWidgets('covering without skeleton fades the drawn skeleton out', (
    tester,
  ) async {
    makeVeil(tester);
    await pumpVeil(tester);
    await advance(tester, revealTime);

    veil.cover(skeleton: false);
    await tester.pump(frame);
    expect(veil.isSkeletonFading, isTrue);
    expect(
      find.byType(LoadingVeil),
      paints
        ..rect()
        ..rrect(),
      reason: '不突然消失',
    );
    await advance(tester, revealTime);
    expect(find.byType(LoadingVeil), noSkeleton);
    expect(veil.isVisible, isTrue, reason: '紙留著');
    await finish(tester);
  });
}

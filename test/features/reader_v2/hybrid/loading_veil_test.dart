import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/hybrid/overlay/loading_veil.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
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
  final veilKey = GlobalKey();

  /// 紙這一幀畫出來的像素（RGBA）。
  Future<Uint8List> pixels(WidgetTester tester) async {
    final boundary =
        veilKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData();
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

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
            ? RepaintBoundary(
                key: veilKey,
                child: LoadingVeil(
                  controller: veil,
                  spec: spec,
                  lines: lines,
                  titleLines: titleLines,
                  backgroundColor: const Color(0xFFF6F1E7),
                  textColor: const Color(0xFF2B2622),
                ),
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
    expect(tester.hasRunningAnimations, isFalse, reason: '長完先停在最深');
    await advance(tester, LoadingVeilController.restBeforeBreath + frame);
    expect(tester.hasRunningAnimations, isTrue, reason: '正文還沒好，開始呼吸');
    await finish(tester);
  });

  testWidgets('the paper also covers the gaps above and below the text area', (
    tester,
  ) async {
    // 跨在上下緣的那一行畫進正文與頁首頁尾之間的空隙；紙沒蓋到的話，那
    // 半行在掀紙前就露出來。
    makeVeil(tester);
    await pumpVeil(tester);
    expect(
      find.byType(LoadingVeil),
      paints..rect(rect: const Rect.fromLTRB(0, -600, 800, 1200)),
    );
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

  testWidgets('settling the breath finishes it at the deepest, covering '
      'again breathes on', (tester) async {
    makeVeil(tester);
    await pumpVeil(tester);
    await advance(tester, revealTime);
    expect(tester.hasRunningAnimations, isFalse, reason: '長完先停在最深');
    final deepest = await pixels(tester);
    await advance(
      tester,
      LoadingVeilController.restBeforeBreath +
          const Duration(milliseconds: 300),
    );
    expect(tester.hasRunningAnimations, isTrue, reason: '正文還沒好，開始呼吸');

    // 正文排好：這一口呼完、每個位置停在最深才完成，不凍在當下的深淺。
    var settled = false;
    unawaited(veil.settleBreath().then((_) => settled = true));
    await tester.pump(frame);
    expect(settled, isFalse, reason: '呼吸還在走完這一口');
    expect(tester.hasRunningAnimations, isTrue);
    // 骨架長完才從最深起步：第一口的右緣晚半輪，收住最多一輪半。
    await advance(tester, Skeleton.breathCycle * 1.5);
    expect(settled, isTrue);
    expect(tester.hasRunningAnimations, isFalse, reason: '收住後畫面靜止');
    expect(await pixels(tester), deepest, reason: '整片停在最深，和長完時一樣');

    // 這次掀紙作廢、又蓋上紙：停一下，正文還沒好就從最深接著呼吸。
    veil.cover();
    await tester.pump(frame);
    expect(tester.hasRunningAnimations, isFalse);
    await advance(tester, LoadingVeilController.restBeforeBreath);
    expect(tester.hasRunningAnimations, isTrue);
    await finish(tester);
  });

  testWidgets('the skeleton waits at the deepest while it grows and does not '
      'breathe when the text is ready by then', (tester) async {
    makeVeil(tester);
    await pumpVeil(tester);
    await tester.pump(frame);
    expect(veil.isSkeletonFading, isTrue, reason: '骨架在長出');

    // 長出途中正文就排好了：長完停在最深，不開始呼吸。
    var settled = false;
    unawaited(veil.settleBreath().then((_) => settled = true));
    await tester.pump(frame);
    expect(settled, isFalse, reason: '等骨架長完');
    await advance(tester, revealTime);
    expect(settled, isTrue);
    expect(tester.hasRunningAnimations, isFalse, reason: '沒有呼吸');
    await finish(tester);
  });

  testWidgets('the last frame of growing in is the still skeleton', (
    tester,
  ) async {
    // 長出、靜止、收住、掀紙起步都用同一種畫法：換畫法時顏色進位不同，
    // 銜接那一幀整片差 1 階（ADR 0022）。
    makeVeil(tester);
    await pumpVeil(tester);
    await advance(tester, revealTime - frame);
    expect(veil.isSkeletonFading, isTrue, reason: '還差最後一幀');
    final last = await pixels(tester);
    await tester.pump(frame);
    expect(veil.isSkeletonFading, isFalse);
    final still = await pixels(tester);
    // 最後一幀時左半已經完全長出，比到這裡。
    const rowBytes = 400 * 4;
    var compared = 0;
    for (var y = 10; y < 28; y++) {
      for (var x = 60; x < 200; x++) {
        final i = y * rowBytes + x * 4;
        for (var c = 0; c < 4; c++) {
          expect(last[i + c], still[i + c], reason: '($x, $y) 第 $c 個通道');
        }
        compared++;
      }
    }
    expect(compared, greaterThan(0));
    await finish(tester);
  });

  testWidgets('a new skeleton after a breathing one grows in still', (
    tester,
  ) async {
    makeVeil(tester);
    await pumpVeil(tester);
    await advance(tester, revealTime + LoadingVeilController.restBeforeBreath);
    await advance(tester, const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue, reason: '正文還沒好，在呼吸');

    // 呼吸中又跳章：舊骨架淡掉的同時把這一口呼完。
    veil.cover(skeleton: false);
    await advance(tester, Skeleton.breathCycle * 1.5);
    expect(tester.hasRunningAnimations, isFalse, reason: '淡完也收住了');

    // 新骨架長出時不呼吸，長完在 restBeforeBreath 內排好就直接收住。
    veil.showSkeleton();
    await tester.pump();
    await advance(tester, revealTime);
    expect(veil.isSkeletonFading, isFalse);
    expect(tester.hasRunningAnimations, isFalse, reason: '長完停在最深');
    var settled = false;
    unawaited(veil.settleBreath().then((_) => settled = true));
    await tester.pump(frame);
    expect(settled, isTrue, reason: '不多等一口呼吸');
    await finish(tester);
  });

  testWidgets('disposing while the skeleton grows ends the wait and asks '
      'for no more frames', (tester) async {
    makeVeil(tester);
    await pumpVeil(tester);
    await tester.pump(frame);
    var settled = false;
    unawaited(veil.settleBreath().then((_) => settled = true));
    await tester.pump(frame);
    expect(settled, isFalse, reason: '等骨架長完');

    await finish(tester);
    await tester.pump(frame);
    expect(settled, isTrue, reason: '拆掉時等待結束');
    expect(tester.binding.hasScheduledFrame, isFalse, reason: '不再要畫面');
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

  group('fading the paper in over the old text', () {
    const paper = Color(0xFFF6F1E7);

    /// 紙掀掉之後，正文在畫面上。
    Future<void> revealed(WidgetTester tester) async {
      makeVeil(tester);
      await pumpVeil(tester);
      veil.reveal();
      await advance(tester, revealTime * 2);
      expect(veil.isVisible, isFalse);
    }

    testWidgets('the paper fades in evenly and then covers fully', (
      tester,
    ) async {
      await revealed(tester);
      var covered = false;
      veil.cover(skeleton: false, fade: true);
      unawaited(veil.covered.then((value) => covered = value));
      await tester.pump();
      await advance(tester, AppMotion.fade ~/ 2);
      expect(veil.isVisible, isTrue);
      expect(veil.isCovered, isFalse);
      expect(covered, isFalse);
      // 半途的紙是半透明的整片，不是由左而右的漸層。
      expect(find.byType(LoadingVeil), isNot(paints..rect(color: paper)));
      expect(find.byType(LoadingVeil), paints..rect());
      expect(find.byType(LoadingVeil), noSkeleton);

      await advance(tester, AppMotion.fade);
      expect(veil.isCovered, isTrue);
      expect(covered, isTrue);
      expect(find.byType(LoadingVeil), paints..rect(color: paper));
      await finish(tester);
    });

    testWidgets('with animations disabled the paper covers at once', (
      tester,
    ) async {
      await revealed(tester);
      veil.reduceMotion = true;
      veil.cover(skeleton: false, fade: true);
      expect(veil.isCovered, isTrue);
      await veil.covered;
      await finish(tester);
    });

    testWidgets('disposing mid-fade ends every wait on the paper', (
      tester,
    ) async {
      await revealed(tester);
      veil.cover(skeleton: false, fade: true);
      final results = <bool>[];
      unawaited(veil.covered.then(results.add));
      await tester.pump();
      await advance(tester, AppMotion.fade ~/ 2);
      unawaited(veil.covered.then(results.add));

      await pumpVeil(tester, mounted: false);
      veil.dispose();
      await tester.pump();
      expect(results, [false, false], reason: '拆掉不算蓋滿，但每個等待都結束');
    });

    testWidgets('lifting the paper mid-fade ends the wait as not covered', (
      tester,
    ) async {
      await revealed(tester);
      veil.cover(skeleton: false, fade: true);
      bool? covered;
      unawaited(veil.covered.then((value) => covered = value));
      await tester.pump();
      await advance(tester, AppMotion.fade ~/ 2);

      veil.reveal();
      await tester.pump();
      expect(covered, isFalse, reason: '一改成掀開就結束，不等淡出完');
      expect(veil.isRevealing, isTrue);
      await advance(tester, revealTime * 2);
      await finish(tester);
    });

    testWidgets('turning animations off mid-fade covers at once', (
      tester,
    ) async {
      await revealed(tester);
      veil.cover(skeleton: false, fade: true);
      await tester.pump();
      await advance(tester, AppMotion.fade ~/ 2);
      veil.reduceMotion = true;
      expect(veil.isCovered, isTrue);
      await finish(tester);
    });
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
    // 正文的長條和字一樣高（18），章名照章名與正文的字級比放大。
    final title = 18 * spec.style.titleFontSize / spec.style.fontSize / 2;
    final radius = AppRadius.cardXs.topLeft;
    expect(
      find.byType(LoadingVeil),
      paints
        ..rect()
        ..rrect(rrect: RRect.fromLTRBR(20, 25 - title, 300, 25 + title, radius))
        ..rrect(rrect: RRect.fromLTRBR(56, 69 - 9, 380, 69 + 9, radius))
        ..rrect(rrect: RRect.fromLTRBR(20, 99 - 9, 200, 99 + 9, radius)),
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
    final title = 18 * spec.style.titleFontSize / spec.style.fontSize / 2;
    final radius = AppRadius.cardXs.topLeft;
    expect(
      find.byType(LoadingVeil),
      paints
        ..rect()
        ..rrect(rrect: RRect.fromLTRBR(20, 25 - title, 300, 25 + title, radius))
        ..rrect(rrect: RRect.fromLTRBR(20, 69 - 9, 200, 69 + 9, radius)),
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

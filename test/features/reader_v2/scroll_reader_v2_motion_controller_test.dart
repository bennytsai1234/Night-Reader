import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/viewport/scroll_reader_v2_motion_controller.dart';

class _FakeRuntime extends Fake implements ReaderV2Runtime {
  @override
  void beginInteractivePreloadPause() {}

  @override
  void endInteractivePreloadPause() {}

  @override
  Future<void> preloadDirectionalForVelocity({
    required int chapterIndex,
    required bool forward,
    required double velocity,
  }) async {}
}

void main() {
  ScrollReaderV2MotionController createController(
    WidgetTester tester, {
    Future<void> Function()? handleScrollSettled,
  }) {
    return ScrollReaderV2MotionController(
      vsync: tester,
      runtime: _FakeRuntime(),
      isMounted: () => true,
      hasVisiblePages: () => true,
      viewportHeight: () => 600,
      scrollBounds: () => (min: 0.0, max: 10000.0),
      shiftThreshold: () => 900,
      isArtificialScrollBoundaryForTarget: (_, _) => false,
      isNearArtificialWindowEdge:
          ({
            required bool forward,
            required double threshold,
            required double readingY,
          }) => false,
      isAtBookBoundaryForDelta: (_, _) => false,
      anchorChapterIndex: (_) => 0,
      updateWindowBoostForFling: (_) {},
      scheduleVisibleLocationCapture: () {},
      scheduleWindowShiftForAnchor: () {},
      requestShiftWindowForAnchor: () async {},
      handleScrollSettled: handleScrollSettled ?? () async {},
    );
  }

  testWidgets(
    'active fling rebase keeps deceleration from chasing stale value',
    (tester) async {
      final controller = createController(tester);
      try {
        controller.setReadingY(500);
        controller.startFling(1800);
        expect(controller.isFlingAnimating, isTrue);

        final staleAnimationValue = controller.scrollAnimation.value;
        controller.setReadingY(staleAnimationValue - 80);
        final visualReadingY = controller.readingY;

        expect(
          controller.scrollAnimation.value - visualReadingY,
          greaterThan(60),
          reason: '測試前提：動畫值已經跑在實際畫面位置前方',
        );

        controller.rebaseActiveFlingToCurrentReadingY();

        expect(controller.scrollAnimation.value, closeTo(visualReadingY, 0.01));
        expect(controller.isFlingAnimating, isTrue);
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        expect(
          controller.readingY,
          greaterThan(visualReadingY),
          reason: 'rebase 後仍需保留當下速度繼續減速',
        );
        expect(
          controller.readingY,
          lessThan(staleAnimationValue),
          reason: 'rebase 後下一幀不得追套等待期間累積的舊動畫位移',
        );
      } finally {
        controller.dispose();
      }
    },
  );
}

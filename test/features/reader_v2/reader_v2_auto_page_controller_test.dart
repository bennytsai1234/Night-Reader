import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/auto_page/reader_v2_auto_page_controller.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/viewport/reader_v2_viewport_controller.dart';

class _FakeRuntime extends Fake implements ReaderV2Runtime {
  @override
  final ReaderV2State state = ReaderV2State(
    lifecycle: ReaderV2Lifecycle.ready,
    committedLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
    visibleLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
    layoutSpec: ReaderV2LayoutSpec.fromViewport(
      viewportSize: const Size(360, 640),
      style: const ReaderV2LayoutStyle(
        fontSize: 18,
        lineHeight: 1.5,
        letterSpacing: 0,
        paragraphSpacing: 1,
        paddingTop: 0,
        paddingBottom: 0,
        paddingLeft: 16,
        paddingRight: 16,
      ),
    ),
    layoutGeneration: 0,
  );
}

void main() {
  test(
    'viewport command error stops auto page and preserves the root cause',
    () async {
      final error = StateError('boom');
      final viewport =
          ReaderV2ViewportController()
            ..continuousScrollBy = (_) => Future<bool>.error(error);
      final controller = ReaderV2AutoPageController(
        runtime: _FakeRuntime(),
        viewportController: viewport,
        timerFactory:
            (_, _) => Timer(const Duration(days: 1), () {
              // 測試直接呼叫 stepAsync；長 timer 只維持 running 狀態。
            }),
      );
      addTearDown(controller.dispose);

      controller.start();
      expect(controller.isRunning, isTrue);
      await expectLater(controller.stepAsync(), throwsA(same(error)));

      expect(controller.isRunning, isFalse);
    },
  );
}

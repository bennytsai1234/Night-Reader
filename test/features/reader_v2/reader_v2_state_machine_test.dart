import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state_machine.dart';

void main() {
  group('ReaderV2StateMachine', () {
    test('older operation token cannot complete newer state', () {
      final machine = ReaderV2StateMachine(_initialState());
      final firstJump = machine.beginJump();
      final secondJump = machine.beginJump();

      final oldCompleted = machine.completeReady(
        firstJump,
        visibleLocation: const ReaderV2Location(
          chapterIndex: 1,
          charOffset: 0,
        ),
      );
      expect(oldCompleted, isFalse);
      expect(machine.state.phase, ReaderV2Phase.layingOut);
      expect(machine.state.visibleLocation.chapterIndex, 0);

      final currentCompleted = machine.completeReady(
        secondJump,
        visibleLocation: const ReaderV2Location(
          chapterIndex: 2,
          charOffset: 0,
        ),
      );
      expect(currentCompleted, isTrue);
      expect(machine.state.phase, ReaderV2Phase.ready);
      expect(machine.state.visibleLocation.chapterIndex, 2);
    });

    test(
      'presentation operation updates layout generation and rejects stale token',
      () {
        final machine = ReaderV2StateMachine(_initialState());
        final spec = _layoutSpec(fontSize: 22);
        final presentation = machine.beginPresentation(
          spec: spec,
          layoutGeneration: 1,
        );

        expect(machine.state.phase, ReaderV2Phase.switchingMode);
        expect(machine.state.layoutGeneration, 1);
        expect(machine.state.layoutSpec.layoutSignature, spec.layoutSignature);

        machine.beginContentReload(layoutGeneration: 2);

        final completed = machine.completeReady(presentation);
        expect(completed, isFalse);
        expect(machine.state.phase, ReaderV2Phase.layingOut);
        expect(machine.state.layoutGeneration, 2);
      },
    );

    test('fail only applies to the current operation', () {
      final machine = ReaderV2StateMachine(_initialState());
      final restore = machine.beginRestore();
      machine.beginJump();

      expect(machine.fail(restore, 'old restore failed'), isFalse);
      expect(machine.state.phase, ReaderV2Phase.layingOut);
      expect(machine.state.errorMessage, isNull);
    });
  });
}

ReaderV2State _initialState() {
  return ReaderV2State(
    phase: ReaderV2Phase.ready,
    committedLocation: const ReaderV2Location(
      chapterIndex: 0,
      charOffset: 0,
    ),
    visibleLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
    layoutSpec: _layoutSpec(),
    layoutGeneration: 0,
  );
}

ReaderV2LayoutSpec _layoutSpec({double fontSize = 18}) {
  return ReaderV2LayoutSpec.fromViewport(
    viewportSize: const Size(360, 640),
    style: ReaderV2LayoutStyle(
      fontSize: fontSize,
      lineHeight: 1.6,
      letterSpacing: 0,
      paragraphSpacing: 8,
      paddingTop: 24,
      paddingBottom: 24,
      paddingLeft: 20,
      paddingRight: 20,
      bold: false,
      textIndent: 2,
    ),
  );
}

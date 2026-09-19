import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state_machine.dart';

void main() {
  group('ReaderV2StateMachine', () {
    test('operation start never changes an existing stable Reader world', () {
      final machine = ReaderV2StateMachine(_initialState());
      const target = ReaderV2Location(chapterIndex: 2, charOffset: 8);

      final jump = machine.beginJump(location: target);

      expect(machine.state.lifecycle, ReaderV2Lifecycle.ready);
      expect(machine.state.hasStableWorld, isTrue);
      expect(machine.state.visibleLocation.chapterIndex, 0);
      expect(machine.currentOperation, same(jump));
      expect(machine.pendingLocation, target);
    });

    test('new operation normally cancels the older token', () {
      final machine = ReaderV2StateMachine(_initialState());
      final first = machine.beginJump(
        location: const ReaderV2Location(chapterIndex: 1, charOffset: 0),
      );
      final second = machine.beginJump(
        location: const ReaderV2Location(chapterIndex: 2, charOffset: 0),
      );

      expect(machine.completeOperation(first), isFalse);
      expect(machine.abandonOperation(first), isFalse);
      expect(machine.currentOperation, same(second));
      expect(machine.state.hasStableWorld, isTrue);

      expect(
        machine.completeOperation(
          second,
          visibleLocation: second.targetLocation,
        ),
        isTrue,
      );
      expect(machine.currentOperation, isNull);
      expect(machine.state.visibleLocation.chapterIndex, 2);
    });

    test('presentation is staged until the current operation commits layout', () {
      final machine = ReaderV2StateMachine(_initialState());
      final originalSignature = machine.state.layoutSpec.layoutSignature;
      final spec = _layoutSpec(fontSize: 22);
      final presentation = machine.beginPresentation(
        spec: spec,
        layoutGeneration: 1,
      );

      expect(machine.state.layoutGeneration, 0);
      expect(machine.state.layoutSpec.layoutSignature, originalSignature);
      expect(machine.state.hasStableWorld, isTrue);

      expect(machine.commitLayoutForOperation(presentation), isTrue);
      expect(machine.state.layoutGeneration, 1);
      expect(machine.state.layoutSpec.layoutSignature, spec.layoutSignature);
      expect(machine.state.hasStableWorld, isTrue);
    });

    test('superseding operation inherits an uncommitted layout intent', () {
      final machine = ReaderV2StateMachine(_initialState());
      final spec = _layoutSpec(fontSize: 22);
      final presentation = machine.beginPresentation(
        spec: spec,
        layoutGeneration: 1,
      );
      const target = ReaderV2Location(chapterIndex: 3, charOffset: 42);
      final jump = machine.beginJump(location: target);

      expect(machine.isCurrent(presentation), isFalse);
      expect(jump.layoutGeneration, 1);
      expect(jump.layoutSpec?.layoutSignature, spec.layoutSignature);
      expect(jump.targetLocation, target);
      expect(machine.commitLayoutForOperation(jump), isTrue);
      expect(machine.state.layoutGeneration, 1);
      expect(machine.state.layoutSpec.layoutSignature, spec.layoutSignature);
    });

    test('external unavailability can only mark a Reader with no stable world', () {
      final cold = ReaderV2StateMachine(_initialState(
        lifecycle: ReaderV2Lifecycle.cold,
      ));
      final opening = cold.beginOpen();
      expect(cold.markUnavailable(opening, 'content unavailable'), isTrue);
      expect(cold.state.lifecycle, ReaderV2Lifecycle.unavailable);
      expect(cold.state.hasStableWorld, isFalse);
      expect(cold.currentOperation, isNull);

      final ready = ReaderV2StateMachine(_initialState());
      final jump = ready.beginJump();
      expect(
        () => ready.markUnavailable(jump, 'target unavailable'),
        throwsStateError,
      );
      expect(ready.state.lifecycle, ReaderV2Lifecycle.ready);
      expect(ready.state.hasStableWorld, isTrue);
    });

    test(
      'a presentation inherits semantic intent, not the last painted location',
      () {
        final machine = ReaderV2StateMachine(_initialState());
        const target = ReaderV2Location(chapterIndex: 3, charOffset: 42);
        machine.beginJump(location: target);
        final presentation = machine.beginPresentation(
          spec: _layoutSpec(fontSize: 22),
          layoutGeneration: 1,
        );
        expect(presentation.targetLocation, target);
        expect(machine.pendingLocation, target);
        machine.completeOperation(presentation, visibleLocation: target);
        expect(machine.pendingLocation, isNull);
      },
    );

    test('persisting an older location cannot move the visible position', () {
      final machine = ReaderV2StateMachine(_initialState());
      final before = machine.state.visibleLocation;
      const visible = ReaderV2Location(chapterIndex: 2, charOffset: 50);
      machine.updateVisibleLocation(visible);
      machine.commitLocation(before);
      expect(machine.state.committedLocation, before);
      expect(machine.state.visibleLocation, visible);
    });
  });
}

ReaderV2State _initialState({
  ReaderV2Lifecycle lifecycle = ReaderV2Lifecycle.ready,
}) {
  return ReaderV2State(
    lifecycle: lifecycle,
    committedLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
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

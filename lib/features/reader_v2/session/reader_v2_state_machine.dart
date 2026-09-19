import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';

import 'reader_v2_location.dart';
import 'reader_v2_operation_token.dart';
import 'reader_v2_state.dart';

class ReaderV2StateMachine {
  ReaderV2StateMachine(this.state);

  ReaderV2State state;
  int _nextOperationId = 0;
  ReaderV2OperationToken? _currentOperation;

  ReaderV2OperationToken? get currentOperation => _currentOperation;
  bool get restoreInProgress => state.phase == ReaderV2Phase.restoring;

  ReaderV2Location? get pendingLocation => switch (state.phase) {
    ReaderV2Phase.loading ||
    ReaderV2Phase.layingOut ||
    ReaderV2Phase.restoring ||
    ReaderV2Phase.switchingMode => _currentOperation?.targetLocation,
    _ => null,
  };

  ReaderV2OperationToken beginOpen({ReaderV2Location? location}) {
    return _beginOperation(
      ReaderV2OperationKind.open,
      targetLocation: location,
      phase: ReaderV2Phase.loading,
      clearError: true,
    );
  }

  ReaderV2OperationToken beginJump({ReaderV2Location? location}) {
    return _beginOperation(
      ReaderV2OperationKind.jump,
      targetLocation: location,
      phase: ReaderV2Phase.layingOut,
      clearError: true,
    );
  }

  ReaderV2OperationToken beginRestore({ReaderV2Location? location}) {
    return _beginOperation(
      ReaderV2OperationKind.restore,
      targetLocation: location,
      phase: ReaderV2Phase.restoring,
      clearError: true,
    );
  }

  ReaderV2OperationToken beginPresentation({
    required ReaderV2LayoutSpec spec,
    ReaderV2Location? location,
    required int layoutGeneration,
  }) {
    return _beginOperation(
      ReaderV2OperationKind.presentation,
      targetLocation: location,
      phase: ReaderV2Phase.switchingMode,
      layoutSpec: spec,
      layoutGeneration: layoutGeneration,
      clearError: true,
    );
  }

  ReaderV2OperationToken beginContentReload({
    required int layoutGeneration,
    ReaderV2Location? location,
  }) {
    return _beginOperation(
      ReaderV2OperationKind.contentReload,
      targetLocation: location,
      phase: ReaderV2Phase.layingOut,
      layoutGeneration: layoutGeneration,
      clearError: true,
    );
  }

  void updateVisibleLocation(ReaderV2Location location) {
    state = state.copyWith(visibleLocation: location);
  }

  void commitLocation(ReaderV2Location location) {
    state = state.copyWith(committedLocation: location);
  }

  bool isCurrent(ReaderV2OperationToken token) {
    final current = _currentOperation;
    return current != null &&
        current.id == token.id &&
        current.kind == token.kind &&
        state.layoutGeneration == token.layoutGeneration;
  }

  bool completeReady(
    ReaderV2OperationToken token, {
    ReaderV2Location? visibleLocation,
    bool clearError = true,
  }) {
    if (!isCurrent(token)) return false;
    state = state.copyWith(
      phase: ReaderV2Phase.ready,
      visibleLocation: visibleLocation,
      clearError: clearError,
    );
    return true;
  }

  bool fail(ReaderV2OperationToken token, Object error) {
    if (!isCurrent(token)) return false;
    state = state.copyWith(
      phase: ReaderV2Phase.error,
      errorMessage: error.toString(),
    );
    return true;
  }

  ReaderV2OperationToken _beginOperation(
    ReaderV2OperationKind kind, {
    required ReaderV2Phase phase,
    ReaderV2Location? targetLocation,
    ReaderV2LayoutSpec? layoutSpec,
    int? layoutGeneration,
    bool clearError = false,
  }) {
    final generation = layoutGeneration ?? state.layoutGeneration;
    final token = ReaderV2OperationToken(
      targetLocation:
          targetLocation ?? pendingLocation ?? state.visibleLocation,
      id: ++_nextOperationId,
      kind: kind,
      layoutGeneration: generation,
    );
    _currentOperation = token;
    state = state.copyWith(
      phase: phase,
      layoutSpec: layoutSpec,
      layoutGeneration: generation,
      clearError: clearError,
    );
    return token;
  }
}

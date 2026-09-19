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
  ReaderV2Location? get pendingLocation => _currentOperation?.targetLocation;

  ReaderV2OperationToken beginOpen({ReaderV2Location? location}) {
    if (state.lifecycle == ReaderV2Lifecycle.unavailable) {
      state = state.copyWith(
        lifecycle: ReaderV2Lifecycle.cold,
        clearUnavailableMessage: true,
      );
    }
    return _beginOperation(
      ReaderV2OperationKind.open,
      targetLocation: location,
    );
  }

  ReaderV2OperationToken beginJump({ReaderV2Location? location}) {
    return _beginOperation(
      ReaderV2OperationKind.jump,
      targetLocation: location,
    );
  }

  ReaderV2OperationToken beginRestore({ReaderV2Location? location}) {
    return _beginOperation(
      ReaderV2OperationKind.restore,
      targetLocation: location,
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
      layoutGeneration: layoutGeneration,
      layoutSpec: spec,
    );
  }

  ReaderV2OperationToken beginContentReload({
    required int layoutGeneration,
    ReaderV2Location? location,
  }) {
    return _beginOperation(
      ReaderV2OperationKind.contentReload,
      targetLocation: location,
      layoutGeneration: layoutGeneration,
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
        current.kind == token.kind;
  }

  bool commitLayoutForOperation(ReaderV2OperationToken token) {
    if (!isCurrent(token)) return false;
    if (token.layoutGeneration == state.layoutGeneration) return true;
    if (token.layoutGeneration != state.layoutGeneration + 1) {
      throw StateError(
        'Layout generation must advance exactly once for the current operation.',
      );
    }
    state = state.copyWith(
      layoutSpec: token.layoutSpec,
      layoutGeneration: token.layoutGeneration,
    );
    return true;
  }

  bool completeOperation(
    ReaderV2OperationToken token, {
    ReaderV2Location? visibleLocation,
  }) {
    if (!isCurrent(token)) return false;
    _currentOperation = null;
    state = state.copyWith(
      lifecycle: ReaderV2Lifecycle.ready,
      visibleLocation: visibleLocation,
      clearUnavailableMessage: true,
    );
    return true;
  }

  bool abandonOperation(ReaderV2OperationToken token) {
    if (!isCurrent(token)) return false;
    _currentOperation = null;
    return true;
  }

  bool markUnavailable(ReaderV2OperationToken token, Object error) {
    if (!isCurrent(token)) return false;
    if (state.hasStableWorld) {
      throw StateError(
        'A stable Reader world cannot become unavailable from an operation failure.',
      );
    }
    _currentOperation = null;
    state = state.copyWith(
      lifecycle: ReaderV2Lifecycle.unavailable,
      unavailableMessage: error.toString(),
    );
    return true;
  }

  ReaderV2OperationToken _beginOperation(
    ReaderV2OperationKind kind, {
    ReaderV2Location? targetLocation,
    int? layoutGeneration,
    ReaderV2LayoutSpec? layoutSpec,
  }) {
    final previous = _currentOperation;
    final inheritedGeneration =
        previous != null && previous.layoutGeneration > state.layoutGeneration
        ? previous.layoutGeneration
        : state.layoutGeneration;
    final generation = layoutGeneration ?? inheritedGeneration;
    if (generation < state.layoutGeneration ||
        generation > state.layoutGeneration + 1) {
      throw StateError(
        'Operation layout generation is outside the active transaction.',
      );
    }
    ReaderV2LayoutSpec? stagedSpec = layoutSpec;
    if (stagedSpec == null &&
        previous != null &&
        previous.layoutGeneration > state.layoutGeneration &&
        generation == previous.layoutGeneration) {
      stagedSpec = previous.layoutSpec;
    }
    final token = ReaderV2OperationToken(
      targetLocation:
          targetLocation ?? previous?.targetLocation ?? state.visibleLocation,
      id: ++_nextOperationId,
      kind: kind,
      layoutGeneration: generation,
      layoutSpec: stagedSpec,
    );
    _currentOperation = token;
    return token;
  }
}

import 'package:flutter/foundation.dart';
import 'package:night_reader/features/reader/layout/reader_layout_spec.dart';

import 'reader_location.dart';
import 'reader_operation_token.dart';
import 'reader_state.dart';

class ReaderStateMachine {
  ReaderStateMachine(ReaderState state)
    : _state = state,
      _visibleChapterIndex = ValueNotifier(state.visibleLocation.chapterIndex);

  ReaderState _state;
  ReaderState get state => _state;
  set state(ReaderState value) {
    _state = value;
    _visibleChapterIndex.value = value.visibleLocation.chapterIndex;
  }

  /// 畫面上這一章（[ReaderState.visibleLocation] 的章）。每一次寫入位置
  /// 都跟著更新，捲動途中悄悄記下的位置也一樣；章名、上一章／下一章、
  /// 目錄的目前章各自聽它，換章時只有它們更新，閱讀頁不重建（ADR 0029
  /// 做法 3）。未正規化，用的人自己夾在章數內。
  final ValueNotifier<int> _visibleChapterIndex;
  ValueListenable<int> get visibleChapterIndex => _visibleChapterIndex;

  void dispose() => _visibleChapterIndex.dispose();
  int _nextOperationId = 0;
  ReaderOperationToken? _currentOperation;
  ReaderLayoutSpec? _stagedLayoutSpec;

  ReaderOperationToken? get currentOperation => _currentOperation;
  ReaderLocation? get pendingLocation => _currentOperation?.targetLocation;
  ReaderLayoutSpec? get stagedLayoutSpec => _stagedLayoutSpec;
  ReaderLayoutSpec get effectiveLayoutSpec =>
      _stagedLayoutSpec ?? state.layoutSpec;

  ReaderOperationToken beginOpen({ReaderLocation? location}) {
    if (state.lifecycle == ReaderLifecycle.unavailable) {
      state = state.copyWith(
        lifecycle: ReaderLifecycle.cold,
        clearUnavailableMessage: true,
      );
    }
    return _beginOperation(ReaderOperationKind.open, targetLocation: location);
  }

  ReaderOperationToken beginJump({ReaderLocation? location}) {
    return _beginOperation(ReaderOperationKind.jump, targetLocation: location);
  }

  ReaderOperationToken beginRestore({ReaderLocation? location}) {
    return _beginOperation(
      ReaderOperationKind.restore,
      targetLocation: location,
    );
  }

  ReaderOperationToken beginPresentation({
    required ReaderLayoutSpec spec,
    ReaderLocation? location,
    required int layoutGeneration,
  }) {
    return _beginOperation(
      ReaderOperationKind.presentation,
      targetLocation: location,
      layoutGeneration: layoutGeneration,
      layoutSpec: spec,
    );
  }

  ReaderOperationToken beginContentReload({ReaderLocation? location}) {
    return _beginOperation(
      ReaderOperationKind.contentReload,
      targetLocation: location,
    );
  }

  void updateVisibleLocation(ReaderLocation location) {
    state = state.copyWith(visibleLocation: location);
  }

  void commitLocation(ReaderLocation location) {
    state = state.copyWith(committedLocation: location);
  }

  bool updateViewportSpec(ReaderLayoutSpec spec) {
    final operation = _currentOperation;
    final ownerSpec = effectiveLayoutSpec;
    if (spec.layoutSignature != ownerSpec.layoutSignature) {
      throw StateError('Viewport updates cannot change text layout identity.');
    }
    if (spec.presentationSignature == ownerSpec.presentationSignature) {
      return false;
    }

    if (_stagedLayoutSpec != null) {
      _stagedLayoutSpec = spec;
    }
    if (operation == null ||
        operation.layoutGeneration == state.layoutGeneration) {
      state = state.copyWith(layoutSpec: spec);
    }
    return true;
  }

  /// 開書之前（還沒排過正文）版面變了：換成 [spec]，開書直接照它排。換了
  /// 排版的照常換一代，正文層跟著換掉照舊版面準備的東西。
  void replaceLayoutBeforeOpen(ReaderLayoutSpec spec) {
    if (state.hasStableWorld) {
      throw StateError(
        'A laid-out Reader world must relayout through an operation.',
      );
    }
    final relayout = spec.layoutSignature != state.layoutSpec.layoutSignature;
    state = state.copyWith(
      layoutSpec: spec,
      layoutGeneration: relayout
          ? state.layoutGeneration + 1
          : state.layoutGeneration,
    );
  }

  bool isCurrent(ReaderOperationToken token) {
    final current = _currentOperation;
    return current != null &&
        current.id == token.id &&
        current.kind == token.kind;
  }

  bool publishContentGeneration(int generation) {
    if (generation < state.contentGeneration) {
      throw StateError(
        'Content generation cannot move backwards: '
        'current=${state.contentGeneration}, next=$generation.',
      );
    }
    if (generation == state.contentGeneration) return false;
    state = state.copyWith(contentGeneration: generation);
    return true;
  }

  bool commitLayoutForOperation(ReaderOperationToken token) {
    if (!isCurrent(token)) return false;
    final stagedSpec = _stagedLayoutSpec;
    if (token.layoutGeneration == state.layoutGeneration) {
      if (stagedSpec == null) return true;
      if (stagedSpec.layoutSignature != state.layoutSpec.layoutSignature) {
        throw StateError(
          'Same-generation presentation cannot change text layout identity.',
        );
      }
      state = state.copyWith(layoutSpec: stagedSpec);
      return true;
    }
    if (token.layoutGeneration != state.layoutGeneration + 1) {
      throw StateError(
        'Layout generation must advance exactly once for the current operation.',
      );
    }
    if (stagedSpec == null) {
      throw StateError(
        'A layout generation cannot advance without a staged layout spec.',
      );
    }
    state = state.copyWith(
      layoutSpec: stagedSpec,
      layoutGeneration: token.layoutGeneration,
    );
    return true;
  }

  bool completeOperation(
    ReaderOperationToken token, {
    ReaderLocation? visibleLocation,
  }) {
    if (!isCurrent(token)) return false;
    _currentOperation = null;
    _stagedLayoutSpec = null;
    state = state.copyWith(
      lifecycle: ReaderLifecycle.ready,
      visibleLocation: visibleLocation,
      clearUnavailableMessage: true,
    );
    return true;
  }

  bool abandonOperation(ReaderOperationToken token) {
    if (!isCurrent(token)) return false;
    _currentOperation = null;
    _stagedLayoutSpec = null;
    return true;
  }

  bool markUnavailable(ReaderOperationToken token, Object error) {
    if (!isCurrent(token)) return false;
    if (state.hasStableWorld) {
      throw StateError(
        'A stable Reader world cannot become unavailable from an operation failure.',
      );
    }
    _currentOperation = null;
    _stagedLayoutSpec = null;
    state = state.copyWith(
      lifecycle: ReaderLifecycle.unavailable,
      unavailableMessage: error.toString(),
    );
    return true;
  }

  ReaderOperationToken _beginOperation(
    ReaderOperationKind kind, {
    ReaderLocation? targetLocation,
    int? layoutGeneration,
    ReaderLayoutSpec? layoutSpec,
  }) {
    final previous = _currentOperation;
    final previousStagedSpec = _stagedLayoutSpec;
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
    ReaderLayoutSpec? stagedSpec = layoutSpec;
    if (stagedSpec == null &&
        previous != null &&
        previous.layoutGeneration > state.layoutGeneration &&
        generation == previous.layoutGeneration) {
      stagedSpec = previousStagedSpec;
    }
    final token = ReaderOperationToken(
      targetLocation:
          targetLocation ?? previous?.targetLocation ?? state.visibleLocation,
      id: ++_nextOperationId,
      kind: kind,
      layoutGeneration: generation,
    );
    _currentOperation = token;
    _stagedLayoutSpec = stagedSpec;
    return token;
  }
}

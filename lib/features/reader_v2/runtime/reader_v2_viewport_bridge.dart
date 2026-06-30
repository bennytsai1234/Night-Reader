import 'dart:async';

import 'package:flutter/widgets.dart';

import 'reader_v2_location.dart';
import 'reader_v2_runtime.dart';
import 'reader_v2_state.dart';

class ReaderV2ViewportBridge {
  final ReaderV2Runtime _runtime;

  ReaderV2ViewportBridge(this._runtime);

  Object? _visibleLocationCaptureOwner;
  ReaderV2VisibleLocationCapture? _visibleLocationCapture;
  Object? _viewportRestoreOwner;
  ReaderV2ViewportRestore? _viewportRestore;

  ReaderV2ViewportRestore? get viewportRestore => _viewportRestore;

  void registerVisibleLocationCapture(
    Object owner,
    ReaderV2VisibleLocationCapture capture,
  ) {
    _visibleLocationCaptureOwner = owner;
    _visibleLocationCapture = capture;
  }

  void unregisterVisibleLocationCapture(Object owner) {
    if (!identical(_visibleLocationCaptureOwner, owner)) return;
    _visibleLocationCaptureOwner = null;
    _visibleLocationCapture = null;
  }

  void registerViewportRestore(Object owner, ReaderV2ViewportRestore restore) {
    _viewportRestoreOwner = owner;
    _viewportRestore = restore;
  }

  void unregisterViewportRestore(Object owner) {
    if (!identical(_viewportRestoreOwner, owner)) return;
    _viewportRestoreOwner = null;
    _viewportRestore = null;
  }

  ReaderV2Location? captureVisibleLocation({
    bool notifyIfChanged = true,
    bool allowDuringRestore = false,
  }) =>
      _captureVisibleLocation(
        notifyIfChanged: notifyIfChanged,
        allowDuringRestore: allowDuringRestore,
      );

  Future<ReaderV2Location?> saveProgress({
    ReaderV2Location? location,
    bool immediate = true,
  }) async {
    if (_runtime.restoreInProgress) return null;
    final targetLocation =
        location ?? captureVisibleLocation(notifyIfChanged: false);
    if (targetLocation == null) return null;
    return _saveProgressLocation(targetLocation, immediate: immediate);
  }

  Future<ReaderV2Location?> flushProgress() {
    if (_runtime.restoreInProgress) return Future<ReaderV2Location?>.value();
    final location = captureVisibleLocation(notifyIfChanged: false) ??
        _runtime.state.visibleLocation;
    return _saveProgressLocation(location);
  }

  Future<ReaderV2Location?> saveJumpAfterSettled(
    ReaderV2Location location, {
    required int requestId,
    required int generation,
  }) {
    return _saveVisibleAnchorAfterViewportSettled(
      fallbackLocation: location,
      restoreLocation: location,
      isCurrent: () => _isCurrentJump(requestId, generation),
    );
  }

  Future<ReaderV2Location?> saveProgressLocation(
    ReaderV2Location location, {
    bool immediate = true,
  }) =>
      _saveProgressLocation(location, immediate: immediate);

  Future<ReaderV2Location?> _saveVisibleAnchorAfterViewportSettled({
    required ReaderV2Location fallbackLocation,
    ReaderV2Location? restoreLocation,
    bool Function()? isCurrent,
    bool immediateSave = true,
  }) async {
    if (WidgetsBinding.instance.hasScheduledFrame) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (_runtime.disposed || _runtime.restoreInProgress) return null;
    if (isCurrent != null && !isCurrent()) return null;
    final restore = _viewportRestore;
    if (restoreLocation != null && restore != null) {
      final restored = await restore(restoreLocation);
      if (_runtime.disposed || _runtime.restoreInProgress) return null;
      if (isCurrent != null && !isCurrent()) return null;
      if (!restored) return null;
    }
    final saved = await saveProgress(immediate: immediateSave);
    if (saved != null) return saved;
    if (_runtime.disposed || _runtime.restoreInProgress) return null;
    if (isCurrent != null && !isCurrent()) return null;
    return _saveProgressLocation(
      fallbackLocation,
      immediate: immediateSave,
    );
  }

  Future<ReaderV2Location?> _saveProgressLocation(
    ReaderV2Location location, {
    bool immediate = true,
  }) async {
    if (_runtime.disposed || _runtime.restoreInProgress) return null;
    final normalized = location.normalized(
      chapterCount: _runtime.repository.chapterCount,
    );
    if (normalized == _runtime.state.committedLocation) {
      if (normalized != _runtime.state.visibleLocation) {
        _runtime.setState(
          _runtime.state.copyWith(visibleLocation: normalized),
        );
      }
      if (immediate) {
        await _runtime.progressController.flush();
      }
      return normalized;
    }
    _runtime.setState(
      _runtime.state.copyWith(
        visibleLocation: normalized,
        committedLocation: normalized,
      ),
    );
    if (immediate) {
      await _runtime.progressController.saveImmediately(normalized);
    } else {
      _runtime.progressController.schedule(normalized);
    }
    return normalized;
  }

  ReaderV2Location? _captureVisibleLocation({
    bool allowDuringRestore = false,
    bool notifyIfChanged = true,
  }) {
    if (_runtime.disposed || _runtime.state.phase != ReaderV2Phase.ready) {
      return null;
    }
    if (_runtime.restoreInProgress && !allowDuringRestore) return null;
    final capture = _visibleLocationCapture;
    if (capture == null) return null;
    final captured = _normalizeCapturedLocation(capture());
    if (captured == null) return null;
    if (captured == _runtime.state.visibleLocation) return captured;
    final next = _runtime.state.copyWith(visibleLocation: captured);
    if (notifyIfChanged) {
      _runtime.setState(next);
    } else {
      _runtime.state = next;
    }
    return captured;
  }

  ReaderV2Location? _normalizeCapturedLocation(ReaderV2Location? location) {
    if (location == null) return null;
    final visualOffset = location.visualOffsetPx;
    if (!visualOffset.isFinite || visualOffset.isNaN) return null;
    if (visualOffset < ReaderV2Location.minVisualOffsetPx ||
        visualOffset > ReaderV2Location.maxVisualOffsetPx) {
      return null;
    }
    return location.normalized(chapterCount: _runtime.repository.chapterCount);
  }

  bool _isCurrentJump(int requestId, int generation) {
    return !_runtime.disposed &&
        requestId == _runtime.jumpRequestId &&
        generation == _runtime.state.layoutGeneration;
  }
}

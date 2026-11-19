import 'reader_location.dart';
import 'reader_runtime.dart';

class ReaderViewportBridge {
  final ReaderRuntime _runtime;

  ReaderViewportBridge(this._runtime);

  Object? _visibleLocationCaptureOwner;
  ReaderVisibleLocationCapture? _visibleLocationCapture;
  Object? _viewportRestoreOwner;
  ReaderViewportRestore? _viewportRestore;

  ReaderViewportRestore? get viewportRestore => _viewportRestore;

  void registerVisibleLocationCapture(
    Object owner,
    ReaderVisibleLocationCapture capture,
  ) {
    _visibleLocationCaptureOwner = owner;
    _visibleLocationCapture = capture;
  }

  void unregisterVisibleLocationCapture(Object owner) {
    if (!identical(_visibleLocationCaptureOwner, owner)) return;
    _visibleLocationCaptureOwner = null;
    _visibleLocationCapture = null;
  }

  void registerViewportRestore(Object owner, ReaderViewportRestore restore) {
    _viewportRestoreOwner = owner;
    _viewportRestore = restore;
  }

  bool unregisterViewportRestore(Object owner) {
    if (!identical(_viewportRestoreOwner, owner)) return false;
    _viewportRestoreOwner = null;
    _viewportRestore = null;
    return true;
  }

  /// 照正文目前的捲動位置更新 [ReaderState.visibleLocation]（見
  /// [ReaderRuntime.updateVisibleLocation]：不通知整個 Runtime）。
  ReaderLocation? captureVisibleLocation() {
    if (_runtime.disposed || !_runtime.state.hasStableWorld) return null;
    final capture = _visibleLocationCapture;
    if (capture == null) return null;
    final captured = _normalizeCapturedLocation(capture());
    if (captured == null) return null;
    if (captured != _runtime.state.visibleLocation) {
      _runtime.updateVisibleLocation(captured);
    }
    return captured;
  }

  Future<ReaderLocation?> saveProgress({
    ReaderLocation? location,
    bool immediate = true,
  }) async {
    final targetLocation = location ?? captureVisibleLocation();
    if (targetLocation == null) return null;
    return _saveProgressLocation(targetLocation, immediate: immediate);
  }

  Future<ReaderLocation?> flushProgress() {
    final location = captureVisibleLocation() ?? _runtime.state.visibleLocation;
    return _saveProgressLocation(location);
  }

  Future<ReaderLocation?> saveProgressLocation(
    ReaderLocation location, {
    bool immediate = true,
  }) => _saveProgressLocation(location, immediate: immediate);

  Future<ReaderLocation?> _saveProgressLocation(
    ReaderLocation location, {
    bool immediate = true,
  }) async {
    if (_runtime.disposed) return null;
    final normalized = location.normalized(
      chapterCount: _runtime.repository.chapterCount,
    );
    if (normalized == _runtime.state.committedLocation) {
      // ReaderLocation equality intentionally describes viewport geometry,
      // not the persisted content identity. The same chapter/offset can now
      // point into a new displayText version, so an unchanged viewport must
      // still pass through ProgressController: it enriches readerAnchorJson
      // from the exact cached ReaderContent before writing.
      if (immediate) {
        await _runtime.progressController.saveImmediately(normalized);
      } else {
        _runtime.progressController.schedule(normalized);
      }
      return normalized;
    }
    _runtime.commitProgressLocation(normalized);
    if (immediate) {
      await _runtime.progressController.saveImmediately(normalized);
    } else {
      _runtime.progressController.schedule(normalized);
    }
    return normalized;
  }

  ReaderLocation? _normalizeCapturedLocation(ReaderLocation? location) {
    if (location == null) return null;
    final visualOffset = location.visualOffsetPx;
    if (!visualOffset.isFinite || visualOffset.isNaN) return null;
    if (visualOffset < ReaderLocation.minVisualOffsetPx ||
        visualOffset > ReaderLocation.maxVisualOffsetPx) {
      return null;
    }
    return location.normalized(chapterCount: _runtime.repository.chapterCount);
  }
}

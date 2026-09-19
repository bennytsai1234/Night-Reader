import 'reader_v2_location.dart';
import 'reader_v2_runtime.dart';

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
  }) => _captureVisibleLocation(notifyIfChanged: notifyIfChanged);

  Future<ReaderV2Location?> saveProgress({
  Future<ReaderV2Location?> saveProgress({
    ReaderV2Location? location,
    bool immediate = true,
  }) async {
    final targetLocation =
        location ?? captureVisibleLocation(notifyIfChanged: false);
    if (targetLocation == null) return null;
    return _saveProgressLocation(targetLocation, immediate: immediate);
  }

  Future<ReaderV2Location?> flushProgress() {
    final location =
        captureVisibleLocation(notifyIfChanged: false) ??
        _runtime.state.visibleLocation;
    return _saveProgressLocation(location);
  }

  Future<ReaderV2Location?> saveProgressLocation(
    ReaderV2Location location, {
    bool immediate = true,
  }) => _saveProgressLocation(location, immediate: immediate);

  Future<ReaderV2Location?> _saveProgressLocation(
    ReaderV2Location location, {
    bool immediate = true,
  }) async {
    if (_runtime.disposed) return null;
    final normalized = location.normalized(
      chapterCount: _runtime.repository.chapterCount,
    );
    if (normalized == _runtime.state.committedLocation) {
      // ReaderV2Location equality intentionally describes viewport geometry,
      // not the persisted content identity. The same chapter/offset can now
      // point into a new displayText version, so an unchanged viewport must
      // still pass through ProgressController: it enriches readerAnchorJson
      // from the exact cached ReaderV2Content before writing.
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

  ReaderV2Location? _captureVisibleLocation({
    bool notifyIfChanged = true,
  }) {
    if (_runtime.disposed || !_runtime.state.hasStableWorld) return null;
    final capture = _visibleLocationCapture;
    if (capture == null) return null;
    final captured = _normalizeCapturedLocation(capture());
    if (captured == null) return null;
    if (captured == _runtime.state.visibleLocation) return captured;
    _runtime.updateVisibleLocation(captured, notify: notifyIfChanged);
    return captured;
  }

  ReaderV2Location? _normalizeCapturedLocation(
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
}

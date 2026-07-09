import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

final class AnchorManager {
  AnchorManager({LayoutEpoch initialEpoch = LayoutEpoch.initial})
    : _epoch = initialEpoch;

  LayoutEpoch _epoch;
  bool _restoreLocked = false;

  LayoutEpoch get epoch => _epoch;
  bool get restoreLocked => _restoreLocked;

  static double anchorOffsetInViewport(double viewportHeight) {
    final safeHeight =
        viewportHeight.isFinite && viewportHeight > 0 ? viewportHeight : 1.0;
    return (safeHeight * 0.2).clamp(24.0, 120.0).toDouble();
  }

  HybridAnchor captureFromLocation(
    ReaderV2Location location,
    ChapterBlocks chapterBlocks,
  ) {
    return HybridAnchor.fromLocation(location, chapterBlocks);
  }

  ReaderV2Location locationFromAnchor(
    HybridAnchor anchor, {
    int? chapterLength,
  }) {
    return anchor.toLocation(chapterLength: chapterLength);
  }

  LayoutEpoch bumpEpoch() {
    _epoch = _epoch.next();
    return _epoch;
  }

  bool beginRestore({required bool isDragging}) {
    if (isDragging) return false;
    _restoreLocked = true;
    return true;
  }

  void completeRestore() {
    _restoreLocked = false;
  }
}

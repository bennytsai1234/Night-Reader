import 'dart:math' as math;

class ReaderV2ChapterSegment {
  ReaderV2ChapterSegment({
    required int chapterIndex,
    required double startY,
    required double height,
  }) : chapterIndex = chapterIndex < 0 ? 0 : chapterIndex,
       startY = _finite(startY),
       height = _height(height);

  final int chapterIndex;
  final double startY;
  final double height;

  double get endY => startY + height;

  static double _finite(double value) {
    return value.isFinite ? value : 0.0;
  }

  static double _height(double value) {
    final finite = _finite(value);
    return finite <= 0 ? 1.0 : finite;
  }
}

class ReaderV2InfiniteSegmentStrip {
  final Map<int, ReaderV2ChapterSegment> _segments =
      <int, ReaderV2ChapterSegment>{};
  int _revision = 0;
  ({double min, double max})? _cachedBounds;
  int? _cachedBoundsRevision;
  double? _cachedBoundsViewportHeight;
  double? _cachedBoundsAnchorOffset;

  bool get isEmpty => _segments.isEmpty;
  int get revision => _revision;

  bool containsChapter(int chapterIndex) {
    return _segments.containsKey(chapterIndex);
  }

  double? chapterTop(int chapterIndex) {
    return _segments[chapterIndex]?.startY;
  }

  double? chapterEnd(int chapterIndex) {
    return _segments[chapterIndex]?.endY;
  }

  void placeChapter({
    required int chapterIndex,
    required double startY,
    required double height,
  }) {
    final next = ReaderV2ChapterSegment(
      chapterIndex: chapterIndex,
      startY: startY,
      height: height,
    );
    final previous = _segments[next.chapterIndex];
    if (previous != null &&
        previous.startY == next.startY &&
        previous.height == next.height) {
      return;
    }
    _segments[next.chapterIndex] = next;
    _revision += 1;
  }

  void retain(Set<int> retained) {
    final before = _segments.length;
    _segments.removeWhere(
      (chapterIndex, _) => !retained.contains(chapterIndex),
    );
    if (_segments.length != before) _revision += 1;
  }

  void clear() {
    if (_segments.isEmpty) return;
    _segments.clear();
    _revision += 1;
  }

  ({double min, double max})? scrollBounds({
    required double viewportHeight,
    required double anchorOffset,
  }) {
    final cached = _cachedBounds;
    if (cached != null &&
        _cachedBoundsRevision == _revision &&
        _cachedBoundsViewportHeight == viewportHeight &&
        _cachedBoundsAnchorOffset == anchorOffset) {
      return cached;
    }
    if (_segments.isEmpty) {
      _cachedBounds = null;
      _cachedBoundsRevision = _revision;
      _cachedBoundsViewportHeight = viewportHeight;
      _cachedBoundsAnchorOffset = anchorOffset;
      return null;
    }
    var minTop = double.infinity;
    var maxBottom = double.negativeInfinity;
    for (final segment in _segments.values) {
      if (segment.startY < minTop) minTop = segment.startY;
      if (segment.endY > maxBottom) maxBottom = segment.endY;
    }
    final minScrollY = minTop;
    final maxScrollY = math.max(
      minScrollY,
      math.max(maxBottom - viewportHeight, maxBottom - anchorOffset),
    );
    final bounds = (min: minScrollY, max: maxScrollY);
    _cachedBounds = bounds;
    _cachedBoundsRevision = _revision;
    _cachedBoundsViewportHeight = viewportHeight;
    _cachedBoundsAnchorOffset = anchorOffset;
    return bounds;
  }

  bool isNearEdge({
    required bool forward,
    required double readingY,
    required double threshold,
    required double viewportHeight,
    required double anchorOffset,
  }) {
    final bounds = scrollBounds(
      viewportHeight: viewportHeight,
      anchorOffset: anchorOffset,
    );
    if (bounds == null) return false;
    const tolerance = 0.5;
    return forward
        ? bounds.max - readingY <= threshold + tolerance
        : readingY - bounds.min <= threshold + tolerance;
  }
}

import 'dart:ui';

import 'reader_v2_render_page.dart';

/// Lightweight render-layer view over a [ReaderV2RenderPage].
///
/// Instead of copying all fields and duplicating query methods from
/// [ReaderV2RenderPage], this class delegates to the source page directly.
/// The only additional state it carries is an optional [height] override
/// (typically the viewport height, used for scroll layout).
class ReaderV2PageCache {
  ReaderV2PageCache._({required this.source, double? heightOverride})
    : height = _normalizeNonNegative(heightOverride ?? source.viewportHeight);

  factory ReaderV2PageCache.fromRenderPage(
    ReaderV2RenderPage page, {
    double? height,
  }) {
    return ReaderV2PageCache._(source: page, heightOverride: height);
  }

  /// The underlying render page this cache delegates to.
  final ReaderV2RenderPage source;

  // ── Delegated properties ──────────────────────────────────────────

  int get chapterIndex => source.chapterIndex;
  int get pageIndexInChapter => source.pageIndex;
  int get pageIndex => source.pageIndex;
  int get startCharOffset => source.startCharOffset;
  int get endCharOffset => source.endCharOffset;
  double get localStartY => source.localStartY;
  double get localEndY => source.localEndY;
  double get width => source.width;
  List<ReaderV2RenderLine> get lines => source.lines;

  /// The viewport height for this tile (may differ from content height).
  final double height;

  double get contentHeight =>
      (localEndY - localStartY).clamp(0.0, double.infinity).toDouble();

  // ── Delegated query methods ───────────────────────────────────────

  bool containsCharOffset(int charOffset) {
    if (lines.isEmpty) return charOffset == startCharOffset;
    if (charOffset < startCharOffset || charOffset > endCharOffset) {
      return false;
    }
    return charOffset < endCharOffset;
  }

  bool intersectsCharRange(int startCharOffset, int endCharOffset) {
    final start =
        startCharOffset <= endCharOffset ? startCharOffset : endCharOffset;
    final end =
        startCharOffset <= endCharOffset ? endCharOffset : startCharOffset;
    if (start == end) return containsCharOffset(start);
    return end > this.startCharOffset && start < this.endCharOffset;
  }

  ReaderV2RenderLine? lineForCharOffset(int charOffset) {
    ReaderV2RenderLine? previous;
    for (final line in lines) {
      if (line.text.isEmpty) continue;
      if (charOffset >= line.startCharOffset &&
          charOffset < line.endCharOffset) {
        return line;
      }
      if (charOffset < line.startCharOffset) return line;
      previous = line;
    }
    return previous;
  }

  ReaderV2RenderLine? lineAtOrNearLocalY(double localY) {
    if (lines.isEmpty) return null;
    final pageLocalY =
        (localY - localStartY).clamp(0.0, contentHeight).toDouble();
    ReaderV2RenderLine? nearest;
    var nearestDistance = double.infinity;
    for (final line in lines) {
      if (line.text.isEmpty) continue;
      if (pageLocalY >= line.top && pageLocalY <= line.bottom) return line;
      final distance =
          pageLocalY < line.top
              ? line.top - pageLocalY
              : pageLocalY - line.bottom;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = line;
      }
    }
    return nearest;
  }

  List<ReaderV2RenderLine> linesForRange(
    int startCharOffset,
    int endCharOffset,
  ) {
    final start =
        startCharOffset <= endCharOffset ? startCharOffset : endCharOffset;
    final end =
        startCharOffset <= endCharOffset ? endCharOffset : startCharOffset;
    if (start == end) {
      final line = lineForCharOffset(start);
      return line == null
          ? const <ReaderV2RenderLine>[]
          : <ReaderV2RenderLine>[line];
    }
    return lines
        .where(
          (line) =>
              line.text.isNotEmpty &&
              line.endCharOffset > start &&
              line.startCharOffset < end,
        )
        .toList(growable: false);
  }

  List<Rect> fullLineRectsForRange({
    required int startCharOffset,
    required int endCharOffset,
    double pageTopOnScreen = 0.0,
  }) {
    return linesForRange(startCharOffset, endCharOffset)
        .map(
          (line) => Rect.fromLTRB(
            0,
            pageTopOnScreen + line.top,
            width,
            pageTopOnScreen + line.bottom,
          ),
        )
        .toList(growable: false);
  }

  // ── Equality ──────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    return other is ReaderV2PageCache &&
        other.height == height &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(source, height);

  // ── Helpers ───────────────────────────────────────────────────────

  static double _normalizeNonNegative(double value) {
    if (!value.isFinite) return 0.0;
    return value < 0 ? 0.0 : value;
  }
}

class ReaderV2PageCacheFactory {
  const ReaderV2PageCacheFactory._();

  static ReaderV2PageCache fromRenderPage(
    ReaderV2RenderPage page, {
    double? height,
  }) {
    return ReaderV2PageCache.fromRenderPage(page, height: height);
  }

  static List<ReaderV2PageCache> fromRenderPages(
    Iterable<ReaderV2RenderPage> pages, {
    double? height,
  }) {
    return pages
        .map((page) => fromRenderPage(page, height: height))
        .toList(growable: false);
  }
}

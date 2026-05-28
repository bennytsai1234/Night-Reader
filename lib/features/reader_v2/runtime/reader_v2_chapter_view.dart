import 'dart:ui';

import 'package:night_reader/features/reader_v2/layout/reader_v2_layout.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_render_page.dart';
import 'package:night_reader/features/reader_v2/render/reader_v2_text_adapter.dart';

class ReaderV2ChapterView {
  ReaderV2ChapterView(
    this.layout, {
    required this.chapterSize,
    required this.title,
  }) : pages = layout.pages
           .map(
             (slice) => readerV2PageSliceToRenderPage(
               layout: layout,
               slice: slice,
               chapterSize: chapterSize,
               title: title,
             ),
           )
           .toList(growable: false),
       lines = layout.lines
           .map(readerV2TextLineToRenderLine)
           .toList(growable: false) {
    _nonEmptyLines = lines
        .where((line) => line.text.isNotEmpty)
        .toList(growable: false);
    _nonEmptyLineStarts = _nonEmptyLines
        .map((line) => line.startCharOffset)
        .toList(growable: false);
    _nonEmptyLineEffectiveEnds = _buildEffectiveLineEnds(_nonEmptyLines);
    _nonEmptyLineTops = _nonEmptyLines
        .map((line) => line.top)
        .toList(growable: false);
    _pageStartOffsets = pages
        .map((page) => page.startCharOffset)
        .toList(growable: false);
    _pageLocalStarts = pages
        .map((page) => page.localStartY)
        .toList(growable: false);
  }

  final ReaderV2ChapterLayout layout;
  final int chapterSize;
  final String title;
  final List<ReaderV2RenderPage> pages;
  final List<ReaderV2RenderLine> lines;
  late final List<ReaderV2RenderLine> _nonEmptyLines;
  late final List<int> _nonEmptyLineStarts;
  late final List<int> _nonEmptyLineEffectiveEnds;
  late final List<double> _nonEmptyLineTops;
  late final List<int> _pageStartOffsets;
  late final List<double> _pageLocalStarts;

  int get chapterIndex => layout.chapterIndex;
  String get displayText => layout.displayText;
  String get contentHash => layout.contentHash;
  String get layoutSignature => layout.layoutSignature;
  double get contentHeight => layout.contentHeight;

  ReaderV2RenderPage pageForCharOffset(int charOffset) {
    if (pages.isEmpty) {
      return ReaderV2RenderPage(
        pageIndex: 0,
        chapterIndex: chapterIndex,
        lines: const <ReaderV2RenderLine>[],
        height: 1,
      );
    }
    final pageIndex = _lastIndexWhereIntAtMost(_pageStartOffsets, charOffset);
    if (pageIndex < 0) return pages.first;
    final candidate = pages[pageIndex];
    if (candidate.containsCharOffset(charOffset)) return candidate;
    if (pageIndex + 1 < pages.length) {
      final next = pages[pageIndex + 1];
      if (next.containsCharOffset(charOffset)) return next;
    }
    final line = lineForCharOffset(charOffset);
    if (line != null) {
      final page = pageForLocalY(line.top);
      if (page != null) return page;
    }
    return candidate;
  }

  ReaderV2RenderLine? lineForCharOffset(int charOffset) {
    final queryLines = _nonEmptyLines;
    if (queryLines.isEmpty) return null;
    if (charOffset < _nonEmptyLineStarts.first) return queryLines.first;
    final index = _lastIndexWhereIntAtMost(_nonEmptyLineStarts, charOffset);
    if (index < 0) return queryLines.first;
    if (charOffset < _nonEmptyLineEffectiveEnds[index]) {
      return queryLines[index];
    }
    if (index + 1 < queryLines.length) {
      return queryLines[index + 1];
    }
    return queryLines[index];
  }

  ReaderV2RenderPage? pageForLine(ReaderV2RenderLine line) =>
      pageForLocalY(line.top);

  ReaderV2RenderLine? lineAtOrNearLocalY(double localY) {
    final queryLines = _nonEmptyLines;
    if (queryLines.isEmpty) return null;
    final index = _lastIndexWhereDoubleAtMost(_nonEmptyLineTops, localY);
    if (index < 0) return queryLines.first;
    final current = queryLines[index];
    if (localY >= current.top && localY <= current.bottom) return current;
    var nearest = current;
    var nearestDistance = _distanceToLine(current, localY);
    if (index > 0) {
      final previous = queryLines[index - 1];
      final previousDistance = _distanceToLine(previous, localY);
      if (previousDistance < nearestDistance) {
        nearestDistance = previousDistance;
        nearest = previous;
      }
    }
    if (index + 1 < queryLines.length) {
      final next = queryLines[index + 1];
      final nextDistance = _distanceToLine(next, localY);
      if (nextDistance < nearestDistance) {
        nearest = next;
      }
    }
    return nearest;
  }

  ReaderV2RenderPage? pageForLocalY(double localY) {
    if (pages.isEmpty) return null;
    final index = _lastIndexWhereDoubleAtMost(_pageLocalStarts, localY);
    if (index < 0) return pages.first;
    return pages[index];
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
    final queryLines = _nonEmptyLines;
    if (queryLines.isEmpty) return const <ReaderV2RenderLine>[];
    var from = _lastIndexWhereIntAtMost(_nonEmptyLineStarts, start);
    if (from < 0) from = 0;
    while (from < queryLines.length &&
        _nonEmptyLineEffectiveEnds[from] <= start) {
      from += 1;
    }
    if (from >= queryLines.length) return const <ReaderV2RenderLine>[];
    final to = _firstIndexWhereIntAtLeast(_nonEmptyLineStarts, end, from: from);
    return queryLines.sublist(from, to);
  }

  List<Rect> fullLineRectsForRange({
    required int startCharOffset,
    required int endCharOffset,
    double pageTopOnScreen = 0.0,
  }) {
    return linesForRange(startCharOffset, endCharOffset)
        .map((line) {
          final page = pageForLocalY(line.top);
          final pageTop = page?.localStartY ?? 0.0;
          final width = (page?.width ?? 0) > 0 ? page!.width : line.width;
          return Rect.fromLTRB(
            0,
            pageTopOnScreen + line.top - pageTop,
            width,
            pageTopOnScreen + line.bottom - pageTop,
          );
        })
        .toList(growable: false);
  }

  static List<int> _buildEffectiveLineEnds(List<ReaderV2RenderLine> lines) {
    if (lines.isEmpty) return const <int>[];
    final ends = <int>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      var effectiveEnd = line.endCharOffset;
      if (index + 1 < lines.length) {
        final nextStart = lines[index + 1].startCharOffset;
        if (nextStart > effectiveEnd) {
          effectiveEnd = nextStart;
        }
      }
      ends.add(effectiveEnd);
    }
    return ends;
  }

  int _lastIndexWhereIntAtMost(List<int> values, int target) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (values[mid] <= target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low - 1;
  }

  int _lastIndexWhereDoubleAtMost(List<double> values, double target) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (values[mid] <= target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low - 1;
  }

  int _firstIndexWhereIntAtLeast(List<int> values, int target, {int from = 0}) {
    var low = from.clamp(0, values.length).toInt();
    var high = values.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (values[mid] < target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  double _distanceToLine(ReaderV2RenderLine line, double localY) {
    if (localY < line.top) return line.top - localY;
    if (localY > line.bottom) return localY - line.bottom;
    return 0.0;
  }
}

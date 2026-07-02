class ReaderV2TextLine {
  const ReaderV2TextLine({
    required this.text,
    required this.chapterIndex,
    required this.lineIndex,
    required this.startCharOffset,
    required this.endCharOffset,
    required this.top,
    required this.bottom,
    required this.baseline,
    required this.width,
    required this.isTitle,
    required this.paragraphIndex,
    required this.isParagraphStart,
    required this.isParagraphEnd,
  });

  final String text;
  final int chapterIndex;
  final int lineIndex;
  final int startCharOffset;
  final int endCharOffset;
  final double top;
  final double bottom;
  final double baseline;
  final double width;
  final bool isTitle;
  final int paragraphIndex;
  final bool isParagraphStart;
  final bool isParagraphEnd;

  double get height => bottom - top;
}

class ReaderV2PageSlice {
  const ReaderV2PageSlice({
    required this.chapterIndex,
    required this.pageIndex,
    required this.pageCount,
    required this.startLineIndex,
    required this.endLineIndexExclusive,
    required this.startCharOffset,
    required this.endCharOffset,
    required this.localStartY,
    required this.localEndY,
    required this.contentWidth,
    required this.contentHeight,
    required this.viewportHeight,
    required this.isChapterStart,
    required this.isChapterEnd,
  });

  final int chapterIndex;
  final int pageIndex;
  final int pageCount;
  final int startLineIndex;
  final int endLineIndexExclusive;
  final int startCharOffset;
  final int endCharOffset;
  final double localStartY;
  final double localEndY;
  final double contentWidth;
  final double contentHeight;
  final double viewportHeight;
  final bool isChapterStart;
  final bool isChapterEnd;

  bool containsCharOffset(int charOffset) {
    if (charOffset < startCharOffset || charOffset > endCharOffset) {
      return false;
    }
    return charOffset < endCharOffset || isChapterEnd;
  }

  bool containsLineIndex(int lineIndex) {
    return lineIndex >= startLineIndex && lineIndex < endLineIndexExclusive;
  }
}

class ReaderV2ChapterLayout {
  const ReaderV2ChapterLayout({
    required this.chapterIndex,
    required this.displayText,
    required this.contentHash,
    required this.layoutSignature,
    required this.lines,
    required this.pages,
    required this.contentHeight,
    this.isComplete = true,
  });

  final int chapterIndex;
  final String displayText;
  final String contentHash;
  final int layoutSignature;
  final List<ReaderV2TextLine> lines;
  final List<ReaderV2PageSlice> pages;
  final double contentHeight;

  /// false 代表這是排版引擎中途回傳的部分結果，章節尚未排完（見
  /// [ReaderV2LayoutEngine.layoutStep]）。此時 [pages] 的尾頁一定不是章節
  /// 真正的結尾，[pages.length]（即 `pageCount`）也只是目前為止的數量，
  /// 之後還會再變多。
  final bool isComplete;

  List<ReaderV2TextLine> linesForPage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= pages.length) {
      return const <ReaderV2TextLine>[];
    }
    final page = pages[pageIndex];
    return lines
        .skip(page.startLineIndex)
        .take(page.endLineIndexExclusive - page.startLineIndex)
        .toList(growable: false);
  }

  ReaderV2PageSlice pageForCharOffset(int charOffset) {
    if (pages.isEmpty) {
      return ReaderV2PageSlice(
        chapterIndex: chapterIndex,
        pageIndex: 0,
        pageCount: 1,
        startLineIndex: 0,
        endLineIndexExclusive: 0,
        startCharOffset: 0,
        endCharOffset: displayText.length,
        localStartY: 0,
        localEndY: 1,
        contentWidth: 1,
        contentHeight: 1,
        viewportHeight: 1,
        isChapterStart: true,
        isChapterEnd: true,
      );
    }
    for (final page in pages) {
      if (page.containsCharOffset(charOffset)) return page;
    }
    final line = lineForCharOffset(charOffset);
    if (line != null) {
      final page = pageForLine(line);
      if (page != null) return page;
    }
    if (charOffset <= pages.first.startCharOffset) return pages.first;
    var best = pages.first;
    for (final page in pages) {
      if (page.startCharOffset <= charOffset) {
        best = page;
      } else {
        break;
      }
    }
    return best;
  }

  ReaderV2TextLine? lineForCharOffset(int charOffset) {
    ReaderV2TextLine? previous;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.text.isEmpty) continue;
      final effectiveEnd = _effectiveLineEnd(index);
      if (charOffset >= line.startCharOffset && charOffset < effectiveEnd) {
        return line;
      }
      if (charOffset < line.startCharOffset) return line;
      previous = line;
    }
    return previous;
  }

  ReaderV2TextLine? lineAtOrNearLocalY(double localY) {
    ReaderV2TextLine? nearest;
    var nearestDistance = double.infinity;
    for (final line in lines) {
      if (line.text.isEmpty) continue;
      if (localY >= line.top && localY <= line.bottom) return line;
      final distance =
          localY < line.top ? line.top - localY : localY - line.bottom;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = line;
      }
    }
    return nearest;
  }

  ReaderV2PageSlice? pageForLine(ReaderV2TextLine line) {
    if (pages.isEmpty) return null;
    for (final page in pages) {
      if (page.containsLineIndex(line.lineIndex)) return page;
    }
    return null;
  }

  ReaderV2PageSlice? pageForLocalY(double localY) {
    if (pages.isEmpty) return null;
    if (localY <= pages.first.localStartY) return pages.first;
    var best = pages.first;
    for (final page in pages) {
      if (page.localStartY <= localY) {
        best = page;
      } else {
        break;
      }
    }
    return best;
  }

  List<ReaderV2TextLine> linesForRange(int startCharOffset, int endCharOffset) {
    final start =
        startCharOffset <= endCharOffset ? startCharOffset : endCharOffset;
    final end =
        startCharOffset <= endCharOffset ? endCharOffset : startCharOffset;
    if (start == end) {
      final line = lineForCharOffset(start);
      return line == null
          ? const <ReaderV2TextLine>[]
          : <ReaderV2TextLine>[line];
    }
    return lines
        .asMap()
        .entries
        .where((entry) {
          final line = entry.value;
          if (line.text.isEmpty) return false;
          return _effectiveLineEnd(entry.key) > start &&
              line.startCharOffset < end;
        })
        .map((entry) => entry.value)
        .toList(growable: false);
  }

  int _effectiveLineEnd(int index) {
    final line = lines[index];
    for (var nextIndex = index + 1; nextIndex < lines.length; nextIndex++) {
      final next = lines[nextIndex];
      if (next.text.isEmpty) continue;
      if (next.startCharOffset > line.endCharOffset) {
        return next.startCharOffset;
      }
      break;
    }
    return line.endCharOffset;
  }
}

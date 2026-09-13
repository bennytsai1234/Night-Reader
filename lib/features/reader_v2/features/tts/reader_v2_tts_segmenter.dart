import 'dart:math' as math;

/// Splits reader text into system-TTS-sized segments while preserving the
/// reader's UTF-16 coordinate space.
final class ReaderV2TtsSegment {
  const ReaderV2TtsSegment({
    required this.chapterIndex,
    required this.startCharOffset,
    required this.endCharOffset,
    required this.text,
  });

  final int chapterIndex;
  final int startCharOffset;
  final int endCharOffset;
  final String text;
}

final class ReaderV2TtsSegmenter {
  const ReaderV2TtsSegmenter();

  static const int minSegmentLength = 24;
  static const int maxSegmentLength = 220;

  List<ReaderV2TtsSegment> segment({
    required String text,
    required int chapterIndex,
    required int startOffset,
  }) {
    final span = _readableSpan(text, startOffset);
    if (span == null) return const <ReaderV2TtsSegment>[];
    final segments = <ReaderV2TtsSegment>[];
    var cursor = _safeSegmentStart(text, span.start, span.end);
    while (cursor < span.end) {
      while (cursor < span.end && _isWhitespace(text.codeUnitAt(cursor))) {
        cursor += 1;
      }
      if (cursor >= span.end) break;
      var end = _segmentEnd(text, cursor, span.end);
      end = _safeSegmentEnd(text, cursor, end, span.end);
      while (end > cursor && _isWhitespace(text.codeUnitAt(end - 1))) {
        end -= 1;
      }
      if (end <= cursor) {
        // A max-length boundary may land immediately between the two UTF-16
        // code units of one supplementary character. Include the complete
        // pair rather than producing a segment that cannot be decoded alone.
        final next = math.min(span.end, cursor + 2);
        if (next <= cursor) break;
        end = next;
      }
      segments.add(
        ReaderV2TtsSegment(
          chapterIndex: chapterIndex,
          startCharOffset: cursor,
          endCharOffset: end,
          text: text.substring(cursor, end),
        ),
      );
      cursor = end;
    }
    return segments;
  }

  int _segmentEnd(String text, int start, int chapterEnd) {
    final preferredLimit = (start + maxSegmentLength)
        .clamp(start + 1, chapterEnd)
        .toInt();
    for (var index = start; index < preferredLimit; index += 1) {
      final length = index - start + 1;
      if (length < minSegmentLength && index + 1 < chapterEnd) continue;
      final codeUnit = text.codeUnitAt(index);
      if (_isSegmentBoundary(codeUnit)) return index + 1;
    }
    for (var index = preferredLimit - 1; index > start; index -= 1) {
      if (_isWhitespace(text.codeUnitAt(index))) return index;
    }
    return preferredLimit;
  }

  int _safeSegmentStart(String text, int start, int end) {
    if (start > 0 && start < end && _isLowSurrogate(text.codeUnitAt(start))) {
      final previous = text.codeUnitAt(start - 1);
      if (_isHighSurrogate(previous)) return start - 1;
    }
    return start;
  }

  int _safeSegmentEnd(String text, int start, int end, int chapterEnd) {
    if (end > start && end < chapterEnd) {
      final previous = text.codeUnitAt(end - 1);
      final current = text.codeUnitAt(end);
      if (_isHighSurrogate(previous) && _isLowSurrogate(current)) {
        return end - 1;
      }
    }
    return end;
  }

  bool _isHighSurrogate(int codeUnit) {
    return codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
  }

  bool _isLowSurrogate(int codeUnit) {
    return codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
  }

  bool _isSegmentBoundary(int codeUnit) {
    switch (codeUnit) {
      case 0x0A: // \n
      case 0x21: // !
      case 0x2E: // .
      case 0x3B: // ;
      case 0x3F: // ?
      case 0x3002: // 。
      case 0xFF01: // ！
      case 0xFF1B: // ；
      case 0xFF1F: // ？
        return true;
    }
    return false;
  }

  ({int start, int end})? _readableSpan(String text, int offset) {
    var start = offset.clamp(0, text.length).toInt();
    var end = text.length;
    while (start < end && _isWhitespace(text.codeUnitAt(start))) {
      start += 1;
    }
    while (end > start && _isWhitespace(text.codeUnitAt(end - 1))) {
      end -= 1;
    }
    if (start >= end) return null;
    return (start: start, end: end);
  }

  bool _isWhitespace(int codeUnit) {
    switch (codeUnit) {
      case 0x09:
      case 0x0A:
      case 0x0B:
      case 0x0C:
      case 0x0D:
      case 0x20:
      case 0x85:
      case 0xA0:
      case 0x2028:
      case 0x2029:
      case 0x3000:
        return true;
    }
    return false;
  }
}

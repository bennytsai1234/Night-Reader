import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/engine/reader/chinese_text_converter.dart';
import '../session/reader_v2_location.dart';

class ReaderV2Content {
  const ReaderV2Content({
    required this.chapterIndex,
    required this.title,
    required this.paragraphs,
    required this.plainText,
    required this.displayText,
    required this.contentHash,
  });

  final int chapterIndex;
  final String title;
  final List<String> paragraphs;
  final String plainText;
  final String displayText;
  final String contentHash;

  int get bodyStartOffset {
    if (title.isEmpty) return 0;
    return plainText.isEmpty ? title.length : title.length + 2;
  }

  factory ReaderV2Content.fromRaw({
    required int chapterIndex,
    required String title,
    required String rawText,
  }) {
    final normalized = normalizeRawText(rawText);
    final paragraphs =
        normalized.isEmpty
            ? <String>[]
            : normalized
                .split(RegExp(r'\n+'))
                .map((line) => line.trim())
                .where((line) => line.isNotEmpty)
                .toList(growable: false);
    final plainText = paragraphs.join('\n\n');
    final normalizedTitle = title.trim();
    final displayText =
        normalizedTitle.isEmpty
            ? plainText
            : plainText.isEmpty
            ? normalizedTitle
            : '$normalizedTitle\n\n$plainText';
    final hashMaterial = jsonEncode(<String, Object>{
      'chapterIndex': chapterIndex,
      'title': normalizedTitle,
      'paragraphs': paragraphs,
      'displayText': displayText,
    });
    return ReaderV2Content(
      chapterIndex: chapterIndex,
      title: normalizedTitle,
      paragraphs: List<String>.unmodifiable(paragraphs),
      plainText: plainText,
      displayText: displayText,
      contentHash: sha1.convert(utf8.encode(hashMaterial)).toString(),
    );
  }

  static String normalizeRawText(String rawText) {
    return rawText
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

/// Remaps a reader location when the displayed content is re-materialized.
///
/// Content conversion can change Dart's UTF-16 code-unit length (for example,
/// a BMP character can become a supplementary CJK code point).  A raw
/// `charOffset` therefore cannot be reused as a location in the new text.
/// Sentence ordinal is stable across the existing replacement/conversion
/// pipeline, while the proportional in-sentence offset preserves the user's
/// approximate reading position without falling back to the chapter start.
final class ReaderV2ContentLocationMapper {
  const ReaderV2ContentLocationMapper._();

  static const String _sentenceTerminators = '。！？!?；;';
  static const ChineseTextConverter _converter = ChineseTextConverter();

  static ReaderV2Location remap({
    required ReaderV2Location location,
    required ReaderV2Content before,
    required ReaderV2Content after,
  }) {
    if (before.chapterIndex != after.chapterIndex ||
        before.displayText == after.displayText) {
      return location.normalized(chapterLength: after.displayText.length);
    }

    final oldSpans = _sentenceSpans(before.displayText);
    final newSpans = _sentenceSpans(after.displayText);
    if (oldSpans.isEmpty || newSpans.isEmpty) {
      return location.normalized(chapterLength: after.displayText.length);
    }

    final oldOffset = location.charOffset
        .clamp(0, before.displayText.length)
        .toInt();
    final oldIndex = _spanIndexAt(oldSpans, oldOffset);
    if (oldIndex < 0 || oldIndex >= newSpans.length) {
      return location.normalized(chapterLength: after.displayText.length);
    }

    final oldSpan = oldSpans[oldIndex];
    final newSpan = newSpans[oldIndex];
    final oldLength = oldSpan.end - oldSpan.start;
    final relativeOffset = (oldOffset - oldSpan.start)
        .clamp(0, oldLength)
        .toInt();
    final mappedRelativeOffset = _mapWithinEquivalentSentence(
      oldSentence: before.displayText.substring(oldSpan.start, oldSpan.end),
      newSentence: after.displayText.substring(newSpan.start, newSpan.end),
      oldRelativeOffset: relativeOffset,
    );

    return location
        .copyWith(charOffset: newSpan.start + mappedRelativeOffset)
        .normalized(chapterLength: after.displayText.length);
  }

  static int _mapWithinEquivalentSentence({
    required String oldSentence,
    required String newSentence,
    required int oldRelativeOffset,
  }) {
    for (final canonicalType in <int>[1, 2]) {
      final oldCanonical = _converter.convert(
        oldSentence,
        convertType: canonicalType,
      );
      final newCanonical = _converter.convert(
        newSentence,
        convertType: canonicalType,
      );
      if (oldCanonical != newCanonical) continue;

      final oldPrefix = _converter.convert(
        oldSentence.substring(0, oldRelativeOffset),
        convertType: canonicalType,
      );
      final canonicalOffset = oldPrefix.length;
      final boundaries = _codeUnitBoundaries(newSentence);
      var low = 0;
      var high = boundaries.length - 1;
      while (low <= high) {
        final middle = (low + high) ~/ 2;
        final rawOffset = boundaries[middle];
        final canonicalLength = _converter
            .convert(
              newSentence.substring(0, rawOffset),
              convertType: canonicalType,
            )
            .length;
        if (canonicalLength < canonicalOffset) {
          low = middle + 1;
        } else if (canonicalLength > canonicalOffset) {
          high = middle - 1;
        } else {
          return rawOffset;
        }
      }
      // A malformed or ambiguous conversion boundary should still stay in
      // the matched sentence, but is not allowed to split a surrogate pair.
      final nearestIndex = high.clamp(0, boundaries.length - 1).toInt();
      return boundaries[nearestIndex];
    }

    // Replacement rules are not expected to alter sentence boundaries. This
    // proportional fallback is only for a changed sentence that cannot be
    // normalized to a common Chinese conversion form.
    if (oldSentence.isEmpty) return 0;
    return (oldRelativeOffset * newSentence.length / oldSentence.length)
        .round()
        .clamp(0, newSentence.length)
        .toInt();
  }

  static List<int> _codeUnitBoundaries(String text) {
    final boundaries = <int>[0];
    var offset = 0;
    for (final rune in text.runes) {
      offset += String.fromCharCode(rune).length;
      boundaries.add(offset);
    }
    return boundaries;
  }

  static List<({int start, int end})> _sentenceSpans(String text) {
    if (text.isEmpty) return const <({int start, int end})>[];
    final spans = <({int start, int end})>[];
    var start = 0;
    for (var index = 0; index < text.length; index += 1) {
      if (!_sentenceTerminators.contains(text[index])) continue;
      spans.add((start: start, end: index + 1));
      start = index + 1;
    }
    if (start < text.length) spans.add((start: start, end: text.length));
    return spans;
  }

  static int _spanIndexAt(List<({int start, int end})> spans, int offset) {
    for (var index = 0; index < spans.length; index += 1) {
      final span = spans[index];
      if (offset >= span.start && offset < span.end) return index;
    }
    return offset == spans.last.end ? spans.length - 1 : -1;
  }
}

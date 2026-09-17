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

/// Maps a persisted UTF-16 location between concrete `displayText` versions.
///
/// A scalar offset is only meaningful for the content identity it was captured
/// against. The mapper stores a short two-sided text anchor with the content
/// hash and length. When identity changes it resolves that anchor in the new
/// text; sentence ordinals are deliberately not part of the contract, because
/// replacement rules may insert/delete punctuation and line breaks.
final class ReaderV2ContentLocationMapper {
  const ReaderV2ContentLocationMapper._();

  static const int _contextCodeUnits = 48;
  static const ChineseTextConverter _converter = ChineseTextConverter();

  static ReaderV2Location capture({
    required ReaderV2Location location,
    required ReaderV2Content content,
  }) {
    return location
        .normalized(chapterLength: content.displayText.length)
        .withContentIdentity(
          contentHash: content.contentHash,
          displayText: content.displayText,
          contextRadius: _contextCodeUnits,
        );
  }

  static ReaderV2Location resolve({
    required ReaderV2Location location,
    required ReaderV2Content target,
  }) {
    final text = target.displayText;
    if (location.contentHash == target.contentHash) {
      return capture(location: location, content: target);
    }

    final oldLength = location.contentLength;
    final projected = oldLength != null && oldLength > 0
        ? (location.charOffset * text.length / oldLength)
              .round()
              .clamp(0, text.length)
              .toInt()
        : location.charOffset.clamp(0, text.length).toInt();
    final mapped = _resolveTextAnchor(
      text: text,
      before: location.anchorBefore,
      after: location.anchorAfter,
      projectedOffset: projected,
    );
    final resolved = location.copyWith(
      charOffset: mapped ?? projected,
      clearContentIdentity: true,
    );
    return capture(location: resolved, content: target);
  }

  static ReaderV2Location remap({
    required ReaderV2Location location,
    required ReaderV2Content before,
    required ReaderV2Content after,
  }) {
    if (before.chapterIndex != after.chapterIndex) {
      return resolve(
        location: capture(location: location, content: before),
        target: after,
      );
    }
    if (before.contentHash == after.contentHash) {
      return capture(location: location, content: after);
    }

    final oldOffset = location.charOffset
        .clamp(0, before.displayText.length)
        .toInt();
    // Chinese conversion may change UTF-16 length while leaving the canonical
    // text identical. Preserve the exact canonical prefix in that case before
    // falling back to the content anchor used for arbitrary replacements.
    final canonicalOffset = _mapCanonicalEquivalent(
      before: before.displayText,
      after: after.displayText,
      oldOffset: oldOffset,
    );
    if (canonicalOffset != null) {
      return capture(
        location: location.copyWith(
          charOffset: canonicalOffset,
          clearContentIdentity: true,
        ),
        content: after,
      );
    }

    return resolve(
      location: capture(location: location, content: before),
      target: after,
    );
  }

  static int? _resolveTextAnchor({
    required String text,
    required String? before,
    required String? after,
    required int projectedOffset,
  }) {
    final left = before ?? '';
    final right = after ?? '';
    if (left.isEmpty && right.isEmpty) return null;

    if (left.isNotEmpty && right.isNotEmpty) {
      final combined = '$left$right';
      final matches = _allOccurrences(text, combined)
          .map((start) => start + left.length)
          .toList(growable: false);
      if (matches.isNotEmpty) return _nearest(matches, projectedOffset);
    }

    final candidates = <int>[];
    if (left.isNotEmpty) {
      candidates.addAll(
        _allOccurrences(text, left).map((start) => start + left.length),
      );
    }
    if (right.isNotEmpty) {
      candidates.addAll(_allOccurrences(text, right));
    }
    if (candidates.isEmpty) return null;
    return _nearest(candidates, projectedOffset);
  }

  static Iterable<int> _allOccurrences(String text, String needle) sync* {
    if (needle.isEmpty) return;
    var start = 0;
    while (start <= text.length - needle.length) {
      final found = text.indexOf(needle, start);
      if (found < 0) return;
      yield found;
      start = found + 1;
    }
  }

  static int _nearest(Iterable<int> candidates, int target) {
    var best = candidates.first;
    var bestDistance = (best - target).abs();
    for (final candidate in candidates.skip(1)) {
      final distance = (candidate - target).abs();
      if (distance < bestDistance) {
        best = candidate;
        bestDistance = distance;
      }
    }
    return best;
  }

  static int? _mapCanonicalEquivalent({
    required String before,
    required String after,
    required int oldOffset,
  }) {
    for (final canonicalType in <int>[1, 2]) {
      final oldCanonical = _converter.convert(
        before,
        convertType: canonicalType,
      );
      final newCanonical = _converter.convert(
        after,
        convertType: canonicalType,
      );
      if (oldCanonical != newCanonical) continue;

      final safeOldOffset = _safeBoundaryAtOrBefore(before, oldOffset);
      final canonicalPrefixLength = _converter
          .convert(
            before.substring(0, safeOldOffset),
            convertType: canonicalType,
          )
          .length;
      final boundaries = _codeUnitBoundaries(after);
      var low = 0;
      var high = boundaries.length - 1;
      while (low <= high) {
        final middle = (low + high) ~/ 2;
        final rawOffset = boundaries[middle];
        final canonicalLength = _converter
            .convert(
              after.substring(0, rawOffset),
              convertType: canonicalType,
            )
            .length;
        if (canonicalLength < canonicalPrefixLength) {
          low = middle + 1;
        } else if (canonicalLength > canonicalPrefixLength) {
          high = middle - 1;
        } else {
          return rawOffset;
        }
      }
      return boundaries[high.clamp(0, boundaries.length - 1).toInt()];
    }
    return null;
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

  static int _safeBoundaryAtOrBefore(String text, int offset) {
    final safe = offset.clamp(0, text.length).toInt();
    if (safe <= 0 || safe >= text.length) return safe;
    final previous = text.codeUnitAt(safe - 1);
    final next = text.codeUnitAt(safe);
    return _isHighSurrogate(previous) && _isLowSurrogate(next)
        ? safe - 1
        : safe;
  }

  static bool _isHighSurrogate(int value) => value >= 0xD800 && value <= 0xDBFF;
  static bool _isLowSurrogate(int value) => value >= 0xDC00 && value <= 0xDFFF;
}

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/engine/reader/chinese_text_converter.dart';
import '../session/reader_v2_location.dart';
import 'reader_v2_illustration.dart';

export 'reader_v2_illustration.dart';

/// 一張插圖對到的圖檔與大小（[ReaderV2Content.fromRaw]）。
typedef ReaderV2IllustrationSlot = ({
  String src,
  String path,
  int pixelWidth,
  int pixelHeight,
});

class ReaderV2Content {
  const ReaderV2Content({
    required this.chapterIndex,
    required this.title,
    required this.paragraphs,
    required this.plainText,
    required this.displayText,
    required this.contentHash,
    this.illustrations = const <ReaderV2Illustration>[],
  });

  final int chapterIndex;
  final String title;
  final List<String> paragraphs;
  final String plainText;
  final String displayText;
  final String contentHash;

  /// 要顯示的插圖，照位置排（ADR 0050）。圖不在 [displayText] 裡，關掉
  /// 「顯示插圖」時這裡是空的，字一模一樣。
  final List<ReaderV2Illustration> illustrations;

  int get bodyStartOffset {
    if (title.isEmpty) return 0;
    return plainText.isEmpty ? title.length : title.length + 2;
  }

  /// [rawText] 裡的 [ReaderV2IllustrationMarkers.placeholder] 是插圖的位置：
  /// 一律拿掉，第 i 個對應 [illustrationSlots] 的第 i 個；是 null（關掉
  /// 「顯示插圖」、圖檔不在或讀不出大小）的那張不顯示。只有插圖的段落不
  /// 成段，圖放在下一段前面。
  factory ReaderV2Content.fromRaw({
    required int chapterIndex,
    required String title,
    required String rawText,
    List<ReaderV2IllustrationSlot?> illustrationSlots =
        const <ReaderV2IllustrationSlot?>[],
  }) {
    final placed = _placeIllustrations(paragraphsOf(rawText));
    final paragraphs = placed.paragraphs;
    final plainText = paragraphs.join('\n\n');
    final normalizedTitle = title.trim();
    final displayText = normalizedTitle.isEmpty
        ? plainText
        : plainText.isEmpty
        ? normalizedTitle
        : '$normalizedTitle\n\n$plainText';
    final bodyStart = normalizedTitle.isEmpty
        ? 0
        : plainText.isEmpty
        ? normalizedTitle.length
        : normalizedTitle.length + 2;
    final paragraphStarts = <int>[];
    var cursor = bodyStart;
    for (final paragraph in paragraphs) {
      paragraphStarts.add(cursor);
      cursor += paragraph.length + 2;
    }
    final illustrations = <ReaderV2Illustration>[];
    for (var i = 0; i < placed.positions.length; i += 1) {
      final slot = i < illustrationSlots.length ? illustrationSlots[i] : null;
      if (slot == null) continue;
      final position = placed.positions[i];
      final offset = position.paragraph >= paragraphs.length
          ? displayText.length
          : paragraphStarts[position.paragraph] + position.offset;
      illustrations.add(
        ReaderV2Illustration(
          offset: offset,
          src: slot.src,
          path: slot.path,
          pixelWidth: slot.pixelWidth,
          pixelHeight: slot.pixelHeight,
        ),
      );
    }
    final hashMaterial = jsonEncode(<String, Object>{
      'chapterIndex': chapterIndex,
      'title': normalizedTitle,
      'paragraphs': paragraphs,
      'displayText': displayText,
      // 沒有插圖的章節雜湊和以前一樣，既有的排版快取照用。
      if (illustrations.isNotEmpty)
        'illustrations': [
          for (final illustration in illustrations)
            [
              illustration.offset,
              illustration.path,
              illustration.pixelWidth,
              illustration.pixelHeight,
            ],
        ],
    });
    return ReaderV2Content(
      chapterIndex: chapterIndex,
      title: normalizedTitle,
      paragraphs: List<String>.unmodifiable(paragraphs),
      plainText: plainText,
      displayText: displayText,
      contentHash: sha1.convert(utf8.encode(hashMaterial)).toString(),
      illustrations: List<ReaderV2Illustration>.unmodifiable(illustrations),
    );
  }

  /// 拿掉段落裡的插圖記號，記下每張圖落在第幾段的第幾個字。圖在段首的
  /// 空白（縮排）之內算段落開頭，在段尾空白之後算段落結尾；只剩空白的段
  /// 落不成段，圖算在下一段開頭（後面沒有段落時 paragraph 等於段落數）。
  static ({
    List<String> paragraphs,
    List<({int paragraph, int offset})> positions,
  })
  _placeIllustrations(List<String> rawParagraphs) {
    const mark = ReaderV2IllustrationMarkers.placeholder;
    final paragraphs = <String>[];
    final positions = <({int paragraph, int offset})>[];
    var pendingBefore = 0;
    for (final raw in rawParagraphs) {
      if (!raw.contains(mark)) {
        for (var i = 0; i < pendingBefore; i += 1) {
          positions.add((paragraph: paragraphs.length, offset: 0));
        }
        pendingBefore = 0;
        paragraphs.add(raw);
        continue;
      }
      final cleaned = raw.replaceAll(mark, '');
      if (cleaned.replaceAll('　', '').trim().isEmpty) {
        pendingBefore += mark.allMatches(raw).length;
        continue;
      }
      for (var i = 0; i < pendingBefore; i += 1) {
        positions.add((paragraph: paragraphs.length, offset: 0));
      }
      pendingBefore = 0;
      final leading =
          cleaned.length - cleaned.replaceFirst(_leadingSpace, '').length;
      final trailingStart = cleaned.replaceFirst(_trailingSpace, '').length;
      var removed = 0;
      for (var i = 0; i < raw.length; i += 1) {
        if (raw[i] != mark) continue;
        final at = i - removed;
        removed += 1;
        final offset = at <= leading
            ? 0
            : at >= trailingStart
            ? cleaned.length
            : at;
        positions.add((paragraph: paragraphs.length, offset: offset));
      }
      paragraphs.add(cleaned);
    }
    for (var i = 0; i < pendingBefore; i += 1) {
      positions.add((paragraph: paragraphs.length, offset: 0));
    }
    return (paragraphs: paragraphs, positions: positions);
  }

  static final RegExp _leadingSpace = RegExp(r'^[\s　]+');
  static final RegExp _trailingSpace = RegExp(r'[\s　]+$');

  /// 原文切成的段落，和 [ReaderV2Content.fromRaw] 的 [paragraphs] 相同。
  /// 只要段落時用這個：[ReaderV2Content.fromRaw] 還會對整章算雜湊，那只在
  /// 背景做（`reader_v2_content_transformer.dart`）。
  static List<String> paragraphsOf(String rawText) {
    final normalized = normalizeRawText(rawText);
    if (normalized.isEmpty) return const <String>[];
    return normalized
        .split(RegExp(r'\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
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
    if (location.contentHash == target.contentHash) {
      return capture(location: location, content: target);
    }
    final resolved = location.copyWith(
      charOffset: offsetIn(
        location: location,
        displayText: target.displayText,
        contentHash: target.contentHash,
      ),
      clearContentIdentity: true,
    );
    return capture(location: resolved, content: target);
  }

  /// [location] 在另一份正文（[displayText]，身分 [contentHash]）裡是第幾個
  /// 字：同一份照原位置，不同就照前後原文找回同一句，找不到時照長度比例估。
  static int offsetIn({
    required ReaderV2Location location,
    required String displayText,
    required String contentHash,
  }) {
    final text = displayText;
    if (location.contentHash == contentHash) {
      return location.charOffset.clamp(0, text.length).toInt();
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
    return mapped ?? projected;
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
      final matches = _allOccurrences(
        text,
        combined,
      ).map((start) => start + left.length).toList(growable: false);
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
            .convert(after.substring(0, rawOffset), convertType: canonicalType)
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

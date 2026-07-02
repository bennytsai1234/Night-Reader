import 'dart:convert';

import 'package:crypto/crypto.dart';

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

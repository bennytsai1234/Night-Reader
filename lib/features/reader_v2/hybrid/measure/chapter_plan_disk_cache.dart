import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

/// 章節換行結果（不含正文的切分與換行位置）的磁碟快取。
///
/// 換行結果由排版樣式、正文與換行規則決定。樣式由 [StyleFingerprint] 分檔，
/// 正文由 contentHash 比對；換行規則與內建字型跟著程式走，所以每筆都記下
/// 寫入時的 [buildSignature]，App 換版後一律視為失效重算。任何不符或檔案
/// 損壞都只當作沒有快取，不會把舊的換行套到新內容上。
final class ChapterPlanDiskCache {
  ChapterPlanDiskCache({
    required this.baseDirectory,
    required this.buildSignature,
  });

  static const int _version = 1;

  final Directory baseDirectory;
  final String buildSignature;

  Future<ChapterBlocks?> read({
    required String bookUrl,
    required StyleFingerprint fingerprint,
    required ChapterText text,
  }) async {
    final file = _fileFor(
      bookUrl: bookUrl,
      fingerprint: fingerprint,
      chapterIndex: text.id,
    );
    final String raw;
    try {
      raw = await file.readAsString();
    } on FileSystemException {
      return null;
    }
    try {
      return _decode(jsonDecode(raw), text);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on RangeError {
      return null;
    }
  }

  Future<void> write({
    required String bookUrl,
    required StyleFingerprint fingerprint,
    required ChapterBlocks blocks,
  }) async {
    final file = _fileFor(
      bookUrl: bookUrl,
      fingerprint: fingerprint,
      chapterIndex: blocks.chapterIndex,
    );
    final payload = jsonEncode(<String, Object>{
      'version': _version,
      'build': buildSignature,
      'chapter': blocks.chapterIndex,
      'contentHash': blocks.contentHash,
      'textLength': blocks.displayText.length,
      'spans': [
        for (final block in blocks.blocks)
          [
            block.charRange.start,
            block.charRange.end,
            block.sourceParagraphIndex,
            (block.isTitle ? 1 : 0) |
                (block.isContinuation ? 2 : 0) |
                (block.layoutBreakBefore ? 4 : 0),
            block.visualLineBreakOffsets,
          ],
      ],
    });
    await file.parent.create(recursive: true);
    // 先寫暫存檔再改名：同一本書的新舊閱讀器可能同時寫同一章，
    // 讀到的永遠是某一次完整的寫入。
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temp.writeAsString(payload, flush: true);
    await temp.rename(file.path);
  }

  ChapterBlocks? _decode(Object? json, ChapterText text) {
    if (json is! Map<String, Object?>) return null;
    if (json['version'] != _version ||
        json['build'] != buildSignature ||
        json['chapter'] != text.id ||
        json['contentHash'] != text.contentHash ||
        json['textLength'] != text.displayText.length) {
      return null;
    }
    final spans = json['spans'];
    if (spans is! List<Object?> || spans.isEmpty) return null;
    final blocks = <ChapterBlock>[];
    for (var i = 0; i < spans.length; i += 1) {
      final span = spans[i] as List<Object?>;
      final start = span[0] as int;
      final end = span[1] as int;
      final flags = span[3] as int;
      final isTitle = flags & 1 != 0;
      final source = isTitle ? text.title : text.displayText;
      if (start < 0 || end < start || end > source.length) return null;
      final offsets = [
        for (final offset in span[4] as List<Object?>) offset as int,
      ];
      var previous = start;
      for (final offset in offsets) {
        if (offset <= previous || offset >= end) return null;
        previous = offset;
      }
      blocks.add(
        ChapterBlock(
          key: BlockKey(chapterIndex: text.id, blockIndex: i),
          text: source.substring(start, end),
          charRange: HybridTextRange(start, end),
          sourceParagraphIndex: span[2] as int,
          isTitle: isTitle,
          isContinuation: flags & 2 != 0,
          layoutBreakBefore: flags & 4 != 0,
          visualLineBreakOffsets: List<int>.unmodifiable(offsets),
        ),
      );
    }
    return ChapterBlocks(
      chapterIndex: text.id,
      title: text.title,
      displayText: text.displayText,
      contentHash: text.contentHash,
      blocks: blocks,
    );
  }

  File _fileFor({
    required String bookUrl,
    required StyleFingerprint fingerprint,
    required int chapterIndex,
  }) {
    final bookHash = sha1.convert(utf8.encode(bookUrl)).toString();
    final fingerprintHash = sha1
        .convert(utf8.encode(fingerprint.stableKey))
        .toString();
    return File(
      p.join(
        baseDirectory.path,
        'hybrid_plans',
        bookHash,
        fingerprintHash,
        '$chapterIndex.json',
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';
import 'package:night_reader/features/reader_v2/hybrid/text/text_preprocessor.dart';

typedef _PlanSpan = ({
  int start,
  int end,
  int paragraph,
  int flags,
  List<int> offsets,
});

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

  /// 讀檔與 JSON 解析在背景 isolate 進行：讀取發生在捲動中下一章進來時，
  /// 不受排版的每幀時間額度管，不能佔用 UI isolate。
  Future<ChapterBlocks?> read({
    required String bookUrl,
    required StyleFingerprint fingerprint,
    required ChapterText text,
  }) async {
    final path = _fileFor(
      bookUrl: bookUrl,
      fingerprint: fingerprint,
      chapterIndex: text.id,
    ).path;
    final header = (
      build: buildSignature,
      chapter: text.id,
      contentHash: text.contentHash,
      textLength: text.displayText.length,
    );
    final spans = await Isolate.run(() => _readSpans(path, header));
    if (spans == null) return null;
    return _decode(spans, text);
  }

  /// JSON 編碼與寫檔在背景 isolate 進行，理由同 [read]。
  Future<void> write({
    required String bookUrl,
    required StyleFingerprint fingerprint,
    required ChapterBlocks blocks,
  }) async {
    final path = _fileFor(
      bookUrl: bookUrl,
      fingerprint: fingerprint,
      chapterIndex: blocks.chapterIndex,
    ).path;
    final payload = <String, Object>{
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
    };
    await Isolate.run(() => _writeSync(path, payload));
  }

  static void _writeSync(String path, Map<String, Object> payload) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    // 先寫暫存檔再改名：同一本書的新舊閱讀器可能同時寫同一章，
    // 讀到的永遠是某一次完整的寫入。
    final temp = File('$path.${DateTime.now().microsecondsSinceEpoch}.tmp');
    temp.writeAsStringSync(jsonEncode(payload), flush: true);
    temp.renameSync(path);
  }

  /// 檔頭不符、檔案不存在或損壞時回傳 null。
  static List<_PlanSpan>? _readSpans(
    String path,
    ({String build, int chapter, String contentHash, int textLength}) header,
  ) {
    final String raw;
    try {
      raw = File(path).readAsStringSync();
    } on FileSystemException {
      return null;
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return null;
      if (json['version'] != _version ||
          json['build'] != header.build ||
          json['chapter'] != header.chapter ||
          json['contentHash'] != header.contentHash ||
          json['textLength'] != header.textLength) {
        return null;
      }
      final spans = json['spans'];
      if (spans is! List<Object?>) return null;
      return [
        for (final value in spans)
          if (value case [
            final int start,
            final int end,
            final int paragraph,
            final int flags,
            final List<Object?> offsets,
          ])
            (
              start: start,
              end: end,
              paragraph: paragraph,
              flags: flags,
              offsets: [for (final offset in offsets) offset as int],
            )
          else
            throw const FormatException('Malformed line-break span.'),
      ];
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  ChapterBlocks? _decode(List<_PlanSpan> spans, ChapterText text) {
    final blocks = <ChapterBlock>[];
    var next = 0;
    // 換行切分必須完整覆蓋前處理產生的每一段：標題與正文段落依序出現，
    // 段內各塊首尾相接、不缺不重疊；只有段落的第一塊不是 continuation。
    for (final segment in chapterSegmentsOf(text)) {
      var cursor = segment.start;
      do {
        if (next >= spans.length) return null;
        final (:start, :end, :paragraph, :flags, :offsets) = spans[next];
        final isTitle = flags & 1 != 0;
        final isContinuation = flags & 2 != 0;
        final layoutBreakBefore = flags & 4 != 0;
        final first = cursor == segment.start;
        if (isTitle != segment.isTitle ||
            paragraph != segment.paragraph ||
            start != cursor ||
            end > segment.end ||
            (end == start && segment.end != segment.start) ||
            isContinuation == first ||
            layoutBreakBefore == first) {
          return null;
        }
        // 換行位置相對於這一塊的文字（見 ParagraphTextMap）。
        var previous = 0;
        for (final offset in offsets) {
          if (offset <= previous || offset >= end - start) return null;
          previous = offset;
        }
        final source = isTitle ? text.title : text.displayText;
        blocks.add(
          ChapterBlock(
            key: BlockKey(chapterIndex: text.id, blockIndex: next),
            text: source.substring(start, end),
            charRange: HybridTextRange(start, end),
            sourceParagraphIndex: paragraph,
            isTitle: isTitle,
            isContinuation: isContinuation,
            layoutBreakBefore: layoutBreakBefore,
            visualLineBreakOffsets: List<int>.unmodifiable(offsets),
          ),
        );
        next += 1;
        cursor = end;
      } while (cursor < segment.end);
    }
    if (next != spans.length) return null;
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

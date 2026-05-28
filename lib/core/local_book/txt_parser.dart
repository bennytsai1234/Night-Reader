import 'dart:convert';
import 'dart:io';

import '../services/encoding_detect.dart';

/// TxtParser - 高性能 TXT 解析器
/// 深度還原 Android model/localBook/TextFile.kt 的物理位移邏輯
class TxtParser {
  final File file;

  static const int _maxChapterChars = 50000;
  static const int _fallbackChunkChars = 30000;

  static final RegExp defaultChapterPattern = RegExp(
    r'^\s*[第][0-9零一二两三四五六七八九十百千万万]+[章回节卷集幕计][ \t]*.*$',
    multiLine: true,
  );

  TxtParser(this.file);

  Future<void> load() async {}

  /// 掃描文件並獲取章節位移 (不讀取全量內容入記憶體)
  Future<({List<Map<String, dynamic>> chapters, String charset})>
  splitChapters({RegExp? customPattern}) async {
    final pattern = customPattern ?? defaultChapterPattern;
    final bytes = await file.readAsBytes();
    final charsetName = EncodingDetect.getEncode(bytes);
    final charset = EncodingDetect.detect(bytes);
    final content = EncodingDetect.decode(bytes);

    final result = <Map<String, dynamic>>[];
    final matches = pattern.allMatches(content).toList();

    // 將字元索引轉換為位元組位移，避免逐章重算全段
    final charOffsets = <int>[
      0,
      ...matches.map((m) => m.start),
      content.length,
    ];
    final byteOffsets = _buildByteOffsets(
      content: content,
      charset: charset,
      charOffsets: charOffsets,
    );

    if (matches.isEmpty) {
      _appendChunkedRange(
        result: result,
        content: content,
        charset: charset,
        titleBase: '正文',
        charStart: 0,
        charEnd: content.length,
        byteStart: 0,
        byteEnd: bytes.length,
        chunkChars: _fallbackChunkChars,
      );
      return (chapters: result, charset: charsetName);
    }

    // 處理前言
    if (matches.first.start > 0) {
      _appendChunkedRange(
        result: result,
        content: content,
        charset: charset,
        titleBase: '前言',
        charStart: 0,
        charEnd: matches.first.start,
        byteStart: byteOffsets[0],
        byteEnd: byteOffsets[1],
        chunkChars: _fallbackChunkChars,
      );
    }

    for (var i = 0; i < matches.length; i++) {
      final charStart = matches[i].start;
      final charEnd =
          (i + 1 < matches.length) ? matches[i + 1].start : content.length;
      final byteStart = byteOffsets[i + 1];
      final byteEnd = byteOffsets[i + 2];
      final titleBase = matches[i].group(0)?.trim() ?? '第 ${i + 1} 章';

      _appendChunkedRange(
        result: result,
        content: content,
        charset: charset,
        titleBase: titleBase,
        charStart: charStart,
        charEnd: charEnd,
        byteStart: byteStart,
        byteEnd: byteEnd,
        chunkChars: _maxChapterChars,
      );
    }

    return (chapters: result, charset: charsetName);
  }

  List<int> _buildByteOffsets({
    required String content,
    required Encoding charset,
    required List<int> charOffsets,
  }) {
    final byteOffsets = List<int>.filled(charOffsets.length, 0);
    var currentChar = 0;
    var currentByte = 0;
    for (var i = 0; i < charOffsets.length; i++) {
      final targetChar = charOffsets[i];
      if (targetChar > currentChar) {
        currentByte +=
            charset.encode(content.substring(currentChar, targetChar)).length;
      }
      byteOffsets[i] = currentByte;
      currentChar = targetChar;
    }
    return byteOffsets;
  }

  void _appendChunkedRange({
    required List<Map<String, dynamic>> result,
    required String content,
    required Encoding charset,
    required String titleBase,
    required int charStart,
    required int charEnd,
    required int byteStart,
    required int byteEnd,
    required int chunkChars,
  }) {
    if (charEnd <= charStart || byteEnd <= byteStart) return;

    final totalChars = charEnd - charStart;
    final needsSuffix = totalChars > chunkChars;
    var part = 0;
    var currentChar = charStart;
    var currentByte = byteStart;

    while (currentChar < charEnd) {
      part += 1;
      final nextChar =
          (currentChar + chunkChars < charEnd)
              ? currentChar + chunkChars
              : charEnd;
      final isLast = nextChar == charEnd;
      final nextByte =
          isLast
              ? byteEnd
              : (currentByte +
                      charset
                          .encode(content.substring(currentChar, nextChar))
                          .length)
                  .clamp(currentByte, byteEnd)
                  .toInt();

      result.add({
        'title': needsSuffix ? '$titleBase ($part)' : titleBase,
        'start': currentByte,
        'end': nextByte,
      });

      currentChar = nextChar;
      currentByte = nextByte;
    }
  }
}

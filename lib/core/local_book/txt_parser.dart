import 'dart:io';
import 'dart:typed_data';

import '../services/encoding_detect.dart';

/// TxtParser - 高性能 TXT 解析器
/// 深度還原 Android model/localBook/TextFile.kt 的物理位移邏輯
class TxtParser {
  final File file;

  /// 一章最多幾字，超過就再切開；EPUB 目錄太粗時也照這個切。
  static const int maxChapterChars = 50000;
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
    final bytes = await file.readAsBytes();
    final charsetName = EncodingDetect.getEncode(bytes);
    final content = EncodingDetect.decode(bytes);
    final bomLength = EncodingDetect.bomLength(bytes);

    final spans = splitText(content, pattern: customPattern);
    // 只映射章界與實際切塊端點，避免為大型書籍的每個 code unit 建立
    // 一筆位移資料。
    final byteOffsets = _buildByteOffsets(
      bytes: bytes,
      content: content,
      charsetName: charsetName,
      charOffsets: [
        0,
        content.length,
        for (final span in spans) ...[span.start, span.end],
      ],
      initialByteOffset: bomLength,
    );

    final result = <Map<String, dynamic>>[];
    for (final span in spans) {
      final byteStart = byteOffsets[span.start];
      final byteEnd = byteOffsets[span.end];
      if (byteStart == null || byteEnd == null || byteEnd <= byteStart) {
        continue;
      }
      result.add({'title': span.title, 'start': byteStart, 'end': byteEnd});
    }
    return (chapters: result, charset: charsetName);
  }

  /// 依章名規則切開 [content]，範圍以 UTF-16 code unit 計。
  ///
  /// 第一個章名之前的文字叫 [leadTitle]；整段都沒有章名時叫
  /// [untitledTitle]。太長的章再切成「章名 (1)」「章名 (2)」…：有章名的
  /// 每段最多 [maxChapterChars] 字，沒有章名的每段 3 萬字。
  static List<({String title, int start, int end})> splitText(
    String content, {
    RegExp? pattern,
    String leadTitle = '前言',
    String untitledTitle = '正文',
  }) {
    final result = <({String title, int start, int end})>[];
    final matches = (pattern ?? defaultChapterPattern)
        .allMatches(content)
        .toList();
    if (matches.isEmpty) {
      _appendChunks(
        result,
        content,
        untitledTitle,
        0,
        content.length,
        _fallbackChunkChars,
      );
      return result;
    }

    if (matches.first.start > 0) {
      _appendChunks(
        result,
        content,
        leadTitle,
        0,
        matches.first.start,
        _fallbackChunkChars,
      );
    }
    for (var i = 0; i < matches.length; i++) {
      _appendChunks(
        result,
        content,
        matches[i].group(0)?.trim() ?? '第 ${i + 1} 章',
        matches[i].start,
        i + 1 < matches.length ? matches[i + 1].start : content.length,
        maxChapterChars,
      );
    }
    return result;
  }

  Map<int, int> _buildByteOffsets({
    required Uint8List bytes,
    required String content,
    required String charsetName,
    required List<int> charOffsets,
    required int initialByteOffset,
  }) {
    final sortedOffsets = charOffsets.toSet().toList()..sort();
    final exactOffsets = _buildExactByteOffsets(
      bytes: bytes,
      charsetName: charsetName,
      initialByteOffset: initialByteOffset,
      expectedCodeUnits: content.length,
      targetCharOffsets: sortedOffsets,
    );
    if (exactOffsets != null) return exactOffsets;

    final byteOffsets = <int, int>{};
    var currentChar = 0;
    var currentByte = initialByteOffset;
    for (final targetChar in sortedOffsets) {
      if (targetChar > currentChar) {
        currentByte += EncodingDetect.encodeWithCharset(
          content.substring(currentChar, targetChar),
          charsetName,
        ).length;
      }
      byteOffsets[targetChar] = currentByte;
      currentChar = targetChar;
    }
    return byteOffsets;
  }

  Map<int, int>? _buildExactByteOffsets({
    required Uint8List bytes,
    required String charsetName,
    required int initialByteOffset,
    required int expectedCodeUnits,
    required List<int> targetCharOffsets,
  }) {
    final normalized = charsetName.toUpperCase().replaceAll('_', '-');
    if (targetCharOffsets.any(
      (offset) => offset < 0 || offset > expectedCodeUnits,
    )) {
      return null;
    }
    final targets = targetCharOffsets.toSet();
    final offsets = <int, int>{};
    var codeUnits = 0;
    var index = initialByteOffset;
    if (targets.contains(0)) offsets[0] = initialByteOffset;

    void advance(int byteLength, int producedCodeUnits) {
      index += byteLength;
      for (var i = 0; i < producedCodeUnits; i++) {
        codeUnits += 1;
        if (targets.contains(codeUnits)) offsets[codeUnits] = index;
      }
    }

    Map<int, int>? completedOffsets() {
      if (codeUnits != expectedCodeUnits || offsets.length != targets.length) {
        return null;
      }
      return offsets;
    }

    if (normalized == 'UTF-16LE' ||
        normalized == 'UTF16LE' ||
        normalized == 'UTF-16BE' ||
        normalized == 'UTF16BE') {
      while (index + 1 < bytes.length) {
        advance(2, 1);
      }
      if (index < bytes.length) advance(bytes.length - index, 1);
      return completedOffsets();
    }

    if (normalized == 'UTF-8' || normalized == 'UTF8') {
      while (index < bytes.length) {
        final unit = _utf8UnitAt(bytes, index);
        advance(unit.byteLength, unit.codeUnits);
      }
      return completedOffsets();
    }

    if (normalized == 'GBK' ||
        normalized == 'GB2312' ||
        normalized == 'GB18030') {
      while (index < bytes.length) {
        final first = bytes[index];
        if (first <= 0x7F || index + 1 >= bytes.length) {
          advance(1, 1);
        } else {
          advance(2, 1);
        }
      }
      return completedOffsets();
    }

    return null;
  }

  ({int byteLength, int codeUnits}) _utf8UnitAt(Uint8List bytes, int index) {
    final first = bytes[index];
    if (first <= 0x7F) {
      return (byteLength: 1, codeUnits: 1);
    }

    if (first >= 0xC2 && first <= 0xDF) {
      if (_isUtf8Continuation(bytes, index + 1)) {
        return (byteLength: 2, codeUnits: 1);
      }
      return (byteLength: 1, codeUnits: 1);
    }

    if (first >= 0xE0 && first <= 0xEF) {
      if (!_isValidUtf8SecondByte(bytes, index, first)) {
        return (byteLength: 1, codeUnits: 1);
      }
      if (_isUtf8Continuation(bytes, index + 2)) {
        return (byteLength: 3, codeUnits: 1);
      }
      return (byteLength: 2, codeUnits: 1);
    }

    if (first >= 0xF0 && first <= 0xF4) {
      if (!_isValidUtf8SecondByte(bytes, index, first)) {
        return (byteLength: 1, codeUnits: 1);
      }
      if (!_isUtf8Continuation(bytes, index + 2)) {
        return (byteLength: 2, codeUnits: 1);
      }
      if (_isUtf8Continuation(bytes, index + 3)) {
        return (byteLength: 4, codeUnits: 2);
      }
      return (byteLength: 3, codeUnits: 1);
    }

    return (byteLength: 1, codeUnits: 1);
  }

  bool _isValidUtf8SecondByte(Uint8List bytes, int index, int first) {
    if (index + 1 >= bytes.length) return false;
    final second = bytes[index + 1];
    if (first == 0xE0) return second >= 0xA0 && second <= 0xBF;
    if (first == 0xED) return second >= 0x80 && second <= 0x9F;
    if (first == 0xF0) return second >= 0x90 && second <= 0xBF;
    if (first == 0xF4) return second >= 0x80 && second <= 0x8F;
    return second >= 0x80 && second <= 0xBF;
  }

  bool _isUtf8Continuation(Uint8List bytes, int index) {
    return index < bytes.length && bytes[index] >= 0x80 && bytes[index] <= 0xBF;
  }

  static void _appendChunks(
    List<({String title, int start, int end})> result,
    String content,
    String titleBase,
    int charStart,
    int charEnd,
    int chunkChars,
  ) {
    if (charEnd <= charStart) return;
    final needsSuffix = charEnd - charStart > chunkChars;
    var part = 0;
    var currentChar = charStart;
    while (currentChar < charEnd) {
      part += 1;
      var nextChar = currentChar + chunkChars < charEnd
          ? currentChar + chunkChars
          : charEnd;
      nextChar = _safeChunkEnd(content, currentChar, nextChar, charEnd);
      result.add((
        title: needsSuffix ? '$titleBase ($part)' : titleBase,
        start: currentChar,
        end: nextChar,
      ));
      currentChar = nextChar;
    }
  }

  static int _safeChunkEnd(String text, int start, int end, int limit) {
    if (end <= start || end >= limit) return end;
    final previous = text.codeUnitAt(end - 1);
    final next = text.codeUnitAt(end);
    final splitsSurrogatePair =
        previous >= 0xD800 &&
        previous <= 0xDBFF &&
        next >= 0xDC00 &&
        next <= 0xDFFF;
    return splitsSurrogatePair ? end + 1 : end;
  }
}

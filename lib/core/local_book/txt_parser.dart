import 'dart:io';
import 'dart:typed_data';

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
    final content = EncodingDetect.decode(bytes);
    final bomLength = EncodingDetect.bomLength(bytes);

    final result = <Map<String, dynamic>>[];
    final matches = pattern.allMatches(content).toList();

    // 只映射章界與實際切塊端點，避免為大型書籍的每個 code unit 建立
    // 一筆位移資料。
    final charOffsets = <int>{
      0,
      ...matches.map((m) => m.start),
      content.length,
    };
    if (matches.isEmpty) {
      _addChunkCharOffsets(
        charOffsets,
        content: content,
        charStart: 0,
        charEnd: content.length,
        chunkChars: _fallbackChunkChars,
      );
    } else {
      if (matches.first.start > 0) {
        _addChunkCharOffsets(
          charOffsets,
          content: content,
          charStart: 0,
          charEnd: matches.first.start,
          chunkChars: _fallbackChunkChars,
        );
      }
      for (var i = 0; i < matches.length; i++) {
        _addChunkCharOffsets(
          charOffsets,
          content: content,
          charStart: matches[i].start,
          charEnd:
              i + 1 < matches.length ? matches[i + 1].start : content.length,
          chunkChars: _maxChapterChars,
        );
      }
    }
    final byteOffsets = _buildByteOffsets(
      bytes: bytes,
      content: content,
      charsetName: charsetName,
      charOffsets: charOffsets.toList(growable: false),
      initialByteOffset: bomLength,
    );

    if (matches.isEmpty) {
      _appendChunkedRange(
        result: result,
        content: content,
        titleBase: '正文',
        charStart: 0,
        charEnd: content.length,
        byteOffsets: byteOffsets,
        chunkChars: _fallbackChunkChars,
      );
      return (chapters: result, charset: charsetName);
    }

    // 處理前言
    if (matches.first.start > 0) {
      _appendChunkedRange(
        result: result,
        content: content,
        titleBase: '前言',
        charStart: 0,
        charEnd: matches.first.start,
        byteOffsets: byteOffsets,
        chunkChars: _fallbackChunkChars,
      );
    }

    for (var i = 0; i < matches.length; i++) {
      final charStart = matches[i].start;
      final charEnd =
          (i + 1 < matches.length) ? matches[i + 1].start : content.length;
      final titleBase = matches[i].group(0)?.trim() ?? '第 ${i + 1} 章';

      _appendChunkedRange(
        result: result,
        content: content,
        titleBase: titleBase,
        charStart: charStart,
        charEnd: charEnd,
        byteOffsets: byteOffsets,
        chunkChars: _maxChapterChars,
      );
    }

    return (chapters: result, charset: charsetName);
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
        currentByte +=
            EncodingDetect.encodeWithCharset(
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

  void _appendChunkedRange({
    required List<Map<String, dynamic>> result,
    required String content,
    required String titleBase,
    required int charStart,
    required int charEnd,
    required Map<int, int> byteOffsets,
    required int chunkChars,
  }) {
    final byteStart = byteOffsets[charStart];
    final byteEnd = byteOffsets[charEnd];
    if (byteStart == null || byteEnd == null) return;
    if (charEnd <= charStart || byteEnd <= byteStart) return;

    final totalChars = charEnd - charStart;
    final needsSuffix = totalChars > chunkChars;
    var part = 0;
    var currentChar = charStart;
    var currentByte = byteStart;

    while (currentChar < charEnd) {
      part += 1;
      var nextChar =
          (currentChar + chunkChars < charEnd)
              ? currentChar + chunkChars
              : charEnd;
      nextChar = _safeChunkEnd(content, currentChar, nextChar, charEnd);
      final nextByte = byteOffsets[nextChar];
      if (nextByte == null) return;

      result.add({
        'title': needsSuffix ? '$titleBase ($part)' : titleBase,
        'start': currentByte,
        'end': nextByte,
      });

      currentChar = nextChar;
      currentByte = nextByte;
    }
  }

  void _addChunkCharOffsets(
    Set<int> offsets, {
    required String content,
    required int charStart,
    required int charEnd,
    required int chunkChars,
  }) {
    if (charEnd <= charStart) return;
    offsets
      ..add(charStart)
      ..add(charEnd);
    var currentChar = charStart;
    while (currentChar < charEnd) {
      var nextChar =
          currentChar + chunkChars < charEnd
              ? currentChar + chunkChars
              : charEnd;
      nextChar = _safeChunkEnd(content, currentChar, nextChar, charEnd);
      offsets.add(nextChar);
      currentChar = nextChar;
    }
  }

  int _safeChunkEnd(String text, int start, int end, int limit) {
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

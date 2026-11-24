import 'dart:io';
import 'dart:typed_data';

import '../utils/big5.dart';
import '../utils/encoding_detect.dart';

/// TxtParser - 高性能 TXT 解析器
/// 深度還原 Android model/localBook/TextFile.kt 的物理位移邏輯
class TxtParser {
  final File file;

  /// 一章最多幾字，超過就再切開；EPUB 目錄太粗時也照這個切。
  static const int maxChapterChars = 50000;
  static const int _fallbackChunkChars = 30000;

  /// 挑目錄規則時試檔案前多少位元組（Legado `TextFile.bufferSize`）。
  static const int _tocSampleBytes = 512000;

  /// EPUB 目錄太粗、一章超過 [maxChapterChars] 字時再切用的章名規則
  /// （ADR 0032）。這套切法（[splitEpubChapter]）是 `EpubParser.textVersion`
  /// 2 的一部分：轉好的文字檔不見時會重轉，切出來要和當初一樣，資料庫裡的
  /// 章節與閱讀進度才對得上；要改得一起加 textVersion，並把閱讀位置帶到新
  /// 的章節。
  static final RegExp _epubChapterPattern = RegExp(
    r'^\s*[第][0-9零一二两三四五六七八九十百千万万]+[章回节卷集幕计][ \t]*.*$',
    multiLine: true,
  );

  /// Legado 內建、預設啟用的 TXT 目錄規則（`assets/defaultData/txtTocRule.json`），
  /// 照它的排序。另外打開「目录(古典、轻小说备用)」：它只比「目录」多認
  /// 「回」「话」「场」，Legado 預設關著時「第一回」的古典小說分不出章。
  static final List<RegExp> tocRules = [
    // 目录(去空白)
    r'(?<=[　\s])(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和]))).{0,30}$',
    // 目录
    r'^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$',
    // 目录(古典、轻小说备用)
    r'^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|话|篇(?!张))).{0,30}$',
    // 数字 分隔符 标题名称
    r'^[ 　\t]{0,4}\d{1,5}[:：,.， 、_—\-].{1,30}$',
    // 大写数字 分隔符 标题名称
    r'^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?)[ 、_—\-].{1,30}$',
    // 正文 标题/序号
    r'^[ 　\t]{0,4}正文[ 　]{1,4}.{0,20}$',
    // Chapter/Section/Part/Episode 序号 标题
    r'^[ 　\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][oO][.、]|[Ee]pisode|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)\s{0,4}\d{1,4}.{0,30}$',
    // 特殊符号 序号 标题
    r'(?<=[\s　])[【〔〖「『〈［\[](?:第|[Cc]hapter)[\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}[章节].{0,20}$',
    // 特殊符号 标题(单个)
    r'(?<=[\s　]{0,4})(?:[☆★✦✧].{1,30}|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$',
    // 章/卷 序号 标题
    r'^[ \t　]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[卷章][\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8})[ 　]{0,4}.{0,30}$',
    // 书名 括号 序号
    r'^[一-龥]{1,20}[ 　\t]{0,4}[(（][\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[)）][ 　\t]{0,4}$',
    // 书名 序号
    r'^[一-龥]{1,20}[ 　\t]{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[ 　\t]{0,4}$',
    // 字数分割 分节阅读
    r'(?<=[ 　\t]{0,4})(?:.{0,15}分[页节章段]阅读[-_ ]|第\s{0,4}[\d零一二两三四五六七八九十百千万]{1,6}\s{0,4}[页节]).{0,30}$',
  ].map((rule) => RegExp(rule, multiLine: true)).toList(growable: false);

  TxtParser(this.file);

  Future<void> load() async {}

  /// 掃描文件並獲取章節位移 (不讀取全量內容入記憶體)
  Future<({List<Map<String, dynamic>> chapters, String charset})>
  splitChapters({RegExp? customPattern}) async {
    final bytes = await file.readAsBytes();
    final charsetName = EncodingDetect.getEncode(bytes);
    final content = EncodingDetect.decode(bytes);
    final bomLength = EncodingDetect.bomLength(bytes);

    final sampleEnd = bytes.length < bomLength + _tocSampleBytes
        ? bytes.length
        : bomLength + _tocSampleBytes;
    final sample = EncodingDetect.decodeWithCharset(
      bytes.sublist(bomLength, sampleEnd),
      charsetName,
    );
    final spans = _split(content, customPattern ?? pickTocRule(sample));
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
      result.add({
        'title': span.title,
        'start': byteStart,
        'end': byteEnd,
        'isVolume': span.isVolume,
      });
    }
    return (chapters: result, charset: charsetName);
  }

  /// 照 Legado 從 [tocRules] 挑一條（`TextFile.getTocRule`）：拿 [sample]
  /// （TXT 是檔案前 512KB）試每一條，數對到幾處（離上一處不到 1000 字的不算），
  /// 挑最多的；一樣多時挑排在前面的。一處都對不到時傳回 null。
  static RegExp? pickTocRule(String sample) {
    RegExp? picked;
    var most = 1;
    for (final rule in tocRules.reversed) {
      var count = 0;
      var last = 0;
      for (final match in rule.allMatches(sample)) {
        if (last == 0 || match.start - last > 1000) {
          count += 1;
          last = match.end;
        }
      }
      if (count >= most) {
        most = count;
        picked = rule;
      }
    }
    return picked;
  }

  /// 依章名規則切開 [content]，範圍以 UTF-16 code unit 計；沒給 [pattern]
  /// 時拿整段照 [pickTocRule] 挑一條。
  ///
  /// 第一個章名之前有字時叫 [leadTitle]，只有空白時併進第一章；整段都沒有
  /// 章名時叫 [untitledTitle]。章名後面直接接下一個章名的（只有一行卷名）
  /// 標成分卷（[isVolume]，同 Legado）。太長的章再切成「章名 (1)」「章名 (2)」
  /// …：有章名的每段 [maxChapterChars] 字，沒有章名的每段 3 萬字，切點
  /// 往後找到換行（[_chunkEnd]）。
  static List<({String title, int start, int end, bool isVolume})> splitText(
    String content, {
    RegExp? pattern,
  }) => _split(content, pattern ?? pickTocRule(content));

  static List<({String title, int start, int end, bool isVolume})> _split(
    String content,
    RegExp? rule,
  ) {
    const leadTitle = '前言';
    const untitledTitle = '正文';
    final result = <({String title, int start, int end, bool isVolume})>[];
    final matches = rule == null
        ? const <RegExpMatch>[]
        : rule.allMatches(content).toList();
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

    final leadBlank = content.substring(0, matches.first.start).trim().isEmpty;
    if (matches.first.start > 0 && !leadBlank) {
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
      final start = i == 0 && leadBlank ? 0 : matches[i].start;
      final end = i + 1 < matches.length
          ? matches[i + 1].start
          : content.length;
      final title = matches[i].group(0)?.trim() ?? '第 ${i + 1} 章';
      if (content.substring(matches[i].end, end).trim().isEmpty) {
        result.add((title: title, start: start, end: end, isVolume: true));
        continue;
      }
      _appendChunks(result, content, title, start, end, maxChapterChars);
    }
    return result;
  }

  /// EPUB 一章太長時照 [_epubChapterPattern] 再切（ADR 0032）：第一個章名
  /// 之前的字叫 [title]，每段 [maxChapterChars] 字、沒有章名時 3 萬字，照字數
  /// 切、不找換行。切法固定，見 [_epubChapterPattern]。
  static List<({String title, int start, int end})> splitEpubChapter(
    String content,
    String title,
  ) {
    final result = <({String title, int start, int end, bool isVolume})>[];
    final matches = _epubChapterPattern.allMatches(content).toList();
    if (matches.isEmpty) {
      _appendChunks(
        result,
        content,
        title,
        0,
        content.length,
        _fallbackChunkChars,
        atLineBreak: false,
      );
    } else {
      if (matches.first.start > 0) {
        _appendChunks(
          result,
          content,
          title,
          0,
          matches.first.start,
          _fallbackChunkChars,
          atLineBreak: false,
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
          atLineBreak: false,
        );
      }
    }
    return [
      for (final span in result)
        (title: span.title, start: span.start, end: span.end),
    ];
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

    if (Big5.names.contains(normalized)) {
      while (index < bytes.length) {
        advance(Big5.byteLengthAt(bytes, index), 1);
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
    List<({String title, int start, int end, bool isVolume})> result,
    String content,
    String titleBase,
    int charStart,
    int charEnd,
    int chunkChars, {
    bool atLineBreak = true,
  }) {
    if (charEnd <= charStart) return;
    final needsSuffix = charEnd - charStart > chunkChars;
    var part = 0;
    var currentChar = charStart;
    while (currentChar < charEnd) {
      part += 1;
      final nextChar = currentChar + chunkChars >= charEnd
          ? charEnd
          : _chunkEnd(
              content,
              currentChar + chunkChars,
              charEnd,
              atLineBreak ? chunkChars : 0,
            );
      result.add((
        title: needsSuffix ? '$titleBase ($part)' : titleBase,
        start: currentChar,
        end: nextChar,
        isVolume: false,
      ));
      currentChar = nextChar;
    }
  }

  /// 切點從 [from] 往後找到換行，切在換行之後，下一塊從一段的開頭開始
  /// （同 Legado `TextFile.analyze`）。往後 [window] 字內都沒有換行（整本
  /// 沒有分段的檔；[window] 是 0 時不找）就切在 [from]，只避開把一個字
  /// 切成兩半；過了 [limit] 就到 [limit]。
  static int _chunkEnd(String text, int from, int limit, int window) {
    final bound = from + window < limit ? from + window : limit;
    for (var i = from; i < bound; i += 1) {
      if (text.codeUnitAt(i) == 0x0A) return i + 1 >= limit ? limit : i + 1;
    }
    final previous = text.codeUnitAt(from - 1);
    final next = text.codeUnitAt(from);
    final splitsSurrogatePair =
        previous >= 0xD800 &&
        previous <= 0xDBFF &&
        next >= 0xDC00 &&
        next <= 0xDFFF;
    return splitsSurrogatePair ? from + 1 : from;
  }
}

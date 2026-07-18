import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:night_reader/core/constant/app_pattern.dart';
import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/replace_rule.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/core/services/japanese_text_detector.dart';

import 'reader_v2_processed_chapter.dart';

/// 在內容轉換階段執行文字排版正規化。
///
/// 無開關、恆開（2026-07-18 內化決策）：所有規則都以 CJK 脈絡判定自我防護，
/// 中文語境下把半形/歧義寬度標點統一為佔滿全形格的碼位，讓格線對齊；
/// 純西文脈絡（英文句、數字、URL）一律原樣保留。
///
/// 這裡只處理文字本身；不要在 [ReaderV2Content.fromRaw] 之後再改字，否則
/// displayText 的 TTS、進度錨點與 contentHash 會失去同一座標系。
///
/// [preserveCjkSpaces] 供標題使用：章節標題的空格是刻意的結構分隔
/// （「第一章 起點」），不是來源雜訊；內文才需要為格線刪空格。
String normalizeTypography(String input, {bool preserveCjkSpaces = false}) {
  if (input.isEmpty) return input;

  final cleaned = StringBuffer();
  final lineNormalized = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (final rune in lineNormalized.runes) {
    if (rune == 0x0A) {
      cleaned.write('\n');
      continue;
    }
    if (rune == 0x09 || rune == 0x00A0 || rune == 0x3000) {
      cleaned.write(' ');
      continue;
    }
    if (_isInvisibleTypographyRune(rune) || _isControlRune(rune)) {
      continue;
    }
    cleaned.write(String.fromCharCode(rune));
  }

  var result = cleaned
      .toString()
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r' +'), ' '))
      .join('\n');
  result = _normalizeEllipsis(result);
  result = _normalizeDashes(result);
  result = _normalizeCjkPunctuation(result);
  result = _normalizeAmbiguousWidthPunctuation(result);
  result = _normalizePairedQuotes(result);
  result = _normalizePairedSingleQuotes(result);
  result = _normalizeBrackets(result);
  result = _mapCjkOnlyPunctuation(result);
  if (!preserveCjkSpaces) {
    result = _removeCjkSpaces(result);
  }
  return result;
}

bool _isInvisibleTypographyRune(int rune) {
  return rune == 0x200B || // ZERO WIDTH SPACE
      rune == 0x200C || // ZERO WIDTH NON-JOINER
      rune == 0x200D || // ZERO WIDTH JOINER
      rune == 0xFEFF; // ZERO WIDTH NO-BREAK SPACE / BOM
}

bool _isControlRune(int rune) {
  if (rune == 0x09 || rune == 0x0A) return false;
  return (rune >= 0x00 && rune <= 0x1F) || (rune >= 0x7F && rune <= 0x9F);
}

String _normalizeEllipsis(String input) {
  final runes = input.runes.toList(growable: false);
  final output = StringBuffer();
  for (var index = 0; index < runes.length; index += 1) {
    final rune = runes[index];
    if (_isEllipsisDot(rune)) {
      var end = index + 1;
      while (end < runes.length && _isEllipsisDot(runes[end])) {
        end += 1;
      }
      if (end - index >= 3) {
        output.write('……');
        index = end - 1;
        continue;
      }
    }
    if (rune == 0x2026 || rune == 0x22EF) {
      output.write('……');
      if (index + 1 < runes.length &&
          (runes[index + 1] == 0x2026 || runes[index + 1] == 0x22EF)) {
        index += 1;
      }
      continue;
    }
    output.write(String.fromCharCode(rune));
  }
  return output.toString();
}

bool _isEllipsisDot(int rune) {
  return rune == 0x2E || rune == 0xFF0E || rune == 0x3002;
}

/// 破折號統一為 U+2014（NightReaderPunct 字型保證滿版一格、連排無縫）。
///
/// - `―`（U+2015）、`─`（U+2500 製表線，網文常拿來當破折號）→ `—`
/// - CJK 脈絡下的 `--` 連跑（2+ 個 ASCII hyphen）→ `——`
/// - CJK 脈絡下的 `–`（U+2013）→ `—`；數字區間（1–5）不動
/// - 既有 `—` 連跑保持原樣（寬度由字型解決，不強改字數）
String _normalizeDashes(String input) {
  final runes = input.runes.toList(growable: false);
  final output = StringBuffer();
  for (var index = 0; index < runes.length; index += 1) {
    final rune = runes[index];
    if (rune == 0x2015 || rune == 0x2500) {
      output.write('—');
      continue;
    }
    if (rune == 0x2D) {
      var end = index + 1;
      while (end < runes.length && runes[end] == 0x2D) {
        end += 1;
      }
      final runLength = end - index;
      final previous = index > 0 ? runes[index - 1] : null;
      final next = end < runes.length ? runes[end] : null;
      if (runLength >= 2 &&
          (_isCjkContextRune(previous) || _isCjkContextRune(next))) {
        output.write('——');
        index = end - 1;
        continue;
      }
      output.write('-' * runLength);
      index = end - 1;
      continue;
    }
    if (rune == 0x2013) {
      final previous = index > 0 ? runes[index - 1] : null;
      final next = index + 1 < runes.length ? runes[index + 1] : null;
      if (_isCjkContextRune(previous) || _isCjkContextRune(next)) {
        output.write('—');
        continue;
      }
    }
    output.write(String.fromCharCode(rune));
  }
  return output.toString();
}

String _normalizeCjkPunctuation(String input) {
  const replacements = <int, String>{
    0x2C: '，', // comma
    0x2E: '。', // full stop
    0x21: '！', // exclamation
    0x3F: '？', // question
    0x3B: '；', // semicolon
    0x3A: '：', // colon
    0x7E: '～', // tilde（「喂~」→「喂～」）
  };
  final runes = input.runes.toList(growable: false);
  final output = StringBuffer();
  for (var index = 0; index < runes.length; index += 1) {
    final replacement = replacements[runes[index]];
    if (replacement == null) {
      output.write(String.fromCharCode(runes[index]));
      continue;
    }
    final previous = _neighborRune(runes, index, -1);
    final next = _neighborRune(runes, index, 1);
    final hasCjkSide = _isCjkRune(previous) || _isCjkRune(next);
    final hasNumericSide =
        _isAsciiOrFullWidthDigit(previous) || _isAsciiOrFullWidthDigit(next);
    output.write(
      hasCjkSide && !hasNumericSide
          ? replacement
          : String.fromCharCode(runes[index]),
    );
  }
  return output.toString();
}

int? _neighborRune(List<int> runes, int index, int direction) {
  var cursor = index + direction;
  while (cursor >= 0 && cursor < runes.length) {
    final rune = runes[cursor];
    if (rune == 0x0A) return null;
    if (rune != 0x20) return rune;
    cursor += direction;
  }
  return null;
}

/// 歧義寬度標點轉 CJK 專屬碼位。
///
/// 彎引號（U+201C/201D/2018/2019）與間隔號（U+00B7/U+2027）屬東亞歧義
/// 寬度字元：Android 字型回退鏈逐字取第一個有字形的字型，這些碼位會
/// 命中 Roboto 的西文窄字形而非 CJK 字型，因此不佔一格、與漢字不同寬
/// （`fwid` 只作用於有 OpenType 半形→全形對映的字形，Roboto 不支援）。
/// 轉成 Roboto 沒有字形的 CJK 專屬碼位（「」『』・）後，回退鏈必然落到
/// CJK 字型、佔滿一格。
String _normalizeAmbiguousWidthPunctuation(String input) {
  final runes = input.runes.toList(growable: false);
  final output = List<String>.generate(
    runes.length,
    (index) => String.fromCharCode(runes[index]),
    growable: false,
  );
  _convertCurlyQuotePairs(
    runes,
    output,
    open: 0x201C,
    close: 0x201D,
    openReplacement: '「',
    closeReplacement: '」',
  );
  _convertCurlyQuotePairs(
    runes,
    output,
    open: 0x2018,
    close: 0x2019,
    openReplacement: '『',
    closeReplacement: '』',
  );
  for (var index = 0; index < runes.length; index += 1) {
    final rune = runes[index];
    if (rune != 0xB7 && rune != 0x2027) continue;
    final previous = index > 0 ? runes[index - 1] : null;
    final next = index + 1 < runes.length ? runes[index + 1] : null;
    if (_isCjkRune(previous) && _isCjkRune(next)) {
      output[index] = '・';
    }
  }
  return output.join();
}

/// 彎引號成對轉換：開/收一起轉，避免逐字元判斷在 `他說“Hello”` 這類
/// 案例只轉一邊而破對。不成對（落單）的引號原樣保留；純西文脈絡的
/// 引號對（內文與外側鄰字皆無 CJK）也原樣保留。
void _convertCurlyQuotePairs(
  List<int> runes,
  List<String> output, {
  required int open,
  required int close,
  required String openReplacement,
  required String closeReplacement,
}) {
  var index = 0;
  while (index < runes.length) {
    if (runes[index] != open) {
      index += 1;
      continue;
    }
    var closeIndex = -1;
    var cursor = index + 1;
    for (; cursor < runes.length; cursor += 1) {
      final rune = runes[cursor];
      if (rune == open) break; // 收尾前又開新引號：放棄目前這個開引號
      if (rune == close && !_isApostropheRune(runes, cursor, close)) {
        closeIndex = cursor;
        break;
      }
    }
    if (closeIndex < 0) {
      index = cursor; // 從中斷點（可能是新的開引號）繼續
      continue;
    }
    if (_quotePairHasCjkContext(runes, index, closeIndex)) {
      output[index] = openReplacement;
      output[closeIndex] = closeReplacement;
    }
    index = closeIndex + 1;
  }
}

/// `’` 夾在拉丁字母/數字之間是撇號（don’t、it’s），不當作引號收尾。
bool _isApostropheRune(List<int> runes, int index, int close) {
  if (close != 0x2019) return false;
  final previous = index > 0 ? runes[index - 1] : null;
  final next = index + 1 < runes.length ? runes[index + 1] : null;
  return _isLatinLetterOrDigit(previous) && _isLatinLetterOrDigit(next);
}

bool _isLatinLetterOrDigit(int? rune) {
  if (rune == null) return false;
  return (rune >= 0x30 && rune <= 0x39) ||
      (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A);
}

bool _quotePairHasCjkContext(List<int> runes, int openIndex, int closeIndex) {
  for (var cursor = openIndex + 1; cursor < closeIndex; cursor += 1) {
    if (_isCjkContextRune(runes[cursor])) return true;
  }
  return _isCjkContextRune(_neighborRune(runes, openIndex, -1)) ||
      _isCjkContextRune(_neighborRune(runes, closeIndex, 1));
}

/// CJK 脈絡字元：漢字之外也涵蓋 CJK 標點/全形區段與常見中文標點
/// （`“……”`、`“——”他說` 這類引號內只有標點的段落也要能判定為中文脈絡）。
bool _isCjkContextRune(int? rune) {
  if (rune == null) return false;
  if (_isCjkRune(rune)) return true;
  return (rune >= 0x3000 && rune <= 0x303F) ||
      (rune >= 0xFF00 && rune <= 0xFF60) ||
      rune == 0x2014 ||
      rune == 0x2026 ||
      rune == 0x30FB;
}

/// 直引號 `"` 無方向資訊，只能靠交替配對。配對以**行**為單位：
/// 對白引號幾乎不跨行，逐行配對能把單一雜訊引號的錯位影響隔離在
/// 該行（整章全域交替時，一個落單引號會讓其後所有開/收全部顛倒；
/// 全章奇數個就整章放棄，命中率極低）。奇數個引號的行原樣保留；
/// 逐對再做 CJK 脈絡判定，純英文行（`"Hello," he said.`）不動。
String _normalizePairedQuotes(String input) {
  return input
      .split('\n')
      .map(
        (line) => _convertAlternatingQuotesLine(
          line,
          quote: 0x22,
          openReplacement: '「',
          closeReplacement: '」',
          skipAt: (runes, index) => false,
        ),
      )
      .join('\n');
}

/// 直單引號 `'` 同理配對轉 `『』`（中文巢狀引號慣例的內層）。
/// 夾在拉丁字母/數字之間的 `'` 是撇號（don't），不參與配對。
String _normalizePairedSingleQuotes(String input) {
  return input
      .split('\n')
      .map(
        (line) => _convertAlternatingQuotesLine(
          line,
          quote: 0x27,
          openReplacement: '『',
          closeReplacement: '』',
          skipAt: (runes, index) {
            final previous = index > 0 ? runes[index - 1] : null;
            final next = index + 1 < runes.length ? runes[index + 1] : null;
            return _isLatinLetterOrDigit(previous) &&
                _isLatinLetterOrDigit(next);
          },
        ),
      )
      .join('\n');
}

String _convertAlternatingQuotesLine(
  String line, {
  required int quote,
  required String openReplacement,
  required String closeReplacement,
  required bool Function(List<int> runes, int index) skipAt,
}) {
  final runes = line.runes.toList(growable: false);
  final positions = <int>[];
  for (var index = 0; index < runes.length; index += 1) {
    if (runes[index] == quote &&
        !_isEscaped(runes, index) &&
        !skipAt(runes, index)) {
      positions.add(index);
    }
  }
  if (positions.isEmpty || positions.length.isOdd) return line;

  final output = List<String>.generate(
    runes.length,
    (index) => String.fromCharCode(runes[index]),
    growable: false,
  );
  var converted = false;
  for (var pair = 0; pair + 1 < positions.length; pair += 2) {
    final openIndex = positions[pair];
    final closeIndex = positions[pair + 1];
    if (!_quotePairHasCjkContext(runes, openIndex, closeIndex)) continue;
    output[openIndex] = openReplacement;
    output[closeIndex] = closeReplacement;
    converted = true;
  }
  return converted ? output.join() : line;
}

/// 半形括號在 CJK 脈絡下成對轉全形：`()`→`（）`、`[]`→`【】`
/// （`【】` 隨後由 [_mapCjkOnlyPunctuation] 統一轉 `「」`）。
/// 同行成對＋逐對 CJK 脈絡判定；純西文（`f(x)`、`[1]`）不動。
String _normalizeBrackets(String input) {
  final runes = input.runes.toList(growable: false);
  final output = List<String>.generate(
    runes.length,
    (index) => String.fromCharCode(runes[index]),
    growable: false,
  );
  _convertBracketPairs(
    runes,
    output,
    open: 0x28,
    close: 0x29,
    openReplacement: '（',
    closeReplacement: '）',
  );
  _convertBracketPairs(
    runes,
    output,
    open: 0x5B,
    close: 0x5D,
    openReplacement: '【',
    closeReplacement: '】',
  );
  return output.join();
}

void _convertBracketPairs(
  List<int> runes,
  List<String> output, {
  required int open,
  required int close,
  required String openReplacement,
  required String closeReplacement,
}) {
  var index = 0;
  while (index < runes.length) {
    if (runes[index] != open) {
      index += 1;
      continue;
    }
    var closeIndex = -1;
    var cursor = index + 1;
    for (; cursor < runes.length; cursor += 1) {
      final rune = runes[cursor];
      if (rune == 0x0A || rune == open) break;
      if (rune == close) {
        closeIndex = cursor;
        break;
      }
    }
    if (closeIndex < 0) {
      index = cursor > index ? cursor : index + 1;
      continue;
    }
    if (_quotePairHasCjkContext(runes, index, closeIndex)) {
      output[index] = openReplacement;
      output[closeIndex] = closeReplacement;
    }
    index = closeIndex + 1;
  }
}

/// CJK 專屬碼位的一對一風格映射（恆為中文脈絡，無需判定）：
/// `【】〖〗`→`「」『』`（2026-07-18 使用者定案：統一成上下引號）、
/// 半形直角引號 `｢｣`（U+FF62/FF63）→ `「」`。
String _mapCjkOnlyPunctuation(String input) {
  const mappings = <int, String>{
    0x3010: '「', // 【
    0x3011: '」', // 】
    0x3016: '『', // 〖
    0x3017: '』', // 〗
    0xFF62: '「', // ｢
    0xFF63: '」', // ｣
  };
  final output = StringBuffer();
  for (final rune in input.runes) {
    final replacement = mappings[rune];
    if (replacement != null) {
      output.write(replacement);
    } else {
      output.write(String.fromCharCode(rune));
    }
  }
  return output.toString();
}

bool _isEscaped(List<int> runes, int index) {
  var slashCount = 0;
  for (var cursor = index - 1; cursor >= 0 && runes[cursor] == 0x5C; cursor--) {
    slashCount += 1;
  }
  return slashCount.isOdd;
}

/// 兩側皆 CJK 脈絡字元（漢字或全形標點）的半形空格是來源雜訊，直接刪。
/// 半形空格不佔全形格，是格線錯位的主要來源之一；「他說 「你好」」這類
/// 標點鄰接空格也要涵蓋，故用 [_isCjkContextRune] 而非僅漢字。
String _removeCjkSpaces(String input) {
  final runes = input.runes.toList(growable: false);
  final output = StringBuffer();
  for (var index = 0; index < runes.length; index += 1) {
    if (runes[index] == 0x20 &&
        index > 0 &&
        index + 1 < runes.length &&
        _isCjkContextRune(runes[index - 1]) &&
        _isCjkContextRune(runes[index + 1])) {
      continue;
    }
    output.write(String.fromCharCode(runes[index]));
  }
  return output.toString();
}

bool _isAsciiOrFullWidthDigit(int? rune) {
  if (rune == null) return false;
  return (rune >= 0x30 && rune <= 0x39) || (rune >= 0xFF10 && rune <= 0xFF19);
}

bool _isCjkRune(int? rune) {
  if (rune == null) return false;
  return (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0x20000 && rune <= 0x323AF);
}

class ReaderV2ContentTransformer {
  const ReaderV2ContentTransformer();

  static final Map<String, RegExp> _regexCache = {};
  static const String _duplicateTitleBoundary = r'(?=\s|\p{P}|$)';

  static RegExp _getOrCreateRegex(String pattern, {bool unicode = false}) {
    final key = '$pattern|$unicode';
    if (_regexCache.length > 500) {
      _regexCache.clear();
    }
    return _regexCache.putIfAbsent(
      key,
      () => RegExp(pattern, unicode: unicode),
    );
  }

  Future<ReaderV2ProcessedChapter> process({
    required Book book,
    required BookChapter chapter,
    required String rawContent,
    required List<ReplaceRule> enabledRules,
    required int chineseConvertType,
  }) async {
    final args = <String, Object?>{
      'bookName': book.name,
      'bookOrigin': book.origin,
      'chapterTitle': chapter.title,
      'rawContent': rawContent,
      'rulesJson': enabledRules.map((rule) => rule.toJson()).toList(),
      'useReplaceRules': book.getUseReplaceRule(),
      'reSegmentEnabled': book.getReSegment(),
      'chineseConvertType': chineseConvertType,
    };

    // 首選：常駐 worker isolate。免去每章 compute spawn，且簡繁轉換也在
    // worker 內完成（字典由主 isolate 送入初始化一次），主執行緒只剩訊息
    // 收發——fling 減速期間的內容預載不再佔用幀預算。
    final workerResult = await ReaderV2ContentTransformWorker.instance.process(
      args,
    );
    if (workerResult != null) {
      return _decodeProcessed(workerResult);
    }

    // 退回路徑（worker 不可用）：行為與舊版完全相同——compute 一次性
    // isolate 做替換/重分段，簡繁轉換因字典只在主 isolate 而留在主執行緒。
    final result = await compute(_processInBackground, args);
    final processed = _decodeProcessed(result);
    if (chineseConvertType == 0) return processed;
    const converter = ChineseTextConverter();
    return ReaderV2ProcessedChapter(
      displayTitle: converter.convert(
        processed.displayTitle,
        convertType: chineseConvertType,
      ),
      content: convertChinesePreservingJapanese(
        processed.content,
        chineseConvertType,
      ),
      effectiveReplaceRules: processed.effectiveReplaceRules,
      sameTitleRemoved: processed.sameTitleRemoved,
    );
  }

  /// 逐行簡繁轉換，假名偵測命中的行跳過。
  ///
  /// 日文段落的漢字若先被簡繁字典改字（発→發、国→國），就不再是
  /// 合法日文，後續的日文翻譯 pass（ML Kit）輸入品質會劣化；即使
  /// 翻譯功能關閉，把日文漢字硬轉成中文字形也是改壞原文。
  static String convertChinesePreservingJapanese(String text, int convertType) {
    if (text.isEmpty || convertType == 0) return text;
    const converter = ChineseTextConverter();
    return text
        .split('\n')
        .map(
          (line) =>
              looksJapanese(line)
                  ? line
                  : converter.convert(line, convertType: convertType),
        )
        .join('\n');
  }

  static ReaderV2ProcessedChapter _decodeProcessed(
    Map<String, Object?> result,
  ) {
    final effectiveRules = (result['effectiveRules'] as List<dynamic>)
        .map(
          (rule) =>
              ReplaceRule.fromJson(Map<String, dynamic>.from(rule as Map)),
        )
        .toList(growable: false);
    return ReaderV2ProcessedChapter(
      displayTitle: result['displayTitle'] as String? ?? '',
      content: result['content'] as String? ?? '',
      effectiveReplaceRules: List<ReplaceRule>.unmodifiable(effectiveRules),
      sameTitleRemoved: result['sameTitleRemoved'] as bool? ?? false,
    );
  }

  static Map<String, Object?> _processInBackground(Map<String, Object?> args) {
    final bookName = args['bookName'] as String? ?? '';
    final bookOrigin = args['bookOrigin'] as String? ?? '';
    final chapterTitle = args['chapterTitle'] as String? ?? '';
    final rawContent = args['rawContent'] as String? ?? '';
    final rulesJson =
        (args['rulesJson'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>();
    final useReplaceRules = args['useReplaceRules'] as bool? ?? true;
    final reSegmentEnabled = args['reSegmentEnabled'] as bool? ?? true;
    final rules =
        rulesJson
            .map(ReplaceRule.fromJson)
            .where((rule) => rule.isEnabled)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));

    final titleRules = rules
        .where(
          (rule) =>
              rule.appliesToTitle(bookName: bookName, bookOrigin: bookOrigin),
        )
        .toList(growable: false);
    final contentResult = _processContent(
      bookName: bookName,
      bookOrigin: bookOrigin,
      chapterTitle: chapterTitle,
      rawContent: rawContent,
      rules: rules,
      titleRules: titleRules,
      useReplaceRules: useReplaceRules,
      reSegmentEnabled: reSegmentEnabled,
    );
    final displayTitle = _processTitle(
      chapterTitle: chapterTitle,
      rules: titleRules,
      useReplaceRules: useReplaceRules,
    );

    return <String, Object?>{
      'displayTitle': displayTitle,
      'content': contentResult.content,
      'effectiveRules': contentResult.effectiveReplaceRules
          .map((rule) => rule.toJson())
          .toList(growable: false),
      'sameTitleRemoved': contentResult.sameTitleRemoved,
    };
  }

  static ReaderV2ProcessedChapter _processContent({
    required String bookName,
    required String bookOrigin,
    required String chapterTitle,
    required String rawContent,
    required List<ReplaceRule> rules,
    required List<ReplaceRule> titleRules,
    required bool useReplaceRules,
    required bool reSegmentEnabled,
  }) {
    if (rawContent.isEmpty) {
      return const ReaderV2ProcessedChapter(displayTitle: '', content: '');
    }

    var content = rawContent;
    var sameTitleRemoved = false;
    final effectiveRules = <ReplaceRule>[];

    final nameRegex = RegExp.escape(bookName);
    final titleRegex = RegExp.escape(
      chapterTitle,
    ).replaceAll(AppPattern.spaceRegex, r'\s*');
    final duplicateTitlePattern = _getOrCreateRegex(
      '^(\\s|\\p{P}|$nameRegex)*$titleRegex'
      '$_duplicateTitleBoundary(\\s)*',
      unicode: true,
    );
    final duplicateTitleMatch = duplicateTitlePattern.firstMatch(content);
    if (duplicateTitleMatch != null) {
      content = content.substring(duplicateTitleMatch.end);
      sameTitleRemoved = true;
    } else if (useReplaceRules && titleRules.isNotEmpty) {
      final displayTitle = _processTitle(
        chapterTitle: chapterTitle,
        rules: titleRules,
        useReplaceRules: true,
      );
      if (displayTitle.trim().isNotEmpty && displayTitle != chapterTitle) {
        final displayTitleRegex = RegExp.escape(
          displayTitle,
        ).replaceAll(AppPattern.spaceRegex, r'\s*');
        final displayDuplicateTitlePattern = _getOrCreateRegex(
          '^(\\s|\\p{P}|$nameRegex)*$displayTitleRegex'
          '$_duplicateTitleBoundary(\\s)*',
          unicode: true,
        );
        final displayDuplicateTitleMatch = displayDuplicateTitlePattern
            .firstMatch(content);
        if (displayDuplicateTitleMatch != null) {
          content = content.substring(displayDuplicateTitleMatch.end);
          sameTitleRemoved = true;
        }
      }
    }

    if (reSegmentEnabled) {
      content = _reSegment(content);
    }

    if (useReplaceRules) {
      final buffer = StringBuffer();
      final lines = content.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) buffer.write('\n');
        buffer.write(lines[i].trim());
      }
      content = buffer.toString();
      for (final rule in rules) {
        if (!rule.appliesToContent(
          bookName: bookName,
          bookOrigin: bookOrigin,
        )) {
          continue;
        }

        try {
          final previous = content;
          content = rule.apply(content);
          if (content != previous) {
            effectiveRules.add(rule);
          }
        } catch (_) {}
      }
    }

    content = normalizeTypography(content);

    final paragraphs = <String>[];
    const indent = '　　';
    for (final line in content.split('\n')) {
      final paragraph = line.trim().replaceAll('\u00A0', ' ');
      if (paragraph.isNotEmpty) {
        paragraphs.add('$indent$paragraph');
      }
    }

    return ReaderV2ProcessedChapter(
      displayTitle: '',
      content: paragraphs.join('\n'),
      effectiveReplaceRules: List<ReplaceRule>.unmodifiable(effectiveRules),
      sameTitleRemoved: sameTitleRemoved,
    );
  }

  static String _reSegment(String content) {
    final normalized = content
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n');
    final nonEmptyLines =
        normalized.split('\n').where((line) => line.trim().isNotEmpty).length;
    if (nonEmptyLines > 1 || normalized.trim().length < 180) {
      return normalized;
    }
    return _splitSingleLineByPunctuation(normalized);
  }

  static String _splitSingleLineByPunctuation(String content) {
    final buffer = StringBuffer();
    for (var index = 0; index < content.length; index++) {
      final char = content[index];
      buffer.write(char);
      if (!_sentenceEndChars.contains(char)) continue;

      while (index + 1 < content.length &&
          _sentenceCloseChars.contains(content[index + 1])) {
        index += 1;
        buffer.write(content[index]);
      }

      if (index + 1 < content.length && content[index + 1].trim().isNotEmpty) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  static const String _sentenceEndChars = '。！？!?；;';
  static const String _sentenceCloseChars = '」』”’））》〉】]';

  static String _processTitle({
    required String chapterTitle,
    required List<ReplaceRule> rules,
    required bool useReplaceRules,
  }) {
    var displayTitle = chapterTitle.replaceAll(RegExp(r'[\r\n]'), '');
    if (useReplaceRules) {
      for (final rule in rules) {
        if (rule.pattern.isEmpty) continue;
        try {
          final next = rule.apply(displayTitle);
          if (next.trim().isNotEmpty) {
            displayTitle = next;
          }
        } catch (_) {}
      }
    }
    return normalizeTypography(displayTitle, preserveCjkSpaces: true);
  }
}

/// 常駐內容轉換 worker isolate。
///
/// 為什麼不用 compute：fling 放開瞬間會連續預載最多 3 章，compute 每章現場
/// spawn/銷毀一個 isolate；且簡繁字典只存在主 isolate 靜態區，轉換被迫留在
/// 主執行緒對整章正文執行，成本正好落在減速動畫期間。常駐 worker 只 spawn
/// 一次、字典初始化一次，之後替換規則＋重分段＋簡繁轉換全部離開主執行緒。
///
/// worker 不可用（spawn 失敗、isolate 死亡）時 [process] 回傳 null，呼叫端
/// 退回既有的 compute 路徑，行為不變。
class ReaderV2ContentTransformWorker {
  ReaderV2ContentTransformWorker._();

  static final ReaderV2ContentTransformWorker instance =
      ReaderV2ContentTransformWorker._();

  /// 測試鉤子：字典原文提供者。預設從 rootBundle 取（啟動時已載入快取）。
  @visibleForTesting
  static Future<List<String>?> Function() dictionaryDataLoader =
      loadDictionaryDataFromBundle;

  /// 測試鉤子：強制停用 worker，讓 process 走 compute 退回路徑。
  @visibleForTesting
  static bool debugDisableWorker = false;

  Future<SendPort?>? _starting;
  ReceivePort? _responses;
  Isolate? _isolate;
  bool _broken = false;
  int _nextRequestId = 0;
  final Map<int, Completer<Map<String, Object?>?>> _pending =
      <int, Completer<Map<String, Object?>?>>{};

  @visibleForTesting
  static Future<List<String>?> loadDictionaryDataFromBundle() async {
    try {
      return await Future.wait(
        ChineseUtils.dictionaryAssetPaths.map(rootBundle.loadString),
      );
    } catch (_) {
      // 測試環境或 asset 缺失：worker 內簡繁轉換退化為直通（與主 isolate
      // 字典未初始化時的行為一致）。
      return null;
    }
  }

  /// 轉換一章；回傳 null 代表 worker 不可用，呼叫端應退回 compute 路徑。
  Future<Map<String, Object?>?> process(Map<String, Object?> args) async {
    if (debugDisableWorker || _broken) return null;
    SendPort? commands;
    try {
      commands = await (_starting ??= _start());
    } catch (_) {
      commands = null;
    }
    if (commands == null) {
      _markBroken();
      return null;
    }
    final id = _nextRequestId++;
    final completer = Completer<Map<String, Object?>?>();
    _pending[id] = completer;
    try {
      commands.send(<String, Object?>{
        'type': 'process',
        'id': id,
        'args': args,
      });
    } catch (_) {
      _pending.remove(id);
      _markBroken();
      return null;
    }
    return completer.future;
  }

  Future<SendPort?> _start() async {
    final responses = ReceivePort();
    final handshake = Completer<SendPort?>();
    responses.listen((Object? message) {
      if (message is SendPort) {
        if (!handshake.isCompleted) handshake.complete(message);
        return;
      }
      if (message is Map) {
        final id = message['id'] as int?;
        final completer = id == null ? null : _pending.remove(id);
        if (completer == null || completer.isCompleted) return;
        final result = message['result'];
        completer.complete(
          message['ok'] == true && result is Map
              ? Map<String, Object?>.from(result)
              : null,
        );
        return;
      }
      // onError（List）或 onExit（null）：worker 已不可信，讓所有等待者
      // 退回 compute 路徑。
      if (!handshake.isCompleted) handshake.complete(null);
      _markBroken();
    });
    _responses = responses;
    try {
      _isolate = await Isolate.spawn(
        _workerMain,
        responses.sendPort,
        onError: responses.sendPort,
        onExit: responses.sendPort,
        debugName: 'reader-v2-content-transform',
      );
    } catch (_) {
      responses.close();
      _responses = null;
      return null;
    }
    final commands = await handshake.future;
    if (commands == null) return null;
    // 字典訊息先於任何 process 訊息送出（同一 port 依序送達），worker 收到
    // 第一章之前必已完成初始化。
    final dictionaryData = await dictionaryDataLoader();
    if (dictionaryData != null && dictionaryData.length == 4) {
      commands.send(<String, Object?>{'type': 'dict', 'data': dictionaryData});
    }
    return commands;
  }

  void _markBroken() {
    _broken = true;
    final waiters = _pending.values.toList(growable: false);
    _pending.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete(null);
    }
    _responses?.close();
    _responses = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  /// 測試鉤子：關掉現有 worker 並重設狀態，讓下一次 process 重新 spawn。
  @visibleForTesting
  void debugReset() {
    _markBroken();
    _broken = false;
    _starting = null;
  }

  static void _workerMain(SendPort replyPort) {
    final commands = ReceivePort();
    replyPort.send(commands.sendPort);
    commands.listen((Object? message) {
      if (message is! Map) return;
      switch (message['type']) {
        case 'dict':
          final data = message['data'];
          if (data is List) {
            ChineseUtils.initializeFromDictionaryData(data.cast<String>());
          }
        case 'process':
          final id = message['id'] as int?;
          final rawArgs = message['args'];
          if (id == null || rawArgs is! Map) return;
          try {
            final args = Map<String, Object?>.from(rawArgs);
            final result = ReaderV2ContentTransformer._processInBackground(
              args,
            );
            final convertType = args['chineseConvertType'] as int? ?? 0;
            if (convertType != 0) {
              const converter = ChineseTextConverter();
              result['displayTitle'] = converter.convert(
                result['displayTitle'] as String? ?? '',
                convertType: convertType,
              );
              result['content'] =
                  ReaderV2ContentTransformer.convertChinesePreservingJapanese(
                    result['content'] as String? ?? '',
                    convertType,
                  );
            }
            replyPort.send(<String, Object?>{
              'id': id,
              'ok': true,
              'result': result,
            });
          } catch (e) {
            replyPort.send(<String, Object?>{
              'id': id,
              'ok': false,
              'error': '$e',
            });
          }
      }
    });
  }
}

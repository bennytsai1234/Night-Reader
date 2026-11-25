import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/core/models/replace_rule.dart';

/// 替換規則兩種寫法都比（ADR 0084）：正文先做繁簡轉換再套規則（同
/// Legado），規則照字面比一次；規則的字轉成顯示的寫法後和字面不同時，
/// 再用轉過的比一次。照畫面寫的規則用字面那次對上，照網站原文寫的舊規則
/// 用轉過的那次對上。規則的字不能只用轉過的：轉換器轉兩次不一定一樣
/// （「干擾」再轉成「幹擾」），照畫面寫的規則會被轉壞。
extension ReplaceRuleScript on ReplaceRule {
  /// 套這條規則時依序要比的寫法：字面這一條；再來是規則的字轉成
  /// [convertTypes]（`ChineseTextConverter` 的轉換方式，0 不轉）各自的寫法、
  /// 和前面都不同的。替換成的字一律照字面放（同 Legado）。正則只轉語法
  /// 以外的字（[_convertRegex]）。
  List<ReplaceRule> matchVariants(Iterable<int> convertTypes) {
    final variants = [this];
    for (final convertType in convertTypes) {
      if (convertType == 0) continue;
      final converted = _cached(
        convertType,
        isRegex ? 'p' : 't',
        pattern,
        () => isRegex
            ? _convertRegex(pattern, convertType)
            : _convertText(pattern, convertType),
      );
      if (variants.any((rule) => rule.pattern == converted)) continue;
      variants.add(
        ReplaceRule(
          id: id,
          name: name,
          group: group,
          pattern: converted,
          replacement: replacement,
          scope: scope,
          scopeTitle: scopeTitle,
          scopeContent: scopeContent,
          excludeScope: excludeScope,
          isEnabled: isEnabled,
          isRegex: isRegex,
          timeoutMillisecond: timeoutMillisecond,
          order: order,
        ),
      );
    }
    return variants;
  }
}

/// 轉過的規則字：每一章、每一次試跑都套同一批規則，轉一次就留著。
final Map<String, String> _converted = {};
const int _cacheMaxEntries = 4096;

String _cached(
  int convertType,
  String kind,
  String text,
  String Function() convert,
) {
  if (text.isEmpty) return text;
  final key = '$convertType$kind$text';
  final hit = _converted[key];
  if (hit != null) return hit;
  if (_converted.length >= _cacheMaxEntries) _converted.clear();
  return _converted[key] = convert();
}

String _convertText(String text, int convertType) =>
    const ChineseTextConverter().convert(text, convertType: convertType);

bool _isAscii(int unit) => unit < 0x80;

/// 正則裡只轉非 ASCII 的字（漢字與全形標點），一段連續的一起轉；語法都是
/// ASCII，照原樣：跳脫字元（`\p{…}`、`\k<…>`、`\x{…}` 到右括號為止，其他
/// 是反斜線加下一個字）與具名群組的名稱（`(?<名稱>`）不動。
String _convertRegex(String pattern, int convertType) {
  final out = StringBuffer();
  final run = StringBuffer();
  void flush() {
    if (run.isEmpty) return;
    out.write(_convertText(run.toString(), convertType));
    run.clear();
  }

  var i = 0;
  while (i < pattern.length) {
    final unit = pattern.codeUnitAt(i);
    if (unit == 0x5C /* \ */ ) {
      flush();
      final end = _escapeEnd(pattern, i);
      out.write(pattern.substring(i, end));
      i = end;
      continue;
    }
    if (pattern.startsWith('(?<', i) &&
        i + 3 < pattern.length &&
        pattern[i + 3] != '=' &&
        pattern[i + 3] != '!') {
      flush();
      final close = pattern.indexOf('>', i + 3);
      final end = close < 0 ? pattern.length : close + 1;
      out.write(pattern.substring(i, end));
      i = end;
      continue;
    }
    if (_isAscii(unit)) {
      flush();
      out.writeCharCode(unit);
    } else {
      run.writeCharCode(unit);
    }
    i += 1;
  }
  flush();
  return out.toString();
}

/// 從 [start] 的反斜線起的跳脫字元結束在哪。
int _escapeEnd(String pattern, int start) {
  final next = start + 1;
  if (next >= pattern.length) return pattern.length;
  final char = pattern[next];
  String? closer;
  if ((char == 'p' || char == 'P' || char == 'x' || char == 'u') &&
      pattern.startsWith('{', next + 1)) {
    closer = '}';
  } else if (char == 'k' && pattern.startsWith('<', next + 1)) {
    closer = '>';
  }
  if (closer != null) {
    final close = pattern.indexOf(closer, next + 2);
    return close < 0 ? pattern.length : close + 1;
  }
  // 反斜線後是一個字（含兩個 UTF-16 單位的字）。
  final unit = pattern.codeUnitAt(next);
  final isLead = unit >= 0xD800 && unit <= 0xDBFF;
  return (isLead && next + 1 < pattern.length ? next + 2 : next + 1);
}

import 'package:night_reader/core/engine/parsers/java_regexp.dart';
import 'package:night_reader/core/engine/reader/chinese_text_converter.dart';
import 'package:night_reader/core/models/replace_rule.dart';

/// 替換規則兩種寫法都比（ADR 0084）：正文先做繁簡轉換再套規則（同
/// Legado），規則照字面比；規則的字轉成顯示的寫法後和字面不同時，轉過的
/// 也比。兩種寫法對同一段字（這條規則套用前的）比，每一處只換一次
/// （[applyVariants]）。照畫面寫的規則用字面對上，照網站原文寫的舊規則用
/// 轉過的對上。規則的字不能只用轉過的：轉換器轉兩次不一定一樣（「干擾」
/// 再轉成「幹擾」），照畫面寫的規則會被轉壞。
extension ReplaceRuleScript on ReplaceRule {
  /// 套用這條規則，字面與轉成 [convertTypes] 的寫法都比（[matchVariants]、
  /// [applyVariants]）。正文、章名與試跑都用它。
  String applyMatchingVariants(
    String text,
    Iterable<int> convertTypes, {
    String Function(String code, String matched)? runJs,
  }) => applyVariants(text, matchVariants(convertTypes), runJs: runJs);

  /// 套這條規則時要比的寫法，重疊時排前面的優先：字面這一條；再來是規則的
  /// 字轉成 [convertTypes]（`ChineseTextConverter` 的轉換方式，0 不轉）各自
  /// 的寫法、和前面都不同的。替換成的字一律照字面放（同 Legado）。正則只轉語法
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

/// 套用一條規則的幾種寫法 [variants]（[ReplaceRuleScript.matchVariants]）：
/// 每一種都對 [text] 比，對到的地方重疊時排前面的那一種優先（字面優先），
/// 每一處只換一次，換上的字不再被別的寫法比到。只有一種寫法時就是
/// [ReplaceRule.apply]。長度是零的對法（`^`、`(?=…)`）和同一處的另一種
/// 對法算重疊。正則寫錯的那一種寫法不比；「替換為」的 `@js:` 出錯時這條
/// 不套，[text] 照舊（同 [ReplaceRule.apply]）。
String applyVariants(
  String text,
  List<ReplaceRule> variants, {
  String Function(String code, String matched)? runJs,
}) {
  if (variants.length == 1) return variants.single.apply(text, runJs: runJs);
  final rule = variants.first;
  if (rule.pattern.isEmpty) return text;
  final js = rule.isRegex && rule.replacement.startsWith('@js:');
  if (js && runJs == null) return text;
  var accepted = <_Match>[];
  for (final variant in variants) {
    final found = _matchesOf(variant, text, js: js);
    if (found == null || found.isEmpty) continue;
    if (accepted.isEmpty) {
      accepted = found;
      continue;
    }
    final added = [
      for (final match in found)
        if (!_overlapsAny(accepted, match)) match,
    ];
    if (added.isEmpty) continue;
    accepted = _merged(accepted, added);
  }
  if (accepted.isEmpty) return text;
  final out = StringBuffer();
  var cursor = 0;
  try {
    for (final match in accepted) {
      out
        ..write(text.substring(cursor, match.start))
        ..write(
          js
              ? runJs!(rule.replacement.substring(4), match.matched)
              : match.replacement,
        );
      cursor = match.end;
    }
  } on Object {
    return text;
  }
  out.write(text.substring(cursor));
  return out.toString();
}

typedef _Match = ({int start, int end, String matched, String replacement});

/// [variant] 在 [text] 裡對到的地方，由前到後、互不重疊；正則寫錯是 null。
/// [js] 時替換成的字之後才跑 JS 算，這裡不算。
List<_Match>? _matchesOf(ReplaceRule variant, String text, {required bool js}) {
  final pattern = variant.pattern;
  if (!variant.isRegex) {
    final found = <_Match>[];
    var at = text.indexOf(pattern);
    while (at >= 0) {
      found.add((
        start: at,
        end: at + pattern.length,
        matched: pattern,
        replacement: variant.replacement,
      ));
      at = text.indexOf(pattern, at + pattern.length);
    }
    return found;
  }
  try {
    final reg = javaRegExp(pattern);
    return [
      for (final match in reg.allMatches(text))
        (
          start: match.start,
          end: match.end,
          matched: match.group(0)!,
          replacement: js ? '' : javaReplacement(variant.replacement, match),
        ),
    ];
  } on FormatException {
    return null;
  }
}

bool _overlaps(_Match a, _Match b) =>
    a.start < b.end && b.start < a.end ||
    a.start == b.start && (a.start == a.end || b.start == b.end);

/// [match] 和 [sorted]（照位置排、互不重疊）裡的哪一處重疊。
bool _overlapsAny(List<_Match> sorted, _Match match) {
  var low = 0;
  var high = sorted.length;
  while (low < high) {
    final mid = (low + high) >> 1;
    if (sorted[mid].start < match.start) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low > 0 && _overlaps(sorted[low - 1], match) ||
      low < sorted.length && _overlaps(sorted[low], match);
}

/// 兩份照位置排的對到處合成一份。
List<_Match> _merged(List<_Match> a, List<_Match> b) {
  final out = <_Match>[];
  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    if (j >= b.length || i < a.length && a[i].start <= b[j].start) {
      out.add(a[i++]);
    } else {
      out.add(b[j++]);
    }
  }
  return out;
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

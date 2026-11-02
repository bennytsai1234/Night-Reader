import 'package:html/dom.dart';
import 'package:night_reader/core/models/json_read.dart';
import 'package:night_reader/core/models/source/lenient_json.dart';
import 'package:xpath_selector/xpath_selector.dart';

import '../parsers/analyze_by_css.dart';
import '../parsers/analyze_by_json_path.dart';
import '../parsers/analyze_by_xpath.dart';
import 'analyze_rule_base.dart';

enum Mode { xpath, json, defaultMode, js, regex }

/// SourceRule 輔助類
/// (原 Android model/analyzeRule/AnalyzeRule.kt) 內部的私有類
class SourceRule {
  String rule;
  Mode mode;
  String replaceRegex = '';
  String replacement = '';
  bool replaceFirst = false;
  Map<String, String> putMap = {};
  bool isDynamic = false;
  List<String> ruleParam = [];
  List<int> ruleType = [];

  static final RegExp _evalPattern = RegExp(
    r'@get:\{[^}]+?\}|\{\{[\w\W]*?\}\}|\{\$.*?\}',
    caseSensitive: false,
  );
  static final RegExp _evalPatternJson = RegExp(
    r'@get:\{[^}]+?\}|\{\{[\w\W]*?\}\}',
    caseSensitive: false,
  );

  static const int jsonPartRuleType = -3;
  static const int getRuleType = -2;
  static const int jsRuleType = -1;
  static const int defaultRuleType = 0;

  /// [isJson]：要解析的內容是 JSON（[isJsonContent]）。同 Legado，這時沒有
  /// 前綴的規則一律是 JSON 路徑。
  SourceRule(this.rule, {this.mode = Mode.defaultMode, bool isJson = false}) {
    rule = _stripLeadingStandaloneCommentLines(rule);
    // 處理 ##regex##replacement 與 ### replaceFirst
    if (rule.contains('##')) {
      final rawParts = rule.split('##');
      final parts = <String>[];
      for (var i = 0; i < rawParts.length; i++) {
        final part = rawParts[i];
        if (i == rawParts.length - 1 && part.endsWith('#')) {
          replaceFirst = true;
          parts.add(part.substring(0, part.length - 1));
        } else {
          parts.add(part);
        }
      }

      if (rule.startsWith('##')) {
        mode = Mode.regex;
        rule = ''; // 提取規則為空，表示對全文進行正則替換
        if (parts.length > 1) replaceRegex = parts[1];
        if (parts.length > 2) replacement = parts[2];
      } else {
        rule = parts[0];
        if (parts.length > 1) replaceRegex = parts[1];
        if (parts.length > 2) replacement = parts[2];
      }
    }

    if (mode == Mode.defaultMode) {
      final normalizedRule = rule.toUpperCase();
      if (normalizedRule.startsWith('@CSS:')) {
        mode = Mode.defaultMode;
      } else if (_looksLikeLegacyRegexRule(rule)) {
        mode = Mode.regex;
        rule = rule.trimLeft().substring(1);
      } else if (rule.startsWith('@@')) {
        mode = Mode.defaultMode;
        rule = rule.substring(2);
      } else if (normalizedRule.startsWith('@JSON:')) {
        mode = Mode.json;
        rule = rule.substring(6);
      } else if (normalizedRule.startsWith('@XPATH:')) {
        mode = Mode.xpath;
        rule = rule.substring(7);
      } else if (isJson || rule.startsWith(r'$.') || rule.startsWith(r'$[')) {
        mode = Mode.json;
      } else if (rule.startsWith('/')) {
        mode = Mode.xpath;
      }
    }
    // 同 Legado `splitPutRule`：照 Gson 讀進 `Map<String, String>`，標準 JSON
    // 與寬鬆寫法（`@put:{bid:id}` 鍵和值都沒加引號）都收；數字照原文
    // （`007` 不變成 7），物件與陣列轉成 JSON 文字。
    final putPattern = RegExp(r'@put:(\{[^}]+?\})', caseSensitive: false);
    var vRuleStr = rule;
    final putMatches = putPattern.allMatches(rule);
    for (final putMatch in putMatches) {
      vRuleStr = vRuleStr.replaceFirst(putMatch.group(0)!, '');
      final jsonStr = putMatch.group(1)!;
      Object? decoded;
      try {
        decoded = decodeLenientJson(jsonStr, numbersAsText: true);
      } on FormatException {
        decoded = null;
      }
      if (decoded is Map) {
        decoded.forEach((k, v) {
          final value = readJsonString(v);
          if (value != null) putMap['$k'] = value;
        });
      }
    }
    rule = vRuleStr;
    // JSON 模式的 `{$.x}` 由 JSON 解析器替換（同 Legado，它的 evalPattern 沒有
    // 這一種）；其他模式夜讀在這裡先代入。
    final evalPattern = mode == Mode.json ? _evalPatternJson : _evalPattern;
    var start = 0;
    final evalMatches = evalPattern.allMatches(rule);
    if (evalMatches.isNotEmpty) {
      isDynamic = true;
      // 同 Legado：含 `@get:`、`{{ }}` 的規則組好就是結果的文字，不再拿去
      // 解析（`##` 之後的取代已在上面分開）。
      if (mode != Mode.js && mode != Mode.regex) mode = Mode.regex;
    }
    for (final match in evalMatches) {
      if (match.start > start) _splitRegex(rule.substring(start, match.start));
      final tmp = match.group(0)!;
      if (tmp.toLowerCase().startsWith('@get:')) {
        ruleType.add(getRuleType);
        ruleParam.add(tmp.substring(6, tmp.length - 1));
      } else if (tmp.startsWith('{{')) {
        ruleType.add(jsRuleType);
        ruleParam.add(tmp.substring(2, tmp.length - 2));
      } else if (tmp.startsWith('{\$')) {
        ruleType.add(jsonPartRuleType);
        ruleParam.add(tmp.substring(1, tmp.length - 1));
      }
      start = match.end;
    }
    if (rule.length > start) _splitRegex(rule.substring(start));
  }

  bool _looksLikeLegacyRegexRule(String rawRule) {
    final trimmed = rawRule.trimLeft();
    return trimmed.startsWith(':(?');
  }

  void _splitRegex(String ruleStr) {
    var start = 0;
    final regexPattern = RegExp(r'\$\d{1,2}');
    final matches = regexPattern.allMatches(ruleStr);
    if (matches.isNotEmpty) {
      isDynamic = true;
      if (mode != Mode.js) {
        mode = Mode.regex;
      }
    }
    for (final match in matches) {
      if (match.start > start) {
        ruleType.add(defaultRuleType);
        ruleParam.add(ruleStr.substring(start, match.start));
      }
      ruleType.add(int.parse(match.group(0)!.substring(1)));
      ruleParam.add(match.group(0)!);
      start = match.end;
    }
    if (ruleStr.length > start) {
      ruleType.add(defaultRuleType);
      ruleParam.add(ruleStr.substring(start));
    }
  }

  /// 動態組合規則字串 (對標 Android SourceRule.makeUpRule)
  ///
  /// 重要：本方法不得 mutate `this.rule`，因為 SourceRule 實例會被
  /// stringRuleCache 靜態快取跨呼叫共用。mutate 後會造成 race condition
  /// 或把動態組合後的字串寫回快取，污染後續使用者。
  String makeUpRule(dynamic result, dynamic analyzer) {
    if (!isDynamic) return rule;
    final buffer = StringBuffer();
    for (var i = 0; i < ruleType.length; i++) {
      final type = ruleType[i];
      final param = ruleParam[i];
      if (type == defaultRuleType) {
        buffer.write(param);
      } else if (type == jsRuleType) {
        final trimmed = param.trimLeft();
        if (trimmed.startsWith('@') ||
            trimmed.startsWith(r'$.') ||
            trimmed.startsWith(r'$[') ||
            trimmed.startsWith('//')) {
          buffer.write(analyzer.getString(trimmed));
        } else {
          buffer.write(analyzer.evalJS(param, result) ?? '');
        }
      } else if (type == getRuleType) {
        buffer.write(analyzer.get(param));
      } else if (type == jsonPartRuleType) {
        final val = getAnalyzeByJSonPath(analyzer, result).getString(param);
        buffer.write(val);
      } else {
        // 反向引用 $1..$N —— AnalyzeByRegex 會把 group(0) 放在 index 0，
        // 這裡需對齊 legado 語義，令 `$1` 對應第一個捕獲組而不是整段匹配。
        if (result is List && type > 0 && type < result.length) {
          buffer.write(result[type]?.toString() ?? '');
        }
      }
    }
    return buffer.toString();
  }

  int get paramSize => ruleParam.length;

  // 延遲載入解析器
  AnalyzeByXPath getAnalyzeByXPath(AnalyzeRuleBase analyzer, dynamic o) {
    if (o != analyzer.content) return AnalyzeByXPath(o);
    return analyzer.analyzeByXPath ??= AnalyzeByXPath(analyzer.content);
  }

  AnalyzeByCss getAnalyzeByJSoup(AnalyzeRuleBase analyzer, dynamic o) {
    if (o != analyzer.content) return AnalyzeByCss(o);
    return analyzer.analyzeByJSoup ??= AnalyzeByCss(analyzer.content);
  }

  AnalyzeByJsonPath getAnalyzeByJSonPath(AnalyzeRuleBase analyzer, dynamic o) {
    if (o != analyzer.content) return AnalyzeByJsonPath(o);
    return analyzer.analyzeByJSonPath ??= AnalyzeByJsonPath(analyzer.content);
  }
}

String _stripLeadingStandaloneCommentLines(String input) {
  if (!input.contains('\n')) {
    return input;
  }

  final lines = input.split('\n');
  var start = 0;
  while (start < lines.length) {
    final trimmed = lines[start].trim();
    if (trimmed.isEmpty) {
      start++;
      continue;
    }
    if (_looksLikeStandaloneRuleComment(trimmed) &&
        lines
            .skip(start + 1)
            .map((line) => line.trim())
            .any((line) => line.isNotEmpty)) {
      start++;
      continue;
    }
    break;
  }

  if (start == 0) {
    return input;
  }
  return lines.sublist(start).join('\n').trimLeft();
}

bool _looksLikeStandaloneRuleComment(String line) {
  if (!line.startsWith('//')) {
    return false;
  }
  final remainder = line.substring(2).trimLeft();
  if (remainder.isEmpty) {
    return true;
  }
  return !RegExp(r'^[A-Za-z_*\.@]').hasMatch(remainder);
}

String stringifyRuleResult(dynamic value) {
  if (value == null) {
    return '';
  }
  final htmlLike = extractHtmlLikeRuleInput(value);
  if (htmlLike != null) {
    return htmlLike;
  }
  if (value is Element) {
    return value.outerHtml;
  }
  // XPath 找到的節點：元素交出 HTML（`toString()` 只有標籤名稱）。
  if (value is XPathNode && value.node is Element) {
    return (value.node as Element).outerHtml;
  }
  if (value is Iterable) {
    return value.map(stringifyRuleResult).join('\n');
  }
  return value.toString();
}

/// 要解析的內容是不是 JSON（同 Legado `AnalyzeRule.setContent` 的
/// `isJSON`）：JSON 物件與陣列，或頭尾是 `{}`、`[]` 的文字；網頁元素與
/// XPath 找到的節點（一個或一組）不是。
bool isJsonContent(dynamic value) {
  if (value is Node || value is XPathNode) return false;
  if (extractHtmlLikeRuleInput(value) != null) return false;
  if (value is Map) return true;
  if (value is List) return !value.any((e) => e is Node || e is XPathNode);
  if (value is String) {
    final text = value.trim();
    return (text.startsWith('{') && text.endsWith('}')) ||
        (text.startsWith('[') && text.endsWith(']'));
  }
  return false;
}

String? extractHtmlLikeRuleInput(dynamic value) {
  if (value is Map) {
    for (final key in const <String>['__html', 'outerHtml', 'html']) {
      final candidate = value[key];
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate;
      }
    }
  }
  return null;
}

dynamic coerceNullInterimResult(dynamic result, SourceRule sourceRule) {
  if (result != null) {
    return result;
  }
  if (sourceRule.mode == Mode.js || sourceRule.isDynamic) {
    return '';
  }
  return null;
}

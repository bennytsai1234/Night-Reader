import 'analyze_rule_base.dart';
import 'analyze_rule_support.dart';

/// AnalyzeRule 的正則工具與輔助邏輯擴展
mixin AnalyzeRuleRegexHelper on AnalyzeRuleBase {
  /// 同一條規則對 JSON 與網頁解析成不同模式，快取分開放。
  List<SourceRule> splitSourceRuleCacheString(String ruleStr) {
    if (ruleStr.isEmpty) {
      return [];
    }
    final isJson = isJsonContent(content);
    final key = isJson ? '\u0000json:$ruleStr' : ruleStr;
    if (AnalyzeRuleBase.stringRuleCache.containsKey(key)) {
      return AnalyzeRuleBase.stringRuleCache[key]!;
    }
    final ruleList = splitSourceRule(ruleStr, isJson: isJson);
    AnalyzeRuleBase.stringRuleCache[key] = ruleList;
    return ruleList;
  }

  /// 拆成一段段規則。[isJson] 是要解析的內容是 JSON（同 Legado 以目前內容
  /// 決定）：沒有前綴的段落是 JSON 路徑。
  List<SourceRule> splitSourceRule(String ruleStr, {bool isJson = false}) {
    final ruleList = <SourceRule>[];
    final jsPattern = RegExp(
      r'@js:|(<js>([\w\W]*?)</js>)',
      caseSensitive: false,
    );
    var start = 0;
    final matches = jsPattern.allMatches(ruleStr);

    for (final match in matches) {
      if (match.start > start) {
        final tmp = ruleStr.substring(start, match.start).trim();
        if (tmp.isNotEmpty) {
          ruleList.add(SourceRule(tmp, isJson: isJson));
        }
      }
      if (match.group(0)!.toLowerCase() == '@js:') {
        final jsCode = ruleStr.substring(match.end).trim();
        ruleList.add(SourceRule(jsCode, mode: Mode.js));
        return ruleList;
      } else {
        final jsCode = match.group(2)!.trim();
        ruleList.add(SourceRule(jsCode, mode: Mode.js));
      }
      start = match.end;
    }
    if (ruleStr.length > start) {
      final tmp = ruleStr.substring(start).trim();
      if (tmp.isNotEmpty) {
        ruleList.add(SourceRule(tmp, isJson: isJson));
      }
    }
    return ruleList;
  }

  String replaceRegexLogic(String result, SourceRule rule) {
    if (rule.replaceRegex.isEmpty) {
      return result;
    }
    RegExp? regex;
    if (AnalyzeRuleBase.regexCache.containsKey(rule.replaceRegex)) {
      regex = AnalyzeRuleBase.regexCache[rule.replaceRegex];
    } else {
      try {
        // Align with Legado's `toRegex()` default behavior: no DOTALL and no
        // multiline mode unless the rule itself encodes it.
        regex = RegExp(rule.replaceRegex);
        AnalyzeRuleBase.regexCache[rule.replaceRegex] = regex;
      } catch (e) {
        return result;
      }
    }
    if (regex == null) {
      return result;
    }
    if (rule.replaceFirst) {
      final match = regex.firstMatch(result);
      if (match == null) {
        return rule.rule.isEmpty ? '' : result;
      }
      var replacement = rule.replacement;
      for (var i = 0; i <= match.groupCount; i++) {
        replacement = replacement.replaceAll('\$$i', match.group(i) ?? '');
      }
      if (rule.rule.isEmpty) {
        return replacement;
      }
      return result.replaceFirstMapped(regex, (match) {
        var res = rule.replacement;
        for (var i = 0; i <= match.groupCount; i++) {
          res = res.replaceAll('\$$i', match.group(i) ?? '');
        }
        return res;
      });
    } else {
      return result.replaceAllMapped(regex, (match) {
        var res = rule.replacement;
        for (var i = 0; i <= match.groupCount; i++) {
          res = res.replaceAll('\$$i', match.group(i) ?? '');
        }
        return res;
      });
    }
  }

  String replaceRegexListItemLogic(String result, SourceRule rule) {
    if (!_isPureRegexCaptureReplacement(rule)) {
      return replaceRegexLogic(result, rule);
    }

    final regex = _buildCachedRegex(rule.replaceRegex);
    if (regex == null) {
      return result;
    }
    final match = regex.firstMatch(result);
    if (match == null) {
      return '';
    }
    var replacement = rule.replacement;
    for (var i = 0; i <= match.groupCount; i++) {
      replacement = replacement.replaceAll('\$$i', match.group(i) ?? '');
    }
    return replacement;
  }

  RegExp? _buildCachedRegex(String pattern) {
    if (AnalyzeRuleBase.regexCache.containsKey(pattern)) {
      return AnalyzeRuleBase.regexCache[pattern];
    }
    try {
      final regex = RegExp(pattern);
      AnalyzeRuleBase.regexCache[pattern] = regex;
      return regex;
    } catch (_) {
      return null;
    }
  }

  bool _isPureRegexCaptureReplacement(SourceRule rule) {
    return rule.replaceFirst &&
        rule.replacement.isNotEmpty &&
        RegExp(r'^(?:\$\d{1,2})+$').hasMatch(rule.replacement);
  }
}

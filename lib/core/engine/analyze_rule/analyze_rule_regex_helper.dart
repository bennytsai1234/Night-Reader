import '../parsers/java_regexp.dart';
import 'analyze_rule_base.dart';
import 'analyze_rule_support.dart';

/// AnalyzeRule 的正則工具與輔助邏輯擴展
mixin AnalyzeRuleRegexHelper on AnalyzeRuleBase {
  /// 同一條規則對 JSON 與網頁解析成不同模式，快取分開放。模式照目前內容
  /// 決定（同 Legado）；[mContent] 是規則 JS 交來的物件時照 JSON 讀它的欄位
  /// （Legado 對 JS 物件直接讀鍵）。[allInOne] 見 [splitSourceRule]。
  List<SourceRule> splitSourceRuleCacheString(
    String ruleStr, {
    dynamic mContent,
    bool allInOne = false,
  }) {
    if (ruleStr.isEmpty) {
      return [];
    }
    final isJson =
        isJsonContent(content) ||
        (mContent is Map && extractHtmlLikeRuleInput(mContent) == null);
    final wholeRegex = allInOne && ruleStr.startsWith(':');
    final key =
        '${isJson ? '\u0000json:' : ''}'
        '${wholeRegex ? '\u0000regex:' : ''}$ruleStr';
    if (AnalyzeRuleBase.stringRuleCache.containsKey(key)) {
      return AnalyzeRuleBase.stringRuleCache[key]!;
    }
    final ruleList = splitSourceRule(
      ruleStr,
      isJson: isJson,
      allInOne: allInOne,
    );
    AnalyzeRuleBase.stringRuleCache[key] = ruleList;
    return ruleList;
  }

  /// 拆成一段段規則。[isJson] 是要解析的內容是 JSON（同 Legado 以目前內容
  /// 決定）：沒有前綴的段落是 JSON 路徑。
  ///
  /// [allInOne] 是 getElement、getElements 的規則（同 Legado
  /// `splitSourceRule(ruleStr, allInOne = true)`）：第一個字是 `:` 時去掉
  /// 冒號，JS 以外的段落整段是正則（「整份內容正則」）。getString 這類取字
  /// 的規則沒有這種寫法，冒號開頭照網頁選擇器讀。
  List<SourceRule> splitSourceRule(
    String ruleStr, {
    bool isJson = false,
    bool allInOne = false,
  }) {
    final ruleList = <SourceRule>[];
    final jsPattern = RegExp(
      r'@js:|(<js>([\w\W]*?)</js>)',
      caseSensitive: false,
    );
    final wholeRegex = allInOne && ruleStr.startsWith(':');
    final mode = wholeRegex ? Mode.regex : Mode.defaultMode;
    var start = wholeRegex ? 1 : 0;
    final matches = jsPattern.allMatches(ruleStr);

    for (final match in matches) {
      if (match.start > start) {
        final tmp = ruleStr.substring(start, match.start).trim();
        if (tmp.isNotEmpty) {
          ruleList.add(SourceRule(tmp, mode: mode, isJson: isJson));
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
        ruleList.add(SourceRule(tmp, mode: mode, isJson: isJson));
      }
    }
    return ruleList;
  }

  /// 規則的 `##正則##取代`，同 Legado `AnalyzeRule.replaceRegex`；取代式照
  /// Java 展開（[javaReplacement]）：
  ///
  /// - `###`（[SourceRule.replaceFirst]）：找第一個對到的，只交出它換過的
  ///   樣子，對不到是空字串；正則或取代式寫壞時交出取代式。
  /// - `##`：每一處都換；正則或取代式寫壞時照純文字取代。
  String replaceRegexLogic(String result, SourceRule rule) {
    if (rule.replaceRegex.isEmpty) {
      return result;
    }
    final regex = _buildCachedRegex(rule.replaceRegex);
    if (rule.replaceFirst) {
      if (regex == null) return rule.replacement;
      final match = regex.firstMatch(result);
      if (match == null) return '';
      try {
        return javaReplacement(rule.replacement, match);
      } on FormatException {
        return rule.replacement;
      }
    }
    if (regex != null) {
      try {
        return result.replaceAllMapped(
          regex,
          (match) => javaReplacement(rule.replacement, match as RegExpMatch),
        );
      } on FormatException {
        // 同 Legado：取代式寫壞時退回純文字取代。
      }
    }
    return result.replaceAll(rule.replaceRegex, rule.replacement);
  }

  /// `##` 之後的正則，同 Legado `toRegex()`：照 Java 的預設與開頭旗標
  /// （[javaRegExp]）；寫錯的正則是 null。
  RegExp? _buildCachedRegex(String pattern) {
    if (AnalyzeRuleBase.regexCache.containsKey(pattern)) {
      return AnalyzeRuleBase.regexCache[pattern];
    }
    try {
      final regex = javaRegExp(pattern);
      AnalyzeRuleBase.regexCache[pattern] = regex;
      return regex;
    } catch (_) {
      return null;
    }
  }
}

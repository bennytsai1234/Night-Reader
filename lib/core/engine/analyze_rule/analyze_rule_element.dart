import 'analyze_rule_base.dart';
import 'analyze_rule_support.dart';
import 'analyze_rule_regex_helper.dart';
import '../parsers/analyze_by_regex.dart';
import '../parsers/analyze_by_css.dart';
import '../parsers/css/analyze_by_css_core.dart';

import 'package:night_reader/core/exception/app_exception.dart';

/// AnalyzeRule 的元素解析擴展
mixin AnalyzeRuleElement on AnalyzeRuleBase, AnalyzeRuleRegexHelper {
  String getString(
    String ruleStr, {
    dynamic mContent,
    bool isUrl = false,
    bool unescape = true,
  });

  /// 獲取單個元素，保留原始結果型別（`init` 這類規則要拿到 JSON 物件與
  /// 陣列本身）。CSS 與 XPath 規則同 Legado 交回找到的一整組元素（找不到時
  /// 是空的一組），不是只有第一個：書源寫 `java.getElement(...).length`。
  dynamic getElement(String ruleStr) {
    if (ruleStr.isEmpty) {
      return null;
    }

    // 同 Legado：只有空白的規則拆不出任何一段，沒有結果，不是整份內容。
    dynamic result;
    final ruleList = splitSourceRuleCacheString(ruleStr, allInOne: true);

    if (content != null && ruleList.isNotEmpty) {
      result = content;
      for (final sourceRule in ruleList) {
        // 同 Legado `putRule`：先存這一段的 @put（取到空的也存，蓋掉上一次
        // 存的值），再看上一段有沒有結果。
        if (sourceRule.putMap.isNotEmpty) {
          sourceRule.putMap.forEach(
            (key, valueRule) => put(key, getString(valueRule)),
          );
        }
        result = coerceNullInterimResult(result, sourceRule);
        if (result == null) {
          break;
        }

        final made = sourceRule.makeUp(result, this);
        final rule = made.rule;

        dynamic tempResult;
        try {
          switch (made.mode) {
            // 同 Legado：交回第一筆的分組（詳情頁 `init` 之後的 `$1`、`$2`
            // 讀的就是它）。
            case Mode.regex:
              tempResult = AnalyzeByRegex.getElement(
                stringifyRuleResult(result),
                rule.split('&&').where((s) => s.isNotEmpty).toList(),
              );
              break;
            case Mode.json:
              tempResult = sourceRule
                  .getAnalyzeByJSonPath(this, result)
                  .getObject(rule);
              break;
            case Mode.xpath:
              tempResult = sourceRule
                  .getAnalyzeByXPath(this, result)
                  .getElements(rule);
              break;
            case Mode.js:
              tempResult = evalJS(rule, result);
              break;
            default:
              tempResult = sourceRule
                  .getAnalyzeByJSoup(this, result)
                  .getElements(rule);
          }
        } catch (e) {
          throw ParsingException(
            e.toString(),
            rule: rule,
            mode: made.mode.name,
            url: baseUrl,
            originalError: e,
          );
        }

        // 動態規則（含 `{{ }}`）也照 Legado：沒結果就是沒有，不退回組好的規則
        // 文字（JS 規則是 JS 交回的結果、正則模式是正則找到的）。
        result = tempResult;

        if (result != null && made.replaceRegex.isNotEmpty) {
          result = replaceRegexLogic(stringifyRuleResult(result), made);
        }
      }
    }
    return result;
  }

  /// 獲取列表
  List<dynamic> getElements(String ruleStr) {
    if (ruleStr.isEmpty) {
      return [];
    }

    // 同 Legado：只有空白的規則拆不出任何一段，沒有結果，不是整份內容。
    dynamic result;
    final ruleList = splitSourceRuleCacheString(ruleStr, allInOne: true);

    if (content != null && ruleList.isNotEmpty) {
      result = content;
      for (final sourceRule in ruleList) {
        // 同 Legado `putRule`：先存這一段的 @put（取到空的也存，蓋掉上一次
        // 存的值），再看上一段有沒有結果。
        if (sourceRule.putMap.isNotEmpty) {
          sourceRule.putMap.forEach(
            (key, valueRule) => put(key, getString(valueRule)),
          );
        }
        result = coerceNullInterimResult(result, sourceRule);
        if (result == null) {
          break;
        }

        final made = sourceRule.makeUp(result, this);
        final rule = made.rule;

        dynamic tempResult;
        try {
          switch (made.mode) {
            case Mode.regex:
              tempResult = AnalyzeByRegex.getElements(
                stringifyRuleResult(result),
                rule.split('&&').where((s) => s.isNotEmpty).toList(),
              );
              break;
            case Mode.json:
              tempResult = sourceRule
                  .getAnalyzeByJSonPath(this, result)
                  .getElements(rule);
              break;
            case Mode.xpath:
              tempResult = sourceRule
                  .getAnalyzeByXPath(this, result)
                  .getElements(rule);
              break;
            case Mode.js:
              tempResult = evalJS(rule, result);
              break;
            default:
              tempResult = sourceRule
                  .getAnalyzeByJSoup(this, result)
                  .getElements(rule);
          }
        } catch (e) {
          throw ParsingException(
            e.toString(),
            rule: rule,
            mode: made.mode.name,
            url: baseUrl,
            originalError: e,
          );
        }

        // 動態規則（含 `{{ }}`）也照 Legado：沒結果就是沒有，不退回組好的規則
        // 文字（JS 規則是 JS 交回的結果、正則模式是正則找到的）。
        result = tempResult;

        if (result != null && made.replaceRegex.isNotEmpty) {
          if (result is List) {
            result = result
                .map((e) => replaceRegexLogic(stringifyRuleResult(e), made))
                .toList();
          } else {
            result = replaceRegexLogic(stringifyRuleResult(result), made);
          }
        }
      }
    }

    if (result is List) {
      return result;
    }
    // 沒有結果（JS 交回空的）就是空的一組，不是一個空字串。
    if (result == null || (result is String && result.isEmpty)) {
      return [];
    }
    return [result];
  }
}

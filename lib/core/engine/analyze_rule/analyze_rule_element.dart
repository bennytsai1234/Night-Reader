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

    log('⇒ 執行 getElement: $ruleStr');
    // 同 Legado：只有空白的規則拆不出任何一段，沒有結果，不是整份內容。
    dynamic result;
    final ruleList = splitSourceRuleCacheString(ruleStr, allInOne: true);

    if (content != null && ruleList.isNotEmpty) {
      result = content;
      for (final sourceRule in ruleList) {
        result = coerceNullInterimResult(result, sourceRule);
        if (result == null) {
          break;
        }

        if (sourceRule.putMap.isNotEmpty) {
          sourceRule.putMap.forEach((key, valueRule) {
            final val = getString(valueRule);
            if (val.isNotEmpty) {
              put(key, val);
              log('  ◇ 保存變數: $key = $val');
            }
          });
        }

        final rule = sourceRule.makeUpRule(result, this);
        log('  ◇ 模式: ${sourceRule.mode.name}, 規則: $rule');

        dynamic tempResult;
        try {
          switch (sourceRule.mode) {
            // 同 Legado：交回第一筆的分組（詳情頁 `init` 之後的 `$1`、`$2`
            // 讀的就是它）。
            case Mode.regex:
              tempResult = AnalyzeByRegex.getElement(
                result.toString(),
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
            mode: sourceRule.mode.name,
            url: baseUrl,
            originalError: e,
          );
        }

        // 動態規則（含 `{{ }}`）也照 Legado：沒結果就是沒有，不退回組好的規則
        // 文字（JS 規則是 JS 交回的結果、正則模式是正則找到的）。
        result = tempResult;

        if (result != null && sourceRule.replaceRegex.isNotEmpty) {
          log(
            '  ◇ 正則替換: ${sourceRule.replaceRegex} -> ${sourceRule.replacement}',
          );
          result = replaceRegexLogic(stringifyRuleResult(result), sourceRule);
        }

        final preview = result == null ? 'null' : stringifyRuleResult(result);
        log(
          '  └ 結果類型: ${result.runtimeType}, 預覽: '
          '${preview.length > 500 ? preview.substring(0, 500) : preview}',
        );
      }
    }
    return result;
  }

  /// 獲取列表
  List<dynamic> getElements(String ruleStr) {
    if (ruleStr.isEmpty) {
      return [];
    }

    log('⇒ 執行 getElements: $ruleStr');
    // 同 Legado：只有空白的規則拆不出任何一段，沒有結果，不是整份內容。
    dynamic result;
    final ruleList = splitSourceRuleCacheString(ruleStr, allInOne: true);

    if (content != null && ruleList.isNotEmpty) {
      result = content;
      for (final sourceRule in ruleList) {
        result = coerceNullInterimResult(result, sourceRule);
        if (result == null) {
          break;
        }

        if (sourceRule.putMap.isNotEmpty) {
          sourceRule.putMap.forEach((key, valueRule) {
            final val = getString(valueRule);
            if (val.isNotEmpty) {
              put(key, val);
              log('  ◇ 保存變數: $key = $val');
            }
          });
        }

        final rule = sourceRule.makeUpRule(result, this);
        log('  ◇ 模式: ${sourceRule.mode.name}, 規則: $rule');

        dynamic tempResult;
        try {
          switch (sourceRule.mode) {
            case Mode.regex:
              tempResult = AnalyzeByRegex.getElements(
                result.toString(),
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
            mode: sourceRule.mode.name,
            url: baseUrl,
            originalError: e,
          );
        }

        // 動態規則（含 `{{ }}`）也照 Legado：沒結果就是沒有，不退回組好的規則
        // 文字（JS 規則是 JS 交回的結果、正則模式是正則找到的）。
        result = tempResult;

        if (result != null && sourceRule.replaceRegex.isNotEmpty) {
          log('  ◇ 正則替換列表元素: ${sourceRule.replaceRegex}');
          if (result is List) {
            result = result
                .map(
                  (e) => replaceRegexLogic(stringifyRuleResult(e), sourceRule),
                )
                .toList();
          } else {
            result = replaceRegexLogic(stringifyRuleResult(result), sourceRule);
          }
        }
        log(
          '  └ 列表長度: ${result is List ? result.length : (result == null ? 0 : 1)}',
        );
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

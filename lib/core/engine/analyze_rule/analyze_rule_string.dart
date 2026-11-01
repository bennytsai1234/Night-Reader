import 'analyze_rule_base.dart';
import 'analyze_rule_support.dart';
import 'analyze_rule_regex_helper.dart';
import '../parsers/analyze_by_regex.dart';
import '../parsers/analyze_by_css.dart';
import '../parsers/css/analyze_by_css_core.dart';

import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/utils/network_utils.dart';

/// AnalyzeRule 的字串解析擴展
mixin AnalyzeRuleString on AnalyzeRuleBase, AnalyzeRuleRegexHelper {
  /// 獲取單個字串。[mContent] 有給時解析它，不給時解析目前內容（同 Legado
  /// `getString(rule, mContent, isUrl)`）。
  String getString(
    String ruleStr, {
    dynamic mContent,
    bool isUrl = false,
    bool unescape = true,
  }) {
    if (ruleStr.isEmpty) {
      return '';
    }

    log('⇒ 執行 getString: $ruleStr');
    final ruleList = splitSourceRuleCacheString(ruleStr);
    var result = mContent ?? content;

    if (result != null && ruleList.isNotEmpty) {
      for (final sourceRule in ruleList) {
        result = coerceNullInterimResult(result, sourceRule);
        if (result == null) {
          break;
        }

        try {
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
          if (_shouldTreatMapDynamicRuleAsLiteral(result, sourceRule, rule)) {
            tempResult = rule;
          } else if (isUrl && _looksLikeAnalyzeUrlLiteral(rule, sourceRule)) {
            tempResult = rule;
          } else if (rule.isNotEmpty || sourceRule.replaceRegex.isEmpty) {
            switch (sourceRule.mode) {
              case Mode.js:
                tempResult = evalJS(rule, result);
                break;
              case Mode.json:
                tempResult = sourceRule
                    .getAnalyzeByJSonPath(this, result)
                    .getString(rule);
                break;
              case Mode.xpath:
                tempResult = sourceRule
                    .getAnalyzeByXPath(this, result)
                    .getString(rule);
                break;
              case Mode.regex:
                if (sourceRule.replaceRegex.isEmpty) {
                  tempResult = rule;
                } else {
                  tempResult = AnalyzeByRegex.getString(
                    stringifyRuleResult(result),
                    rule,
                  );
                }
                break;
              default:
                tempResult = isUrl
                    ? sourceRule
                          .getAnalyzeByJSoup(this, result)
                          .getString0(rule, isUrl: true)
                    : sourceRule
                          .getAnalyzeByJSoup(this, result)
                          .getString(rule);
                if ((tempResult == null || tempResult.toString().isEmpty) &&
                    isJsonLikeRuleInput(result)) {
                  final jsonRule = buildJsonFallbackRule(rule);
                  if (jsonRule != null) {
                    tempResult = sourceRule
                        .getAnalyzeByJSonPath(this, result)
                        .getString(jsonRule);
                  }
                }
            }
          } else {
            // rule 為空 + replaceRegex 非空 → 內容直通，交由 replaceRegex 處理
            // (對標 legado Kotlin AnalyzeRule.getString 空 rule 行為)
            tempResult = result;
          }

          if (sourceRule.isDynamic &&
              (tempResult == null || tempResult.toString().isEmpty)) {
            result = rule;
          } else {
            result = tempResult;
          }

          if (result != null && sourceRule.replaceRegex.isNotEmpty) {
            log('  ◇ 正則替換: ${sourceRule.replaceRegex}');
            result = replaceRegexLogic(stringifyRuleResult(result), sourceRule);
          }

          final preview = result == null ? 'null' : stringifyRuleResult(result);
          log(
            '  └ 字串預覽: ${preview.length > 500 ? preview.substring(0, 500) : preview}',
          );
        } catch (e) {
          if (e is ParsingException) rethrow;
          throw ParsingException(
            '解析字串失敗',
            rule: sourceRule.rule,
            mode: sourceRule.mode.name,
            url: baseUrl,
            originalError: e,
          );
        }
      }
    }

    var str = result == null ? '' : stringifyRuleResult(result);
    if (unescape && str.contains('&')) {
      str = AnalyzeRuleBase.htmlUnescape.convert(str);
    }
    if (isUrl && str.isEmpty) {
      return redirectUrl ?? baseUrl ?? '';
    }
    if (isUrl) {
      return NetworkUtils.getAbsoluteURL(redirectUrl ?? baseUrl, str);
    }
    return str;
  }

  bool _looksLikeAnalyzeUrlLiteral(String rule, SourceRule sourceRule) {
    final trimmed = rule.trimLeft();
    return sourceRule.mode == Mode.xpath &&
        trimmed.startsWith('/') &&
        trimmed.contains(',{');
  }

  bool _shouldTreatMapDynamicRuleAsLiteral(
    dynamic result,
    SourceRule sourceRule,
    String rule,
  ) {
    if (result is! Map ||
        sourceRule.mode == Mode.js ||
        sourceRule.paramSize <= 1) {
      return false;
    }

    final trimmed = rule.trimLeft();
    if (trimmed.isEmpty || trimmed.startsWith('//')) {
      return false;
    }

    if (_looksLikeAnalyzeUrlLiteral(rule, sourceRule)) {
      return true;
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return true;
    }

    if (trimmed.startsWith('./') || trimmed.startsWith('../')) {
      return true;
    }

    if (trimmed.startsWith('?')) {
      return true;
    }

    if (trimmed.startsWith('/')) {
      return trimmed.contains('?') ||
          RegExp(r"^/[A-Za-z0-9._~!$&'()*+,;=:@%/-]+$").hasMatch(trimmed);
    }

    return false;
  }

  /// 獲取字串列表，[mContent] 同 [getString]。
  List<String> getStringList(
    String ruleStr, {
    dynamic mContent,
    bool isUrl = false,
  }) {
    if (ruleStr.isEmpty) {
      return [];
    }
    log('⇒ 執行 getStringList: $ruleStr');

    final ruleList = splitSourceRuleCacheString(ruleStr);
    var result = mContent ?? content;

    if (result != null && ruleList.isNotEmpty) {
      for (final sourceRule in ruleList) {
        result = coerceNullInterimResult(result, sourceRule);
        if (result == null) {
          break;
        }

        try {
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
          final currentInput = result;

          switch (sourceRule.mode) {
            case Mode.js:
              result = evalJS(rule, result);
              break;
            case Mode.json:
              result = sourceRule
                  .getAnalyzeByJSonPath(this, result)
                  .getStringList(rule);
              break;
            case Mode.xpath:
              result = sourceRule
                  .getAnalyzeByXPath(this, result)
                  .getStringList(rule);
              break;
            case Mode.regex:
              result = [rule];
              break;
            default:
              result = sourceRule
                  .getAnalyzeByJSoup(this, currentInput)
                  .getStringList(rule);
              if (result is List &&
                  result.isEmpty &&
                  isJsonLikeRuleInput(currentInput)) {
                final jsonRule = buildJsonFallbackRule(rule);
                if (jsonRule != null) {
                  result = sourceRule
                      .getAnalyzeByJSonPath(this, currentInput)
                      .getStringList(jsonRule);
                }
              }
          }

          if (sourceRule.replaceRegex.isNotEmpty) {
            log('  ◇ 正則替換列表: ${sourceRule.replaceRegex}');
            if (result is List) {
              result = result
                  .map(
                    (e) => replaceRegexListItemLogic(
                      stringifyRuleResult(e),
                      sourceRule,
                    ),
                  )
                  .toList();
            } else {
              result = replaceRegexLogic(
                result == null ? '' : stringifyRuleResult(result),
                sourceRule,
              );
            }
          }
        } catch (e) {
          if (e is ParsingException) rethrow;
          throw ParsingException(
            '解析字串列表失敗',
            rule: sourceRule.rule,
            mode: sourceRule.mode.name,
            url: baseUrl,
            originalError: e,
          );
        }
      }
    }

    if (result is List) {
      final values = result.map((e) => stringifyRuleResult(e));
      return _normalizeStringList(values, isUrl: isUrl);
    }
    if (result == null) {
      return [];
    }
    final str = stringifyRuleResult(result);
    return _normalizeStringList(
      str.split('\n').where((s) => s.isNotEmpty),
      isUrl: isUrl,
    );
  }

  List<String> _normalizeStringList(
    Iterable<String> values, {
    required bool isUrl,
  }) {
    final nonEmpty = values.where((value) => value.isNotEmpty);
    // 同 Legado：網址補成完整網址並去掉重複的；一般文字照原樣，重複的留著。
    if (!isUrl) return nonEmpty.toList();
    return nonEmpty
        .map(
          (value) => NetworkUtils.getAbsoluteURL(redirectUrl ?? baseUrl, value),
        )
        .toSet()
        .toList();
  }
}

import 'package:html/dom.dart';
import 'package:night_reader/core/engine/rule_analyzer.dart';
import 'analyze_by_css_base.dart';
import 'analyze_by_css_support.dart';
import 'analyze_by_css_helper.dart';

/// AnalyzeByCss 的核心解析邏輯擴展
extension AnalyzeByCssCore on AnalyzeByCssBase {
  /// 獲取列表
  List<Element> getElements(String rule) {
    if (rule.isEmpty) return [];

    final sourceRule = SourceRule(rule);
    final ruleAnalyzes = RuleAnalyzer(sourceRule.elementsRule);
    final ruleStrS = ruleAnalyzes.splitRule(['&&', '||', '%%']);

    final elementsList = <List<Element>>[];
    if (sourceRule.isCss) {
      for (var ruleStr in ruleStrS) {
        ruleStr = ruleStr.trim();
        if (ruleStr.isEmpty) continue;
        final tempS = querySelectorAllCompat(element, ruleStr);
        elementsList.add(tempS);
        if (tempS.isNotEmpty && ruleAnalyzes.elementsType == '||') break;
      }
    } else {
      for (var ruleStr in ruleStrS) {
        ruleStr = ruleStr.trim();
        if (ruleStr.isEmpty) continue;
        final rsRule = RuleAnalyzer(ruleStr);
        rsRule.trim();
        final rs = rsRule.splitRule(['@']);

        List<Element> el;
        if (rs.length > 1) {
          el = [element];
          for (var rl in rs) {
            rl = rl.trim();
            if (rl.isEmpty) continue;
            final es = <Element>[];
            for (final et in el) {
              es.addAll(getElementsSingle(et, rl));
            }
            el = es;
          }
        } else {
          el = getElementsSingle(element, ruleStr);
        }

        elementsList.add(el);
        if (el.isNotEmpty && ruleAnalyzes.elementsType == '||') break;
      }
    }

    if (elementsList.isEmpty) return [];

    final result = <Element>[];
    if (ruleAnalyzes.elementsType == '%%') {
      final firstListSize = elementsList[0].length;
      for (var i = 0; i < firstListSize; i++) {
        for (final es in elementsList) {
          if (i < es.length) result.add(es[i]);
        }
      }
    } else {
      for (final es in elementsList) {
        result.addAll(es);
      }
    }
    return result;
  }

  /// 獲取所有內容列表
  List<String> getStringList(String ruleStr) {
    if (ruleStr.isEmpty) return [];

    final sourceRule = SourceRule(ruleStr);
    if (sourceRule.elementsRule.isEmpty) {
      final data = getElementData(element);
      return data.isEmpty ? [] : [data];
    }

    final ruleAnalyzes = RuleAnalyzer(sourceRule.elementsRule);
    final ruleStrS = ruleAnalyzes.splitRule(['&&', '||', '%%']);

    final results = <List<String>>[];
    for (var ruleStrX in ruleStrS) {
      ruleStrX = ruleStrX.trim();
      if (ruleStrX.isEmpty) continue;

      List<String>? temp;
      if (sourceRule.isCss) {
        final lastIndex = ruleStrX.lastIndexOf('@');
        if (lastIndex != -1) {
          final cssSelector = ruleStrX.substring(0, lastIndex);
          final attr = ruleStrX.substring(lastIndex + 1);
          temp = getResultLast(
            querySelectorAllCompat(element, cssSelector),
            attr,
          );
        } else {
          temp = getResultLast(
            querySelectorAllCompat(element, ruleStrX),
            'text',
          );
        }
      } else {
        temp = getResultList(ruleStrX);
      }

      if (temp != null && temp.isNotEmpty) {
        results.add(temp);
        if (ruleAnalyzes.elementsType == '||') break;
      }
    }

    if (results.isEmpty) return [];

    final textS = <String>[];
    if (ruleAnalyzes.elementsType == '%%') {
      final firstListSize = results[0].length;
      for (var i = 0; i < firstListSize; i++) {
        for (final temp in results) {
          if (i < temp.length) textS.add(temp[i]);
        }
      }
    } else {
      for (final temp in results) {
        textS.addAll(temp);
      }
    }
    return textS;
  }

  String? getString(String ruleStr) {
    if (ruleStr.isEmpty) return null;
    final list = getStringList(ruleStr);
    if (list.isEmpty) return null;
    if (list.length == 1) return list.first;
    return list.join('\n');
  }

  String getString0(String ruleStr, {bool isUrl = false}) {
    final list = getStringList(ruleStr);
    if (list.isEmpty) return '';
    return list.first;
  }

  List<String>? getResultList(String ruleStr) {
    if (ruleStr.isEmpty) return null;

    var elements = [element];
    final rule = RuleAnalyzer(ruleStr);
    rule.trim();
    final rules = rule.splitRule(['@']);

    final last = rules.length - 1;
    for (var i = 0; i < last; i++) {
      final es = <Element>[];
      for (final elt in elements) {
        es.addAll(getElementsSingle(elt, rules[i]));
      }
      elements = es;
    }

    if (elements.isEmpty) return null;
    return getResultLast(elements, rules[last]);
  }
}

import 'dart:convert';
import 'package:json_path/json_path.dart';
import 'package:night_reader/core/engine/rule_analyzer.dart';

/// AnalyzeByJsonPath - JsonPath 解析器
/// (原 Android model/analyzeRule/AnalyzeByJSonPath.kt) (6KB)
///
/// 使用 Dart `json_path` 套件
class AnalyzeByJsonPath {
  dynamic _jsonData;

  AnalyzeByJsonPath([dynamic json]) {
    if (json != null) {
      setContent(json);
    }
  }

  void setContent(dynamic content) {
    if (content is String) {
      try {
        _jsonData = jsonDecode(content);
      } catch (e) {
        _jsonData = content;
      }
    } else {
      _jsonData = content;
    }
  }

  /// 預處理規則，去除 @json: 前綴
  String _preProcessRule(String rule) {
    rule = rule.trim();
    if (rule.toLowerCase().startsWith('@json:')) {
      rule = rule.substring(6).trim();
    }
    if (rule.startsWith(r'$.[')) {
      return '\$${rule.substring(2)}';
    }
    return rule;
  }

  /// Get a string result from JsonPath
  String? getString(String rule) {
    rule = _preProcessRule(rule);
    if (rule.isEmpty) return null;

    final ruleAnalyzer = RuleAnalyzer(rule, isCode: true);
    final rules = ruleAnalyzer.splitRule(['&&', '||']);

    if (rules.length == 1) {
      ruleAnalyzer.reSetPos();
      // 替換所有 {$.rule...}
      final result = ruleAnalyzer.innerRule(
        r'{$.',
        fr: (it) => getString(it.startsWith('\$') ? it : '\$.$it'),
      );

      // 如果替換後結果與原規則相同，說明沒有嵌套規則，或者是純 JsonPath 規則
      if (result == rule) {
        try {
          final path = JsonPath(rule);
          final matches = path.read(_jsonData);
          if (matches.isEmpty) return null;

          final values = matches.map((m) => m.value).toList();
          if (values.length == 1) {
            return values[0].toString(); // 自動轉字串 (含數字)
          } else {
            return values.map((v) => v.toString()).join('\n');
          }
        } catch (e) {
          // 如果解析失敗且包含 {$.，則可能真的是沒匹配到
          return null;
        }
      }
      return result;
    } else {
      final textList = <String>[];
      for (final rl in rules) {
        final temp = getString(rl);
        if (temp != null && temp.isNotEmpty) {
          textList.add(temp);
          if (ruleAnalyzer.elementsType == '||') {
            break;
          }
        }
      }
      return textList.isEmpty ? null : textList.join('\n');
    }
  }

  /// Get a list of elements matching the JsonPath
  List<dynamic> getElements(String rule) {
    rule = _preProcessRule(rule);
    if (rule.isEmpty) return [];

    final ruleAnalyzer = RuleAnalyzer(rule, isCode: true);
    final rules = ruleAnalyzer.splitRule(['&&', '||', '%%']);

    if (rules.length == 1) {
      ruleAnalyzer.reSetPos();
      final ruleStr = ruleAnalyzer.innerRule(
        r'{$.',
        fr: (it) => getString(it.startsWith('\$') ? it : '\$.$it'),
      );

      if (ruleStr == rule) {
        try {
          final path = JsonPath(rule);
          final matches = path.read(_jsonData);
          final values = <dynamic>[];
          for (final match in matches) {
            final value = match.value;
            if (value is Iterable && value is! Map && value is! String) {
              values.addAll(value);
            } else {
              values.add(value);
            }
          }
          return values;
        } catch (e) {
          return [];
        }
      } else {
        // 如果有嵌套替換，結果通常是個字串
        return [ruleStr];
      }
    } else {
      final results = <List<dynamic>>[];
      for (final rl in rules) {
        final temp = getElements(rl);
        if (temp.isNotEmpty) {
          results.add(temp);
          if (ruleAnalyzer.elementsType == '||') {
            break;
          }
        }
      }

      if (results.isEmpty) return [];

      final result = <dynamic>[];
      if (ruleAnalyzer.elementsType == '%%') {
        final firstListSize = results[0].length;
        for (var i = 0; i < firstListSize; i++) {
          for (final temp in results) {
            if (i < temp.length) {
              result.add(temp[i]);
            }
          }
        }
      } else {
        for (final temp in results) {
          result.addAll(temp);
        }
      }
      return result;
    }
  }

  /// Get a single object
  dynamic getObject(String rule) {
    final list = getElements(rule);
    return list.isNotEmpty ? list.first : null;
  }

  /// Get a list of strings
  List<String> getStringList(String rule) {
    final list = getElements(rule);
    return list.map((e) => e.toString()).toList();
  }
}

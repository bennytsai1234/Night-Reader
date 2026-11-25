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
    return rule;
  }

  /// 照 Legado 用的 Jayway JsonPath 編譯路徑：不是 `$`、`@` 開頭的補上
  /// `$.`（`title` 就是 `$.title`、`[0]` 就是 `$[0]`）。
  static JsonPath _compile(String rule) {
    var path = rule;
    if (!path.startsWith(r'$') && !path.startsWith('@')) path = '\$.$path';
    if (path.startsWith(r'$.[')) path = '\$${path.substring(2)}';
    return JsonPath(path);
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
          final path = _compile(rule);
          final matches = path.read(_jsonData);
          if (matches.isEmpty) return null;

          final values = matches.map((m) => m.value).toList();
          if (values.length == 1) {
            // 對到的是陣列時一項一行，同 Legado `ob.joinToString("\n")`；
            // 物件與陣列的每一項照 JsonSmart 的 `toString()` 交出 JSON。
            final value = values[0];
            return value is List
                ? value.map(_jsonText).join('\n')
                : _jsonText(value);
          } else {
            return values.map(_jsonText).join('\n');
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
          final path = _compile(rule);
          final matches = path.read(_jsonData);
          // 同 Legado `getList`（Jayway `read`）：確定路徑對到陣列時是陣列裡
          // 的每一筆；其他路徑是對到的每一個值，值本身是陣列也不展開。
          if (!_isDefinite(rule)) {
            return [for (final match in matches) match.value];
          }
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

  /// 單一個值，同 Legado `getObject`（Jayway 的 `read`）：路徑對到的值照
  /// 原樣交出，對到陣列就是整個陣列，不展開成一筆筆再取第一筆；對到好幾個
  /// 時是它們的清單。組合規則（`||`、`&&`、`%%`）與內嵌的 `{$.…}` 照
  /// [getElements] 取第一筆。
  dynamic getObject(String rule) {
    rule = _preProcessRule(rule);
    if (rule.isEmpty) return null;
    if (rule.contains(r'{$.') ||
        RuleAnalyzer(rule, isCode: true).splitRule(['&&', '||', '%%']).length >
            1) {
      final list = getElements(rule);
      return list.isNotEmpty ? list.first : null;
    }
    try {
      final matches = _compile(rule).read(_jsonData).toList();
      if (!_isDefinite(rule)) return [for (final match in matches) match.value];
      return matches.isEmpty ? null : matches.first.value;
    } catch (_) {
      return null;
    }
  }

  /// Jayway 的「確定路徑」：只會對到一個值（沒有 `..`、`*`、篩選、切片、
  /// 好幾個索引或名稱）。確定路徑交出那個值，其他的交出對到的清單，筆數
  /// 是 0 或 1 也一樣。
  static bool _isDefinite(String rule) {
    if (rule.contains('..')) return false;
    String? quote;
    var depth = 0;
    for (var i = 0; i < rule.length; i++) {
      final c = rule[i];
      if (quote != null) {
        if (c == '\\') {
          i++;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '[') {
        depth++;
      } else if (c == ']') {
        depth--;
      } else if (c == '*') {
        return false;
      } else if (depth > 0 && (c == ',' || c == ':' || c == '?')) {
        return false;
      }
    }
    return true;
  }

  /// Get a list of strings
  List<String> getStringList(String rule) {
    final list = getElements(rule);
    return list.map(_jsonText).toList();
  }

  /// 對到的值是 JsonSmart 的物件或陣列時，Legado 的 `toString()` 就是
  /// JSON；夜讀要交出 JSON 文字，後面的 `@js:JSON.parse(result)` 才接得上。
  static String _jsonText(dynamic value) =>
      value is Map || value is List ? jsonEncode(value) : '$value';
}

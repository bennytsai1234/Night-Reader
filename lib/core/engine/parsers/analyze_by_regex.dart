/// AnalyzeByRegex - 正則表達式解析器
/// (原 Android model/analyzeRule/AnalyzeByRegex.kt) (2KB)
///
/// 支援 Legado 的 ##pattern## 格式
class AnalyzeByRegex {
  static RegExp _buildRegExp(
    String pattern, {
    bool multiLine = true,
    bool dotAll = true,
    bool caseSensitive = true,
  }) {
    final inlineFlags = RegExp(r'^\(\?([ims]+)\)');
    final match = inlineFlags.firstMatch(pattern);
    if (match != null) {
      final flags = match.group(1) ?? '';
      if (flags.contains('i')) {
        caseSensitive = false;
      }
      if (flags.contains('m')) {
        multiLine = true;
      }
      if (flags.contains('s')) {
        dotAll = true;
      }
      pattern = pattern.substring(match.end);
    }
    return RegExp(
      pattern,
      multiLine: multiLine,
      dotAll: dotAll,
      caseSensitive: caseSensitive,
    );
  }

  /// 獲取單個匹配項及其分組
  static List<String>? getElement(
    String res,
    List<String> regs, {
    int index = 0,
  }) {
    if (index >= regs.length) return null;

    final regExp = _buildRegExp(regs[index]);
    final match = regExp.firstMatch(res);
    if (match == null) return null;

    if (index + 1 == regs.length) {
      final info = <String>[];
      for (var i = 0; i <= match.groupCount; i++) {
        info.add(match.group(i) ?? '');
      }
      return info;
    } else {
      final result = StringBuffer();
      final allMatches = regExp.allMatches(res);
      for (final m in allMatches) {
        result.write(m.group(0) ?? '');
      }
      return getElement(result.toString(), regs, index: index + 1);
    }
  }

  /// 獲取所有匹配項列表及其分組
  static List<List<String>> getElements(
    String res,
    List<String> regs, {
    int index = 0,
  }) {
    if (index >= regs.length) return [];

    final regExp = _buildRegExp(regs[index]);
    final allMatches = regExp.allMatches(res);
    if (allMatches.isEmpty) return [];

    if (index + 1 == regs.length) {
      final matches = <List<String>>[];
      for (final match in allMatches) {
        final info = <String>[];
        for (var i = 0; i <= match.groupCount; i++) {
          info.add(match.group(i) ?? '');
        }
        matches.add(info);
      }
      return matches;
    } else {
      final result = StringBuffer();
      for (final match in allMatches) {
        result.write(match.group(0) ?? '');
      }
      return getElements(result.toString(), regs, index: index + 1);
    }
  }

  /// 執行正則替換 ##regex##replacement
  /// 支援 $1, $2 等分組引用
  static String replace(String res, String rule) {
    final parts = rule.split('##');
    if (parts.length < 2) return res;

    // parts[0] 為原始規則(可選)，parts[1] 為 regex，parts[2] 為 replacement
    // 注意: split 會導致第一個為空字串，如果是以 ## 開頭
    final regexStr = parts[1];
    final replacement = parts.length > 2 ? parts[2] : '';

    final regExp = _buildRegExp(regexStr);
    return res.replaceAllMapped(regExp, (match) {
      var result = replacement;
      // 替換 $0, $1, $2...
      for (var i = 0; i <= match.groupCount; i++) {
        result = result.replaceAll('\$$i', match.group(i) ?? '');
      }
      return result;
    });
  }

  /// 獲取單個合併字串
  static String getString(String res, String rule) {
    if (rule.contains('##')) {
      return replace(res, rule);
    }

    final regs = rule.split('&&').where((s) => s.isNotEmpty).toList();
    final elements = getElements(res, regs);
    if (elements.isEmpty) return '';
    return elements.map((e) => e[0]).join('\n');
  }
}

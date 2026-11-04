import 'java_regexp.dart';

/// AnalyzeByRegex - 正則表達式解析器
/// (原 Android model/analyzeRule/AnalyzeByRegex.kt)
///
/// 「整份內容正則」（getElement、getElements 的規則以 `:` 開頭）用它：
/// `&&` 隔開的每一段依序套用，前面幾段把找到的字串接起來交給下一段，
/// 最後一段交回每一筆的分組（第 0 個是整段）。
class AnalyzeByRegex {
  /// 獲取單個匹配項及其分組
  static List<String>? getElement(
    String res,
    List<String> regs, {
    int index = 0,
  }) {
    if (index >= regs.length) return null;

    final regExp = javaRegExp(regs[index]);
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

    final regExp = javaRegExp(regs[index]);
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
}

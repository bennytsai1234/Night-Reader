import 'rule_analyzer_base.dart';
import 'rule_analyzer_match.dart';

/// RuleAnalyzer 的範圍提取邏輯擴展
mixin RuleAnalyzerRange on RuleAnalyzerBase, RuleAnalyzerMatch {
  /// 替換內嵌規則 (對標 Android RuleAnalyzer.innerRule)
  String innerRule(
    String inner, {
    int startStep = 1,
    int endStep = 1,
    required String? Function(String) fr,
  }) {
    final st = StringBuffer();

    while (consumeTo(inner)) {
      final posPre = pos; // 記錄匹配位置
      if (chompCodeBalanced('{', '}')) {
        final content = queue.substring(posPre + startStep, pos - endStep);
        final frv = fr(content);
        if (frv != null && frv.isNotEmpty) {
          st.write(queue.substring(startX, posPre));
          st.write(frv);
          startX = pos;
          continue;
        }
      }
      pos += inner.length; // 不平衡則跳過
    }

    if (startX == 0) return queue;
    st.write(queue.substring(startX));
    return st.toString();
  }

  /// 替換內嵌規則 (雙邊標誌版) (對標 Android RuleAnalyzer.innerRule(startStr, endStr))
  String innerRuleRange(
    String startStr,
    String endStr, {
    required String? Function(String) fr,
  }) {
    final st = StringBuffer();
    while (consumeTo(startStr)) {
      pos += startStr.length;
      final posPre = pos;
      if (consumeTo(endStr)) {
        final content = queue.substring(posPre, pos);
        final frv = fr(content);
        st.write(queue.substring(startX, posPre - startStr.length));
        st.write(frv ?? '');
        pos += endStr.length;
        startX = pos;
      }
    }

    if (startX == 0) return queue;
    st.write(queue.substring(startX));
    return st.toString();
  }
}

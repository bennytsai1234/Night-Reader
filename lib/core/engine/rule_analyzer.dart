import 'rule_analyzer/rule_analyzer_base.dart';
import 'rule_analyzer/rule_analyzer_match.dart';
import 'rule_analyzer/rule_analyzer_split.dart';
import 'rule_analyzer/rule_analyzer_range.dart';

export 'rule_analyzer/rule_analyzer_base.dart';
export 'rule_analyzer/rule_analyzer_match.dart';
export 'rule_analyzer/rule_analyzer_split.dart';
export 'rule_analyzer/rule_analyzer_range.dart';

/// RuleAnalyzer - 規則字串切割引擎 (重構後)
/// (原 Android model/analyzeRule/RuleAnalyzer.kt)
class RuleAnalyzer extends RuleAnalyzerBase
    with RuleAnalyzerMatch, RuleAnalyzerSplit, RuleAnalyzerRange {
  RuleAnalyzer(super.data, {super.isCode});
}

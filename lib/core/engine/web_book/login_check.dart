import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/network/str_response.dart';

/// 執行書源的登入檢查（`loginCheckJs`），同 Legado：`result` 是剛抓到的
/// 回應（可呼叫 `body()`、`code()`、`url()`），傳回的回應取代它，例如通過
/// 驗證後重抓的。傳回別的東西時照用原本的回應。
StrResponse runLoginCheckJs(
  BookSource source,
  StrResponse response, {
  dynamic ruleData,
}) {
  final checkJs = source.loginCheckJs;
  if (checkJs == null || checkJs.isEmpty) return response;
  final rule = AnalyzeRule(source: source, ruleData: ruleData);
  try {
    final evaluated = rule.evalJS(checkJs, response);
    return evaluated is StrResponse ? evaluated : response;
  } on RuleJsException catch (error) {
    throw ParsingException(
      '書源的登入檢查（loginCheckJs）出錯',
      url: response.url,
      originalError: error,
    );
  } finally {
    rule.dispose();
  }
}

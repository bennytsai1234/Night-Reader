import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/network/str_response.dart';
import 'package:night_reader/core/utils/network_utils.dart';

/// 執行書源的登入檢查（`loginCheckJs`），同 Legado（`analyzeUrl.evalJS`）：
/// `result` 是 [request] 剛抓到的回應（可呼叫 `body()`、`code()`、`url()`），
/// `key`、`page`、`baseUrl`（請求網址的站點）、`book` 照這次請求；傳回的回應
/// 取代抓到的，例如通過驗證後重抓的。傳回別的東西時照用原本的回應。
StrResponse runLoginCheckJs(AnalyzeUrl request, StrResponse response) {
  final checkJs = request.source?.loginCheckJs;
  if (checkJs == null || checkJs.isEmpty) return response;
  final rule = AnalyzeRule(source: request.source, ruleData: request.ruleData)
    ..key = request.key
    ..page = request.page ?? 1
    ..baseUrl = NetworkUtils.getBaseUrl(request.url) ?? request.baseUrl;
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

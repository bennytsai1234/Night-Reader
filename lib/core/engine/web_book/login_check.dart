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

/// 判斷目錄或正文是不是被登入牆擋住（ADR 0038）。頁面上有「請先登錄」這類
/// 字樣只拿來說明解析不出東西的原因：網站頁首的登入連結不會讓解析得出
/// 內容的頁面失敗。被擋住的第一頁就解析不出東西、也沒有下一頁，只看第一頁。
final class LoginWall {
  String? _url;

  /// 正文只剩這麼短、內容又是登入提示時，當成被擋住：付費或要登入的章節
  /// 常在正文區塊只放一句「請先登錄後閱讀」。
  static const int promptOnlyLength = 200;

  /// 記下第一頁。
  void note(StrResponse response) {
    if (response.looksLikeLoginRequired) _url ??= response.url;
  }

  /// 目錄解析不出章節，而第一頁像登入牆時丟出 [LoginCheckException]。
  void explainToc({required bool empty}) {
    if (empty && _url != null) {
      throw LoginCheckException('目錄需要登入後閱讀', sourceUrl: _url);
    }
  }

  /// 正文解析不出東西而第一頁像登入牆，或正文只有一句登入提示時丟出
  /// [LoginCheckException]。
  void explainContent(String content) {
    final text = content.trim();
    final blocked =
        (text.isEmpty && _url != null) ||
        (text.length <= promptOnlyLength &&
            StrResponse.mentionsLoginRequired(text));
    if (blocked) throw LoginCheckException('正文需要登入後閱讀', sourceUrl: _url);
  }
}

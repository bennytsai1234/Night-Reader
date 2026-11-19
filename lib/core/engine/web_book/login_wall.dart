import 'package:dio/dio.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/analyze_url.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/network/str_response.dart';
import 'package:night_reader/core/utils/network_utils.dart';

/// 抓到要解析的一頁（搜尋、發現、詳情、目錄、正文）之後：先跑書源的登入
/// 檢查（`loginCheckJs`），再確認網站回的不是錯誤碼。
///
/// 登入檢查同 Legado（`analyzeUrl.evalJS`）：`result` 是 [request] 剛抓到
/// 的回應（可呼叫 `body()`、`code()`、`url()`，4xx、5xx 也照樣交給它），
/// `key`、`page`、`baseUrl`（請求網址的站點）、`book` 照這次請求，`java` 是
/// 這個請求（`java.initUrl()`、`java.getStrResponse()` 重抓）；傳回的回應
/// 取代抓到的，例如通過驗證後重抓的。傳回別的東西時照用原本的回應。
///
/// 登入檢查之後還是 4xx、5xx 的頁面不解析，照錯誤碼丟出。這裡和 Legado
/// 不同：Legado 照樣解析，錯誤頁的標題會變成一本叫「403 Forbidden」的書；
/// 2026-11-01 用源倉庫 799 個書源實跑，照 Legado 解析錯誤頁沒有讓任何一個
/// 書源因此讀得到，反而有 4 個把錯誤頁當成搜尋結果。規則 JS 自己發的請求
/// （`java.ajax` 這類）照 Legado 拿到錯誤碼的頁面，由規則決定怎麼處理。
StrResponse runLoginCheckJs(AnalyzeUrl request, StrResponse response) {
  final checked = _loginChecked(request, response);
  if (!checked.isSuccessful) {
    throw DioException.badResponse(
      statusCode: checked.raw.statusCode ?? 0,
      requestOptions: checked.raw.requestOptions,
      response: checked.raw,
    );
  }
  return checked;
}

StrResponse _loginChecked(AnalyzeUrl request, StrResponse response) {
  final checkJs = request.source?.loginCheckJs;
  if (checkJs == null || checkJs.isEmpty) return response;
  final rule = AnalyzeRule(source: request.source, ruleData: request.ruleData)
    ..key = request.key
    ..page = request.page ?? 1
    ..baseUrl = NetworkUtils.getBaseUrl(request.url) ?? request.baseUrl
    ..urlContext = request;
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

/// 判斷目錄或正文的一頁是不是被登入牆擋住（ADR 0038）。頁面上有「請先
/// 登錄」這類字樣只拿來說明這一頁解析不出東西的原因：網站頁首的登入連結
/// 不會讓解析得出內容的頁面失敗。每一頁都要判斷：有的網站第一頁免費、
/// 後面幾頁要登入，只看第一頁會把半章當成一整章。
abstract final class LoginWall {
  /// 正文只剩這麼短、內容又是登入提示時，當成被擋住：付費或要登入的章節
  /// 常在正文區塊只放一句「請先登錄後閱讀」。
  static const int promptOnlyLength = 200;

  /// 目錄的一頁 [page] 解析不出章節（[empty]），而那一頁像登入牆時丟出
  /// [LoginCheckException]。
  static void checkToc(StrResponse page, {required bool empty}) {
    if (empty && page.looksLikeLoginRequired) {
      throw LoginCheckException('目錄需要登入後閱讀', sourceUrl: page.url);
    }
  }

  /// 正文的一頁 [page] 解析出 [content]：解析不出東西而那一頁像登入牆，
  /// 或只有一句登入提示時丟出 [LoginCheckException]。[page] 為 null 時只看
  /// 內容（整章合併、套完替換規則之後）。
  static void checkContent(StrResponse? page, String content) {
    final text = content.trim();
    final blocked = text.isEmpty
        ? page?.looksLikeLoginRequired ?? false
        : text.length <= promptOnlyLength &&
              StrResponse.mentionsLoginRequired(text);
    if (blocked) {
      throw LoginCheckException('正文需要登入後閱讀', sourceUrl: page?.url);
    }
  }
}

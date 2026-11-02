import 'package:night_reader/core/models/rule_data_interface.dart';
import 'package:night_reader/core/models/book_source.dart';

// 導入拆分後的模組
import 'analyze_rule/analyze_rule_base.dart';
import 'analyze_rule/analyze_rule_element.dart';
import 'analyze_rule/analyze_rule_regex_helper.dart';
import 'analyze_rule/analyze_rule_script.dart';
import 'analyze_rule/analyze_rule_string.dart';

export 'analyze_rule/analyze_rule_base.dart';
export 'analyze_rule/analyze_rule_support.dart';
export 'analyze_rule/analyze_rule_script.dart';
export 'analyze_rule/analyze_rule_element.dart';
export 'analyze_rule/analyze_rule_string.dart';
export 'analyze_rule/analyze_rule_regex_helper.dart';

/// AnalyzeRule - 規則總控 (重構後)
/// (原 Android model/analyzeRule/AnalyzeRule.kt)
class AnalyzeRule extends AnalyzeRuleBase
    with AnalyzeRuleRegexHelper, AnalyzeRuleElement, AnalyzeRuleString {
  AnalyzeRule({RuleDataInterface? ruleData, dynamic source}) {
    this.ruleData = ruleData;
    this.source = source;
  }

  AnalyzeRule setChapter(dynamic chapter) {
    this.chapter = chapter;
    return this;
  }

  AnalyzeRule setNextChapterUrl(String? nextChapterUrl) {
    this.nextChapterUrl = nextChapterUrl;
    return this;
  }

  AnalyzeRule setPage(int page) {
    this.page = page;
    return this;
  }

  AnalyzeRule setRedirectUrl(String? url) {
    if (url != null && url.isNotEmpty) {
      redirectUrl = url;
    }
    return this;
  }

  /// [baseUrl] 是送出請求的網址，[redirectUrl] 是網站轉址後實際回應的網址
  /// （同 Legado `setBaseUrl`、`setRedirectUrl`）。相對網址用 [redirectUrl]
  /// 補成完整的；網址規則（`isUrl`）沒有結果時用 [baseUrl]。沒有給
  /// [redirectUrl] 時兩個一樣。
  AnalyzeRule setContent(
    dynamic content, {
    String? baseUrl,
    String? redirectUrl,
  }) {
    if (content == null) {
      throw ArgumentError('Content cannot be null');
    }
    this.content = content;
    // 同 Legado `setContent(content, baseUrl = null)`：沒給 baseUrl（例如規則 JS
    // 的 `java.setContent(html)`）只換內容，原本的 baseUrl 與 redirectUrl 都留著，
    // 不清成空的，之後補相對網址才不會失靈。
    if (baseUrl != null) {
      this.baseUrl = baseUrl;
      this.redirectUrl = redirectUrl ?? baseUrl;
    } else if (redirectUrl != null) {
      this.redirectUrl = redirectUrl;
    }
    analyzeByXPath = null;
    analyzeByJSoup = null;
    analyzeByJSonPath = null;
    return this;
  }

  @override
  dynamic evalJS(String jsStr, dynamic result) {
    return AnalyzeRuleScript(this).evalJS(jsStr, result);
  }

  bool _inPreUpdateJs = false;
  bool _tocUrlRefreshRequested = false;

  /// 執行目錄的預整理 JS（`ruleToc.preUpdateJs`），傳回它有沒有呼叫
  /// `java.refreshTocUrl()`：有的話，抓目錄前要重新讀一次書籍詳情。
  bool preUpdateToc() {
    if (source is! BookSource) return false;
    final js = (source as BookSource).ruleToc?.preUpdateJs;
    if (js == null || js.isEmpty) return false;
    _inPreUpdateJs = true;
    try {
      evalJS(js, null);
    } finally {
      _inPreUpdateJs = false;
    }
    return _tocUrlRefreshRequested;
  }

  /// `java.refreshTocUrl()`：同 Legado，只能在預整理 JS 裡呼叫，要的是
  /// 抓目錄前重新讀書籍詳情、換上新的目錄網址。讀詳情要等網路、跑詳情規則，
  /// 規則 JS 不能停下來等，所以這裡只記下來，預整理 JS 跑完再讀。
  void requestTocUrlRefresh() {
    if (!_inPreUpdateJs) {
      throw StateError('java.refreshTocUrl() 只能在目錄的預整理 JS（preUpdateJs）裡呼叫');
    }
    _tocUrlRefreshRequested = true;
  }

  // 靜態輔助方法
  static String getUtilsJs() {
    return '';
  }
}

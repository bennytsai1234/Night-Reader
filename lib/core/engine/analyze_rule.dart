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

  AnalyzeRule setContent(dynamic content, {String? baseUrl}) {
    if (content == null) {
      throw ArgumentError('Content cannot be null');
    }
    this.content = content;
    this.baseUrl = baseUrl;
    // legado 會在解析鏈中同時維護 baseUrl 與 redirectUrl；若呼叫端尚未
    // 額外指定 redirectUrl，預設以目前內容所在 URL 作為 redirectUrl。
    redirectUrl = baseUrl;
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

import 'package:reader/core/models/rule_data_interface.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/services/book_source_service.dart';

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

  @override
  Future<dynamic> evalJSAsync(String jsStr, dynamic result) {
    return AnalyzeRuleScript(this).evalJSAsync(jsStr, result);
  }

  Future<void> preUpdateToc() async {
    if (source is! BookSource) return;
    final js = (source as BookSource).ruleToc?.preUpdateJs;
    if (js != null && js.isNotEmpty) {
      await evalJSAsync(js, null);
    }
  }

  /// 重新獲取書籍資訊 (原 Android AnalyzeRule.reGetBook)
  Future<void> reGetBook() async {
    if (source is! BookSource || ruleData is! Book) return;
    final book = ruleData as Book;
    final service = BookSourceService();
    // 模擬精確搜尋與更新
    final results = await service.searchBooks(source as BookSource, book.name);
    final match =
        results
            .where((e) => e.name == book.name && e.author == book.author)
            .firstOrNull;
    if (match != null) {
      book.bookUrl = match.bookUrl;
      await service.getBookInfo(source as BookSource, book);
    }
  }

  /// 刷新目錄位址 (原 Android AnalyzeRule.refreshTocUrl)
  Future<void> refreshTocUrl() async {
    if (source is! BookSource || ruleData is! Book) return;
    final service = BookSourceService();
    await service.getBookInfo(source as BookSource, ruleData as Book);
  }

  // 靜態輔助方法
  static String getUtilsJs() {
    return '';
  }
}

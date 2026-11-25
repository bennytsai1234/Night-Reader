import 'package:html_unescape/html_unescape.dart';

import '../parsers/analyze_by_css.dart';
import '../parsers/analyze_by_json_path.dart';
import '../parsers/analyze_by_xpath.dart';
import '../analyze_url.dart';
import '../js/js_engine.dart';
import '../js/js_extensions.dart';

import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/models/source/base_source.dart';
import 'package:night_reader/core/models/source/rule_data_interface.dart';
import 'package:night_reader/core/utils/lru_map.dart';

// 導入同目錄下的其它部分
import 'analyze_rule_support.dart';

/// AnalyzeRule 的基礎結構部分
/// (原 Android model/analyzeRule/AnalyzeRule.kt)
abstract class AnalyzeRuleBase {
  RuleDataInterface? ruleData;
  dynamic source; // BaseSource equivalent

  dynamic content;
  String? baseUrl;
  String? redirectUrl;
  dynamic chapter;
  String? nextChapterUrl;
  String? key;
  int page = 1;
  final Map<String, String> transientVariables = {};

  /// 規則 JS 在網址裡或登入檢查裡跑時，`java` 是這個請求（同 Legado 的
  /// AnalyzeUrl）：多了 `url`、`headerMap`、`initUrl()`、`getStrResponse()`。
  AnalyzeUrl? urlContext;

  AnalyzeByXPath? analyzeByXPath;
  AnalyzeByCss? analyzeByJSoup;
  AnalyzeByJsonPath? analyzeByJSonPath;
  JsEngine? jsEngine;

  /// 不為自己建 JS 引擎，借用這條規則的（建在它身上、由它釋放）。解析清單時
  /// 逐項的規則都借外層規則的引擎：新建一個引擎約 4 毫秒，在同一個引擎裡
  /// 執行一次只要約 0.1 毫秒，3000 章的目錄差了十幾秒。各項依序解析，執行
  /// 時 `java` 會換成當下那一項。
  AnalyzeRuleBase? jsEngineOwner;

  static final HtmlUnescape htmlUnescape = HtmlUnescape();
  static final LruMap<String, RegExp> regexCache = LruMap(maxSize: 200);
  static final LruMap<String, List<SourceRule>> stringRuleCache = LruMap(
    maxSize: 200,
  );

  void put(String key, String? value) {
    if (value == null) return;

    // 同 Legado：章節、書，都沒有時存進書源（`source.put`，和規則 JS 的
    // `source.put` 同一份），之後別的規則讀得到。
    if (chapter != null && chapter is RuleDataInterface) {
      (chapter as RuleDataInterface).putVariable(key, value);
    } else if (ruleData != null) {
      ruleData!.putVariable(key, value);
    } else if (source case final BaseSource source) {
      JsExtensions.putSourceRuleVariable(source, key, value);
    } else {
      transientVariables[key] = value;
    }
  }

  /// 同 Legado `AnalyzeRule.get`：`bookName` 是書名、`title` 是章名，其他
  /// 依序找章節、書、書源（空的也算沒有，往下一層找：正文的規則讀得到詳情頁
  /// 用 @put 存在書上的變數）。
  String get(String key) {
    switch (key) {
      case 'bookName':
        switch (ruleData) {
          case final Book book:
            return book.name;
          case final SearchBook book:
            return book.name;
        }
      case 'title':
        if (chapter != null) return chapter.title?.toString() ?? '';
    }

    String? val;
    if (chapter != null && chapter is RuleDataInterface) {
      val = (chapter as RuleDataInterface).getVariable(key);
    }
    if (val == null || val.isEmpty) val = ruleData?.getVariable(key);
    if (val == null || val.isEmpty) {
      if (source case final BaseSource source) {
        val = JsExtensions.sourceRuleVariable(source, key);
      }
    }
    if (val == null || val.isEmpty) {
      val = transientVariables[key];
    }
    return val ?? '';
  }

  /// 執行書源規則 JS。`java.ajax` 這類要等的呼叫在書源 isolate 停住等，
  /// 傳回的就是結果（ADR 0034）。
  dynamic evalJS(String jsStr, dynamic result);
}

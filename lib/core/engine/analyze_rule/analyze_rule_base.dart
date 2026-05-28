import 'dart:async';
import 'package:html_unescape/html_unescape.dart';
import '../parsers/analyze_by_css.dart';
import '../parsers/analyze_by_json_path.dart';
import '../parsers/analyze_by_xpath.dart';
import '../js/js_engine.dart';
import 'package:night_reader/core/models/rule_data_interface.dart';
import 'package:night_reader/core/services/rule_big_data_service.dart';
import 'package:night_reader/core/utils/lru_map.dart';

// 導入同目錄下的其它部分
import 'analyze_rule_support.dart';

/// AnalyzeRule 的基礎結構部分
/// (原 Android model/analyzeRule/AnalyzeRule.kt)
abstract class AnalyzeRuleBase {
  RuleDataInterface? ruleData;
  dynamic source; // BaseSource equivalent

  // 全域調試日誌流
  static StreamController<String>? debugLogController;

  void log(String msg) {
    final controller = debugLogController;
    if (controller != null && !controller.isClosed) {
      controller.add(msg);
    }
  }

  dynamic content;
  String? baseUrl;
  String? redirectUrl;
  dynamic chapter;
  String? nextChapterUrl;
  String? key;
  int page = 1;
  final Map<String, String> transientVariables = {};

  AnalyzeByXPath? analyzeByXPath;
  AnalyzeByCss? analyzeByJSoup;
  AnalyzeByJsonPath? analyzeByJSonPath;
  JsEngine? jsEngine;

  static final HtmlUnescape htmlUnescape = HtmlUnescape();
  static final LruMap<String, RegExp> regexCache = LruMap(maxSize: 200);
  static final LruMap<String, List<SourceRule>> stringRuleCache = LruMap(
    maxSize: 200,
  );
  static final LruMap<String, dynamic> scriptCache = LruMap(maxSize: 100);

  static void dispose() {
    debugLogController?.close();
    debugLogController = null;
  }

  void put(String key, String? value) {
    if (value == null) return;

    // 如果數據過大 (例如 > 5000 字元)，存入 BigData
    if (value.length > 5000) {
      final bigData = RuleBigDataService();
      // 根據當前上下文決定存儲類型
      try {
        final ch = chapter;
        if (ch != null && ch.bookUrl != null) {
          bigData.putChapterVariable(ch.bookUrl, ch.url, key, value);
        } else {
          final rd = ruleData;
          if (rd != null) {
            final dynamic dRd = rd;
            try {
              if (dRd.bookUrl != null) {
                bigData.putBookVariable(dRd.bookUrl, key, value);
              }
            } catch (_) {}
          }
        }
      } catch (_) {
        // Fallback or ignore if properties missing
      }
    }

    if (chapter != null && chapter is RuleDataInterface) {
      (chapter as RuleDataInterface).putVariable(key, value);
    } else if (ruleData != null) {
      ruleData!.putVariable(key, value);
    } else if (source != null && source is RuleDataInterface) {
      (source as RuleDataInterface).putVariable(key, value);
    } else {
      transientVariables[key] = value;
    }
  }

  String get(String key) {
    switch (key) {
      case 'key':
        return this.key ?? '';
      case 'page':
        return page.toString();
      case 'baseUrl':
        return baseUrl ?? '';
      case 'redirectUrl':
        return redirectUrl ?? '';
      case 'nextChapterUrl':
        return nextChapterUrl ?? '';
      case 'title':
        final chapterTitle = chapter?.title?.toString();
        if (chapterTitle != null && chapterTitle.isNotEmpty) {
          return chapterTitle;
        }
        break;
    }

    String? val;

    if (chapter != null && chapter is RuleDataInterface) {
      val = (chapter as RuleDataInterface).getVariable(key);
    }
    val ??= ruleData?.getVariable(key);
    if (val == null || val.isEmpty) {
      if (source != null && source is RuleDataInterface) {
        val = (source as RuleDataInterface).getVariable(key);
      }
    }
    if (val == null || val.isEmpty) {
      val = transientVariables[key];
    }

    // 如果內存中沒有且可能在大數據中，嘗試讀取
    if (val == null || val.isEmpty) {
      // 異步讀取可能需要重構 get 為 Future，這裡先做同步檢查的框架
    }

    return val ?? '';
  }

  dynamic evalJS(String jsStr, dynamic result);

  /// 以 Promise bridge 執行 rule JS；支援 `java.ajax` 等 async 呼叫。
  ///
  /// 呼叫端應使用本方法執行書源規則 JS；只有當 JS 純同步且呼叫鏈已是
  /// sync context（例如建構子內部）時才退而求其次使用 [evalJS]。
  Future<dynamic> evalJSAsync(String jsStr, dynamic result);
}

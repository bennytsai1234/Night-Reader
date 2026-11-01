import 'analyze_rule_base.dart';
import '../js/js_engine.dart';

import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/models/base_source.dart';

/// AnalyzeRule 的腳本執行 (原 Android AnalyzeRule.kt)。JS 結果取決於
/// source / book / chapter / page / baseUrl 與外部狀態，不快取執行結果。
extension AnalyzeRuleScript on AnalyzeRuleBase {
  dynamic evalJS(String jsStr, dynamic result) {
    final engine = _jsEngineForEval();
    final context = _buildJsContext(result, engine);
    final previous = engine.ruleContext;
    engine.ruleContext = this;
    try {
      return engine.evaluate(jsStr, context: context);
    } finally {
      // 網址 JS 改了 java.url、java.headerMap 就是改了這個請求（Legado 的
      // java 就是 AnalyzeUrl 本身），出錯時也一樣。
      urlContext?.applyJs(engine.urlState());
      engine.ruleContext = previous;
    }
  }

  /// 自己的引擎，或借用 [jsEngineOwner] 的（見該欄位說明）。
  JsEngine _jsEngineForEval() {
    final owner = jsEngineOwner;
    if (owner == null) {
      return jsEngine ??= JsEngine(source: source, ruleContext: this);
    }
    return owner.jsEngine ??= JsEngine(
      source: owner.source,
      ruleContext: owner,
    );
  }

  Map<String, dynamic> _buildJsContext(dynamic result, JsEngine engine) {
    // 引擎只服務一個書源；已經注入過就不再每次把整個書源（含全部規則）
    // 轉成 JSON 重寫一次。逐章共用引擎時，這是每次執行裡最貴的一段。
    final includeSource =
        !engine.sourceInjected || !identical(engine.source, source);
    final context = _baseJsContext(result);
    if (includeSource) context['source'] = _sourceForJs();
    return context;
  }

  dynamic _sourceForJs() {
    dynamic sourceMap;
    try {
      sourceMap = source?.toJson();
    } catch (_) {
      sourceMap = source;
    }
    if (source is BaseSource) {
      final baseSource = source as BaseSource;
      final mergedSource = <String, dynamic>{};
      if (sourceMap is Map) {
        sourceMap.forEach((key, value) {
          mergedSource[key.toString()] = value;
        });
      }
      mergedSource.putIfAbsent('key', () => baseSource.getKey());
      mergedSource.putIfAbsent('tag', () => baseSource.getTag());
      sourceMap = mergedSource;
    }
    return sourceMap;
  }

  Map<String, dynamic> _baseJsContext(dynamic result) {
    return {
      'java': this,
      'cookie': CookieStore(),
      'cache': CacheManager(),
      'result': result,
      'baseUrl': baseUrl,
      'redirectUrl': redirectUrl,
      'book': ruleData,
      'chapter': chapter,
      'title': chapter?.title,
      'nextChapterUrl': nextChapterUrl,
      'key': key,
      'page': page,
      'src': content,
      // 在網址或登入檢查裡跑時，java 多了請求的屬性與方法（見 urlContext）。
      '__lrUrl': urlContext?.toJs(),
      if (urlContext case final request?) ...{
        'speakText': request.speakText,
        'speakSpeed': request.speakSpeed,
      },
    };
  }

  void dispose() {
    jsEngine?.dispose();
  }
}

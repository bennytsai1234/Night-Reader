import 'dart:convert';
import 'dart:typed_data';

import 'analyze_rule_base.dart';
import '../js/js_engine.dart';

import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/services/http_client.dart';
import 'package:night_reader/core/models/base_source.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/utils/ttf_parser.dart';

/// AnalyzeRule 的腳本執行與異步擴展 (原 Android AnalyzeRule.kt & JsExtensions.kt)
extension AnalyzeRuleScript on AnalyzeRuleBase {
  dynamic evalJS(String jsStr, dynamic result) {
    final engine = _jsEngineForEval();
    final context = _buildJsContext(result, engine);
    final previous = engine.ruleContext;
    engine.ruleContext = this;
    try {
      return engine.evaluate(jsStr, context: context);
    } finally {
      engine.ruleContext = previous;
    }
  }

  /// Promise bridge 版本的 evalJS — 支援 rule JS 中的 `java.ajax` 等 async 呼叫。
  ///
  /// JS 結果取決於 source / book / chapter / page / baseUrl 與外部狀態，
  /// 因此同步與非同步路徑都不快取執行結果。
  Future<dynamic> evalJSAsync(String jsStr, dynamic result) async {
    final engine = _jsEngineForEval();
    final context = _buildJsContext(result, engine);
    final previous = engine.ruleContext;
    engine.ruleContext = this;
    try {
      return await engine.evaluateAsync(jsStr, context: context);
    } finally {
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
    };
  }

  /// 供 JS 調用的 TTF 解析 (原 Android JsExtensions.queryTTF)
  TtfParser? queryTTF(dynamic data) {
    if (data == null) return null;
    try {
      Uint8List? buffer;
      if (data is String) {
        if (data.startsWith('http')) {
          // 異步下載需處理，這裡暫作同步佔位
          return null;
        } else {
          // 嘗試 Base64 解碼
          buffer = base64Decode(data);
        }
      } else if (data is Uint8List) {
        buffer = data;
      }

      if (buffer != null) {
        return TtfParser(buffer);
      }
    } catch (e) {
      log('  ❌ queryTTF 失敗: $e');
    }
    return null;
  }

  /// 供 JS 調用的 Base64 TTF 解析
  TtfParser? queryBase64TTF(String? data) => queryTTF(data);

  /// 供 JS 調用的異步請求
  Future<String?> ajax(dynamic url) async {
    final urlStr = url is List ? url.first.toString() : url.toString();
    log('  ◇ JS 調用 ajax: $urlStr');
    try {
      final response = await HttpClient().client.get(urlStr);
      return response.data?.toString();
    } catch (e) {
      log('  ❌ ajax 失敗: $e');
      return null;
    }
  }

  /// 執行目錄預整理 JS
  Future<void> preUpdateToc() async {
    final js = source is BookSource
        ? (source as BookSource).ruleToc?.preUpdateJs
        : null;
    if (js != null && js.isNotEmpty) {
      log('⇒ 執行 preUpdateJs');
      evalJS(js, null);
    }
  }

  void dispose() {
    jsEngine?.dispose();
  }
}

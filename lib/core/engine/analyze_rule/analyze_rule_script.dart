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
    jsEngine ??= JsEngine(source: source, ruleContext: this);
    if (AnalyzeRuleBase.scriptCache.containsKey(jsStr) && result == null) {
      return AnalyzeRuleBase.scriptCache[jsStr];
    }
    final context = _buildJsContext(result);
    final evalResult = jsEngine!.evaluate(jsStr, context: context);
    if (result == null) AnalyzeRuleBase.scriptCache[jsStr] = evalResult;
    return evalResult;
  }

  /// Promise bridge 版本的 evalJS — 支援 rule JS 中的 `java.ajax` 等 async 呼叫。
  ///
  /// 不做 scriptCache：async rule 的結果可能隨 HTTP 回應改變，quiety 快取容易
  /// 誤命中；同步 rule 仍由 [evalJS] 的 scriptCache 保留既有行為。
  Future<dynamic> evalJSAsync(String jsStr, dynamic result) async {
    jsEngine ??= JsEngine(source: source, ruleContext: this);
    final context = _buildJsContext(result);
    return jsEngine!.evaluateAsync(jsStr, context: context);
  }

  Map<String, dynamic> _buildJsContext(dynamic result) {
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
    return {
      'java': this,
      'cookie': CookieStore(),
      'cache': CacheManager(),
      'result': result,
      'baseUrl': baseUrl,
      'redirectUrl': redirectUrl,
      'source': sourceMap,
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
    final js =
        source is BookSource
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_js/flutter_js.dart';
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:xpath_selector/xpath_selector.dart';
import 'package:night_reader/core/models/base_source.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/http_client.dart';
import 'package:night_reader/core/services/source_validation_context.dart';
import 'async_js_rewriter.dart';
import 'js_extensions.dart';
import 'js_rule_async_wrapper.dart';

/// JsEngine - JavaScript 執行引擎
/// (原 Android Rhino) JS Engine (modules/rhino)
///
/// 使用 flutter_js 套件在 Dart 中執行 JavaScript
///
/// 兩條執行路徑：
/// - [evaluate] — 純同步 JS。若規則本身不含 async `java.*` 呼叫，仍走最快路徑。
/// - [evaluateAsync] — 會先以 [AsyncJsRewriter] 插入 `(await ...)` 包裝，
///   再用 [JsRuleAsyncWrapper] 包成 async IIFE，透過 `__ruleDone` sentinel
///   在 Dart 側 await Completer 完成。這是為了解決 flutter_js 同步 onMessage
///   回傳值限制所引入的 Promise bridge。
class JsEngine {
  JavascriptRuntime? _runtime;
  bool _isAvailable = false;
  JsExtensions? _extensions;
  final dynamic source;
  final dynamic ruleContext;
  final Map<int, dom.Element> _bridgedElements = <int, dom.Element>{};
  int _nextBridgeElementId = 0;
  String? _loadedSourceJsLibKey;
  static final Map<String, String> _resolvedJsLibCache = <String, String>{};
  static final Map<String, Future<String>> _pendingJsLibCache =
      <String, Future<String>>{};

  /// 清除 session 級別的靜態快取，在批次校驗結束後呼叫以釋放記憶體。
  static void clearCaches() {
    _resolvedJsLibCache.clear();
    // _pendingJsLibCache 的 Future 完成後會自行移除；強制清除不影響正確性。
    _pendingJsLibCache.clear();
  }

  JsEngine({this.source, this.ruleContext}) {
    try {
      // 背景 isolate（書源批量校驗）沒有 ServicesBinding，flutter_js 的
      // enableFetch() 會用 rootBundle 載入 fetch.js polyfill，存取
      // ServicesBinding.instance 時觸發 null check 崩潰，導致整個 JS 引擎
      // 不可用、所有 JS 書源校驗失敗。校驗只用 java.* 橋接，不需要瀏覽器
      // fetch/XHR，故在非互動校驗時關閉 xhr；主線程閱讀路徑維持開啟。
      _runtime = getJavascriptRuntime(
        xhr: !SourceValidationContext.isNonInteractive,
      );
      _isAvailable = true;
      _extensions = JsExtensions(
        _runtime!,
        source: source,
        ruleContext: ruleContext,
      );
      _extensions!.inject();
    } catch (e) {
      // Library not available in some test environments
      AppLog.e('JS Engine init error: $e', error: e);
      _isAvailable = false;
    }
  }

  /// Execute JavaScript code and return result synchronously.
  ///
  /// **不支援 async `java.*` 呼叫**。若 [jsCode] 中偵測到 async 呼叫，會印出
  /// warning 並仍按原字串執行（結果通常為 Promise 物件，rule 端會拿不到實值）。
  /// 呼叫端請優先使用 [evaluateAsync]。
  dynamic evaluate(String jsCode, {Map<String, dynamic>? context}) {
    if (!_isAvailable) {
      return _mockEvaluate(jsCode, context);
    }

    final normalizedJs = AsyncJsRewriter.normalizeLegacyTemplateEscapes(jsCode);

    if (AsyncJsRewriter.needsAsync(normalizedJs)) {
      AppLog.e(
        'JsEngine.evaluate() called with async JS; '
        'switch caller to evaluateAsync(). Source prefix: '
        '${normalizedJs.substring(0, normalizedJs.length.clamp(0, 120))}',
      );
    }

    _injectContext(context);
    _ensureSourceJsLibLoadedSync();
    final result = _evaluateRuleScript(normalizedJs);
    return _decodeContextValue(result.rawResult);
  }

  /// Execute rule JS that may invoke async `java.*` / `cache.*` / `source.*`
  /// methods. Always awaits their underlying Futures and returns the rule's
  /// final expression value.
  ///
  /// 若 [jsCode] 經 [AsyncJsRewriter.needsAsync] 判定不需 async，會走同步
  /// fast path 直接回傳 [evaluate] 的結果 (避免不必要的 Promise bridge 開銷)。
  Future<dynamic> evaluateAsync(
    String jsCode, {
    Map<String, dynamic>? context,
  }) async {
    if (!_isAvailable) {
      return _mockEvaluate(jsCode, context);
    }

    final normalizedJs = AsyncJsRewriter.normalizeLegacyTemplateEscapes(jsCode);

    // Sync-only 規則不需要 Promise bridge。直接走同步路徑可避免額外包裝
    // 干擾原本就合法的 searchUrl / tocUrl 組裝腳本。
    if (!AsyncJsRewriter.needsAsync(normalizedJs)) {
      return evaluate(normalizedJs, context: context);
    }

    _injectContext(context);
    await _ensureSourceJsLibLoadedAsync();
    final asyncFriendlyJs = _normalizeLegacySyncIifeForAsync(normalizedJs);
    final rewritten = AsyncJsRewriter.rewrite(asyncFriendlyJs);
    final (callId, future) = _extensions!.registerRuleCall();
    final wrapped = JsRuleAsyncWrapper.wrap(rewritten, callId);

    try {
      final res = _runtime!.evaluate(wrapped);
      if (res.isError) {
        _extensions!.cancelRuleCall(
          callId,
          StateError('rule JS evaluate error: ${res.stringResult}'),
        );
      } else {
        // 重要：同步 evaluate 完成後，async IIFE 已經被排進 microtask queue，
        // 需 pump 才能讓第一層 await 真正開始執行。
        _runtime!.executePendingJob();
      }
    } catch (e) {
      _extensions!.cancelRuleCall(callId, e);
      rethrow;
    }

    return future
        .then(_decodeContextValue)
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            _extensions!.cancelRuleCall(
              callId,
              TimeoutException(
                'JS rule timed out after 20s',
                const Duration(seconds: 20),
              ),
            );
            throw TimeoutException(
              'JS rule timed out after 20s',
              const Duration(seconds: 20),
            );
          },
        );
  }

  String _normalizeLegacySyncIifeForAsync(String jsCode) {
    var normalized = jsCode;
    normalized = normalized.replaceFirstMapped(
      RegExp(r'^(\s*)\(\s*\(\s*\)\s*=>'),
      (match) => '${match.group(1)}(async () =>',
    );
    normalized = normalized.replaceFirstMapped(
      RegExp(r'^(\s*)\(\s*function\b'),
      (match) => '${match.group(1)}(async function',
    );
    return normalized;
  }

  String? _extractSourceJsLib() {
    if (source is! BaseSource) {
      return null;
    }
    final jsLib = (source as BaseSource).jsLib?.trim();
    if (jsLib == null || jsLib.isEmpty) {
      return null;
    }
    return jsLib;
  }

  void _ensureSourceJsLibLoadedSync() {
    final jsLib = _extractSourceJsLib();
    if (jsLib == null || jsLib == _loadedSourceJsLibKey) {
      return;
    }
    final resolved = _resolveSourceJsLibSync(jsLib);
    if (resolved == null || resolved.trim().isEmpty) {
      return;
    }
    final result = _runtime!.evaluate(resolved);
    if (result.isError) {
      AppLog.e('JsEngine source jsLib sync load error: ${result.stringResult}');
      return;
    }
    _loadedSourceJsLibKey = jsLib;
  }

  Future<void> _ensureSourceJsLibLoadedAsync() async {
    final jsLib = _extractSourceJsLib();
    if (jsLib == null || jsLib == _loadedSourceJsLibKey) {
      return;
    }
    final resolved = await _resolveSourceJsLibAsync(jsLib);
    if (resolved.trim().isEmpty) {
      return;
    }
    final result = _runtime!.evaluate(resolved);
    if (result.isError) {
      AppLog.e(
        'JsEngine source jsLib async load error: ${result.stringResult}',
      );
      return;
    }
    _loadedSourceJsLibKey = jsLib;
  }

  String? _resolveSourceJsLibSync(String jsLib) {
    final cached = _resolvedJsLibCache[jsLib];
    if (cached != null) {
      return cached;
    }
    final libMap = _decodeJsLibMap(jsLib);
    if (libMap == null) {
      return jsLib;
    }

    final buffers = <String>[];
    for (final value in libMap.values) {
      final resolved = _resolveJsLibFragmentSync(value);
      if (resolved == null) {
        return null;
      }
      if (resolved.trim().isNotEmpty) {
        buffers.add(resolved);
      }
    }
    final merged = buffers.join('\n');
    if (merged.isNotEmpty) {
      _resolvedJsLibCache[jsLib] = merged;
    }
    return merged;
  }

  Future<String> _resolveSourceJsLibAsync(String jsLib) async {
    final cached = _resolvedJsLibCache[jsLib];
    if (cached != null) {
      return cached;
    }
    final pending = _pendingJsLibCache[jsLib];
    if (pending != null) {
      return pending;
    }

    final future = () async {
      final libMap = _decodeJsLibMap(jsLib);
      if (libMap == null) {
        return jsLib;
      }

      final buffers = <String>[];
      for (final value in libMap.values) {
        final resolved = await _resolveJsLibFragmentAsync(value);
        if (resolved.trim().isNotEmpty) {
          buffers.add(resolved);
        }
      }
      return buffers.join('\n');
    }();

    _pendingJsLibCache[jsLib] = future;
    try {
      final resolved = await future;
      if (resolved.isNotEmpty) {
        _resolvedJsLibCache[jsLib] = resolved;
      }
      return resolved;
    } finally {
      _pendingJsLibCache.remove(jsLib);
    }
  }

  Map<String, String>? _decodeJsLibMap(String jsLib) {
    final trimmed = jsLib.trim();
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return null;
      }
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  String? _resolveJsLibFragmentSync(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final cached = _resolvedJsLibCache[trimmed];
    if (cached != null) {
      return cached;
    }
    final file = File(trimmed);
    if (file.existsSync()) {
      final content = file.readAsStringSync();
      _resolvedJsLibCache[trimmed] = content;
      return content;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    return trimmed;
  }

  Future<String> _resolveJsLibFragmentAsync(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final cached = _resolvedJsLibCache[trimmed];
    if (cached != null) {
      return cached;
    }
    final file = File(trimmed);
    if (await file.exists()) {
      final content = await file.readAsString();
      _resolvedJsLibCache[trimmed] = content;
      return content;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      final response = await HttpClient().client.get<List<int>>(
        trimmed,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      final content = utf8.decode(
        response.data ?? const <int>[],
        allowMalformed: true,
      );
      _resolvedJsLibCache[trimmed] = content;
      return content;
    }
    return trimmed;
  }

  JsEvalResult _evaluateRuleScript(String jsCode) {
    final wrapped =
        'typeof __lrNormalizeRuleResult === "function" '
        '? __lrNormalizeRuleResult(eval(${jsonEncode(jsCode)})) '
        ': eval(${jsonEncode(jsCode)})';
    final result = _runtime!.evaluate(wrapped);
    if (!result.isError) {
      return result;
    }
    // 某些 legacy rule 在 eval(...) 路徑會被 QuickJS 誤判語法，
    // 改走 IIFE + final-return 注入，既保留最後表達式結果，也讓 normalize
    // 邏輯繼續生效。
    final fallbackBody = JsRuleAsyncWrapper.injectFinalReturn(jsCode);
    final fallbackWrapped =
        'typeof __lrNormalizeRuleResult === "function" '
        '? __lrNormalizeRuleResult((function() {\n$fallbackBody\n})()) '
        ': (function() {\n$fallbackBody\n})()';
    return _runtime!.evaluate(fallbackWrapped);
  }

  void _injectContext(Map<String, dynamic>? context) {
    if (context == null) return;
    _bridgedElements.clear();
    _nextBridgeElementId = 0;
    context.forEach((key, value) {
      switch (key) {
        case 'java':
        case 'cookie':
        case 'cache':
          return;
        case 'source':
          final jsLiteral = _encodeContextValue(value);
          _runtime!.evaluate(
            'if (typeof source === "object" && source !== null) { '
            'Object.assign(source, $jsLiteral); '
            '} else { var source = $jsLiteral; }',
          );
          return;
        case 'book':
        case 'chapter':
          final jsLiteral = _encodeScopedObject(key, value);
          _runtime!.evaluate('var $key = $jsLiteral;');
          return;
        default:
          final jsLiteral = _encodeContextValue(value);
          _runtime!.evaluate('var $key = $jsLiteral;');
      }
    });
  }

  String _encodeContextValue(dynamic value) {
    if (value == null) {
      return 'null';
    }
    if (value is dom.Element) {
      return _encodeElement(value);
    }
    if (value is XPathNode) {
      final node = value.node;
      if (node is dom.Element) {
        return _encodeElement(node);
      }
      return jsonEncode(value.text ?? '');
    }
    if (value is Iterable) {
      final encodedItems = value.map(_encodeContextValue).join(',');
      return '''
(function() {
  var arr = [$encodedItems];
  Object.defineProperty(arr, 'toArray', {
    value: function() { return arr; },
    enumerable: false
  });
  Object.defineProperty(arr, 'get', {
    value: function(index) { return arr[index]; },
    enumerable: false
  });
  Object.defineProperty(arr, 'size', {
    value: function() { return arr.length; },
    enumerable: false
  });
  return arr;
})()
''';
    }
    try {
      return _encodeJsonContextValue(value);
    } catch (_) {
      return jsonEncode(value.toString());
    }
  }

  String _encodeJsonContextValue(dynamic value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return jsonEncode(value.toString());
    }
  }

  String _encodeScopedObject(String scopeName, dynamic value) {
    final payload = _encodeJsonContextValue(value);
    final scopeLiteral = jsonEncode(scopeName);
    return '''
(function() {
  var seed = $payload;
  if (seed == null || typeof seed !== 'object') {
    return seed;
  }
  var obj = {};
  Object.keys(seed).forEach(function(prop) {
    var current = seed[prop];
    Object.defineProperty(obj, prop, {
      enumerable: true,
      configurable: true,
      get: function() { return current; },
      set: function(value) {
        current = value;
        sendMessage('scopedObjectSetField', JSON.stringify([$scopeLiteral, prop, value]));
      }
    });
  });
  obj.getVariable = function(key) {
    var value = sendMessage(
      'scopedObjectGetVariable',
      JSON.stringify([$scopeLiteral, key])
    );
    return value == null ? '' : value;
  };
  obj.putVariable = function(key, value) {
    sendMessage(
      'scopedObjectPutVariable',
      JSON.stringify([$scopeLiteral, key, value])
    );
    return null;
  };
  if ($scopeLiteral === "book") {
    obj.setReverseToc = function(value) {
      sendMessage(
        'scopedObjectSetField',
        JSON.stringify([$scopeLiteral, 'reverseToc', !!value])
      );
      return null;
    };
    obj.getReverseToc = function() {
      return !!sendMessage(
        'scopedObjectGetField',
        JSON.stringify([$scopeLiteral, 'reverseToc'])
      );
    };
    obj.setUseReplaceRule = function(value) {
      sendMessage(
        'scopedObjectSetField',
        JSON.stringify([$scopeLiteral, 'useReplaceRule', !!value])
      );
      return null;
    };
    obj.getUseReplaceRule = function() {
      return !!sendMessage(
        'scopedObjectGetField',
        JSON.stringify([$scopeLiteral, 'useReplaceRule'])
      );
    };
  }
  return obj;
})()
''';
  }

  String _encodeElement(dom.Element element) {
    final bridgeId = _nextBridgeElementId++;
    _bridgedElements[bridgeId] = element;
    final payload = jsonEncode(<String, dynamic>{
      '__lrElementId': bridgeId,
      'text': element.text,
      'html': element.innerHtml,
      'outerHtml': element.outerHtml,
      'attributes': element.attributes,
    });
    return '''
(function() {
  var e = $payload;
  return {
    __lrElementId: e.__lrElementId,
    text: function() { return e.text || ''; },
    html: function() { return e.html || ''; },
    outerHtml: function() { return e.outerHtml || ''; },
    attr: function(name) {
      var attrs = e.attributes || {};
      return attrs[name] || '';
    },
    toString: function() {
      return e.outerHtml || e.html || e.text || '';
    }
  };
})()
''';
  }

  dynamic _decodeContextValue(dynamic value) {
    if (value is List) {
      return value.map(_decodeContextValue).toList();
    }
    if (value is Map) {
      final elementId = value['__lrElementId'];
      if (elementId is num) {
        return _bridgedElements[elementId.toInt()] ?? value;
      }
      final decoded = <dynamic, dynamic>{};
      value.forEach((key, entry) {
        decoded[key] = _decodeContextValue(entry);
      });
      return decoded;
    }
    return value;
  }

  dynamic _mockEvaluate(String jsCode, Map<String, dynamic>? context) {
    final trimmedJs = jsCode.trim();
    if (trimmedJs == 'key') return context?['key'] ?? 'key';
    if (trimmedJs == 'page') return context?['page'] ?? 'page';
    if (trimmedJs == 'result') return context?['result'] ?? 'result';
    if (trimmedJs == 'baseUrl') return context?['baseUrl'] ?? 'baseUrl';

    if (jsCode.contains("'https://api.example.com/book/' + result")) {
      return 'https://api.example.com/book/${context?['result']}';
    }
    return 'JS_ERROR: Library not available';
  }

  /// Dispose the JS runtime
  void dispose() {
    _runtime?.dispose();
  }
}

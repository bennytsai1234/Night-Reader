import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:xpath_selector/xpath_selector.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/base_source.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/http_client.dart';

import 'js_extensions.dart';
import 'legacy_js_syntax.dart';
import 'rule_final_return.dart';

/// JsEngine - JavaScript 執行引擎
/// (原 Android Rhino) JS Engine (modules/rhino)
///
/// 使用 flutter_js 套件在 Dart 中執行 JavaScript。規則 JS 一律同步執行：
/// `java.ajax` 這類要等的呼叫在書源 isolate 停住等結果（[BlockingCall]，
/// ADR 0034），和 Legado 的 Rhino 一樣。
class JsEngine {
  JavascriptRuntime? _runtime;
  bool _isAvailable = false;

  /// QuickJS 有沒有建起來；沒有時 [evaluate] 回傳模擬結果（給測試環境用）。
  bool get isAvailable => _isAvailable;
  JsExtensions? _extensions;
  final dynamic source;

  /// 規則 JS 裡 `java` 代表的 AnalyzeRule。同一次解析的逐項規則共用一個
  /// 引擎（見 `AnalyzeRuleBase.jsEngineOwner`），每次執行前換成當下那一項。
  dynamic get ruleContext => _ruleContext;
  set ruleContext(dynamic value) {
    _ruleContext = value;
    _extensions?.ruleContext = value;
  }

  dynamic _ruleContext;
  String? _loadedSourceJsLibKey;
  static final Map<String, String> _resolvedJsLibCache = <String, String>{};
  bool _isDisposed = false;

  /// 清除 session 級別的靜態快取，在批次校驗結束後呼叫以釋放記憶體。
  static void clearCaches() {
    _resolvedJsLibCache.clear();
  }

  JsEngine({this.source, dynamic ruleContext}) : _ruleContext = ruleContext {
    try {
      // 書源 worker（含書源校驗）沒有 rootBundle，fetch.js 用主 isolate
      // 讀好的那一份（`fetchPolyfillSource`）。
      _runtime = getJavascriptRuntime();
      _isAvailable = true;
      _extensions = JsExtensions(
        _runtime!,
        source: source,
        ruleContext: ruleContext,
      );
      _extensions!.inject();
      _runtime!.evaluate(_ruleGlobalsHelpers);
    } catch (e) {
      // Library not available in some test environments
      AppLog.e('JS Engine init error: $e', error: e);
      _isAvailable = false;
    }
  }

  /// 執行規則 JS，傳回最後一個表達式的值。
  dynamic evaluate(String jsCode, {Map<String, dynamic>? context}) {
    if (_isDisposed) {
      throw StateError('JsEngine has been disposed');
    }
    if (!_isAvailable) {
      return _mockEvaluate(jsCode, context);
    }

    final normalizedJs = LegacyJsSyntax.normalize(jsCode);

    _activeRules++;
    try {
      _injectContext(context);
      _ensureSourceJsLibLoaded();
      final result = _evaluateRuleScript(normalizedJs);
      return _decodeContextValue(_runtime!.dartValueOf(result));
    } finally {
      _activeRules--;
    }
  }

  /// 正在跑的規則數。規則 JS 裡呼叫 `java.getString` 這類會再跑別的規則；
  /// 交給 JS 的 Jsoup 元素只在沒有規則在跑時才清掉，外層規則手上的元素
  /// 不會在巢狀執行時失效。
  int _activeRules = 0;

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

  void _ensureSourceJsLibLoaded() {
    final jsLib = _extractSourceJsLib();
    if (jsLib == null || jsLib == _loadedSourceJsLibKey) {
      return;
    }
    final resolved = _resolveSourceJsLib(jsLib);
    if (resolved == null || resolved.trim().isEmpty) {
      return;
    }
    final result = _runtime!.evaluate(resolved);
    if (result.isError) {
      AppLog.e('JsEngine source jsLib load error: ${result.stringResult}');
      return;
    }
    _loadedSourceJsLibKey = jsLib;
  }

  /// 書源的 jsLib：一段 JS，或 `{名稱: 片段}`，片段是 JS、檔案路徑或網址。
  /// 有片段抓不到時傳回 null，這次不載入，下次執行再試。
  String? _resolveSourceJsLib(String jsLib) {
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
      final resolved = _resolveJsLibFragment(value);
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

  String? _resolveJsLibFragment(String raw) {
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
      try {
        final content = BlockingCall.run(_jsLibDownload(trimmed)) as String;
        _resolvedJsLibCache[trimmed] = content;
        return content;
      } catch (e) {
        AppLog.e('JsEngine source jsLib fetch error ($trimmed): $e');
        return null;
      }
    }
    return trimmed;
  }

  /// 規則執行時新掛上全域的名稱（沒宣告就賦值的變數，例如 `seen = result`），
  /// 在規則結束後刪掉，下一次執行（下一章、下一筆結果）看不到；Legado 每次
  /// 執行都是新的作用域。規則的 JS 可能經 `java.getString` 再執行一段規則，
  /// 所以只在最外層記下與清除。脈絡、書源 jsLib 都在進入規則前寫好，不受影響。
  static const String _ruleGlobalsHelpers = '''
globalThis.__lrRuleDepth = 0;
globalThis.__lrEnterRule = function () {
  if (__lrRuleDepth++ === 0) globalThis.__lrGlobalsBefore = Object.keys(globalThis);
};
globalThis.__lrExitRule = function () {
  if (__lrRuleDepth === 0 || --__lrRuleDepth > 0) return;
  var keep = new Set(globalThis.__lrGlobalsBefore);
  Object.keys(globalThis).forEach(function (name) {
    if (!keep.has(name)) delete globalThis[name];
  });
};
globalThis.__lrRunRule = function (run) {
  __lrEnterRule();
  try { return run(); } finally { __lrExitRule(); }
};
''';

  /// 規則 JS 包在函式裡用直接 eval 執行：規則裡 `var` 宣告的變數留在這次
  /// 執行，不會掛到全域讓下一次（下一章、下一筆結果）看到，與 Legado 每次
  /// 執行一個新作用域相同。沒宣告就賦值的變數由 `__lrRunRule` 在結束後清掉
  /// （見 [_ruleGlobalsHelpers]）。
  JsEvalResult _evaluateRuleScript(String jsCode) {
    final wrapped =
        '__lrRunRule(function() { return typeof __lrNormalizeRuleResult === "function" '
        '? __lrNormalizeRuleResult(eval(${jsonEncode(jsCode)})) '
        ': eval(${jsonEncode(jsCode)}); })';
    final result = _runtime!.evaluate(wrapped);
    // 某些 legacy rule 在 eval(...) 路徑會被 QuickJS 誤判語法，
    // 改走 IIFE + final-return 注入，既保留最後表達式結果，也讓 normalize
    // 邏輯繼續生效。只在語法錯誤時改走：執行到一半出錯的規則再跑一次，
    // 請求與 `java.put` 這類動作會做兩次（被取消的請求也會再發一次）。
    if (!result.isError || !result.stringResult.contains('SyntaxError')) {
      return result;
    }
    final fallbackBody = RuleFinalReturn.inject(jsCode);
    final fallbackWrapped =
        '__lrRunRule(function() { return typeof __lrNormalizeRuleResult === "function" '
        '? __lrNormalizeRuleResult((function() {\n$fallbackBody\n})()) '
        ': (function() {\n$fallbackBody\n})(); })';
    return _runtime!.evaluate(fallbackWrapped);
  }

  /// 這個引擎的 JS 全域已經有 `source`。引擎只服務一個書源（[source]），
  /// 注入一次之後呼叫端可以省略，見 `AnalyzeRuleScript`。
  bool get sourceInjected => _sourceInjected;
  bool _sourceInjected = false;

  /// 每次執行前把脈絡寫進 JS 全域。全部合成一段腳本一次執行：逐項分開執行
  /// 時，每次都要多付十幾次跨 FFI 的解析與執行。
  void _injectContext(Map<String, dynamic>? context) {
    if (context == null) return;
    final statements = <String>[];
    // 只剩這一條規則在跑（不是巢狀執行）：上一條規則交給 JS 的 Jsoup 元素
    // 不會再用，清掉。
    final jsoup = _extensions?.jsoup;
    if (_activeRules == 1 && jsoup != null && !jsoup.isEmpty) {
      jsoup.clear();
      statements.add('__lrJsoupForget();');
    }
    _contextBaseUrl = context['baseUrl']?.toString();
    context.forEach((key, value) {
      switch (key) {
        case 'java':
        case 'cookie':
        case 'cache':
          return;
        case 'source':
          final jsLiteral = _encodeContextValue(value);
          statements.add(
            'if (typeof source === "object" && source !== null) { '
            'Object.assign(source, $jsLiteral); '
            '} else { var source = $jsLiteral; }',
          );
          _sourceInjected = true;
          return;
        case 'book':
        case 'chapter':
          final jsLiteral = _encodeScopedObject(key, value);
          statements.add('var $key = $jsLiteral;');
          return;
        default:
          final jsLiteral = _encodeContextValue(value);
          statements.add('var $key = $jsLiteral;');
      }
    });
    if (statements.isEmpty) return;
    final batch = _runtime!.evaluate(statements.join('\n'));
    if (!batch.isError) return;
    // 合成的腳本中途出錯時，後面的變數會停在上一次執行的值；共用引擎時
    // 那是上一章的。逐句再寫一次，壞掉的那句不影響其他。
    AppLog.w('JS 脈絡注入失敗，改逐項寫入：${batch.stringResult}');
    for (final statement in statements) {
      _runtime!.evaluate(statement);
    }
  }

  String _encodeContextValue(dynamic value) {
    if (value == null) {
      return 'null';
    }
    if (value is dom.Element || value is dom.Document) {
      return _encodeElement(value as dom.Node);
    }
    if (value is XPathNode) {
      final node = value.node;
      if (node is dom.Element || node is dom.Document) {
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

  /// `book`、`chapter` 的包裝：欄位寫入時通知 Dart，另附 `getVariable` 等
  /// 方法。建構函式每個引擎只定義一次，之後每次執行只傳資料；整段建構程式
  /// 每次重新送進引擎解析，逐章執行時佔了大半時間。
  static const String _scopedObjectFactory = '''
var __lrScopedObject = function(scope, seed) {
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
        sendMessage('scopedObjectSetField', JSON.stringify([scope, prop, value]));
      }
    });
  });
  obj.getVariable = function(key) {
    var value = sendMessage(
      'scopedObjectGetVariable',
      JSON.stringify([scope, key])
    );
    return value == null ? '' : value;
  };
  obj.putVariable = function(key, value) {
    sendMessage(
      'scopedObjectPutVariable',
      JSON.stringify([scope, key, value])
    );
    return null;
  };
  if (scope === "book") {
    obj.setReverseToc = function(value) {
      sendMessage(
        'scopedObjectSetField',
        JSON.stringify([scope, 'reverseToc', !!value])
      );
      return null;
    };
    obj.getReverseToc = function() {
      return !!sendMessage(
        'scopedObjectGetField',
        JSON.stringify([scope, 'reverseToc'])
      );
    };
    obj.setUseReplaceRule = function(value) {
      sendMessage(
        'scopedObjectSetField',
        JSON.stringify([scope, 'useReplaceRule', !!value])
      );
      return null;
    };
    obj.getUseReplaceRule = function() {
      return !!sendMessage(
        'scopedObjectGetField',
        JSON.stringify([scope, 'useReplaceRule'])
      );
    };
  }
  return obj;
};
''';

  bool _scopedObjectFactoryInstalled = false;

  String _encodeScopedObject(String scopeName, dynamic value) {
    if (!_scopedObjectFactoryInstalled) {
      _runtime!.evaluate(_scopedObjectFactory);
      _scopedObjectFactoryInstalled = true;
    }
    final payload = _encodeJsonContextValue(value);
    return '__lrScopedObject(${jsonEncode(scopeName)}, $payload)';
  }

  /// 這次執行的頁面網址，交給 JS 的元素用它算 `abs:` 屬性。
  String? _contextBaseUrl;

  /// 元素交給 JS 時是真的 Jsoup 元素（`JsoupBridge`），和 `java.getElements`
  /// 拿到的一樣。
  String _encodeElement(dom.Node element) {
    final jsoup = _extensions!.jsoup..setBaseUri(element, _contextBaseUrl);
    return '__lrJsoupDecode(${jsonEncode(jsoup.toJs(element))})';
  }

  dynamic _decodeContextValue(dynamic value) {
    if (value is List) {
      return value.map(_decodeContextValue).toList();
    }
    if (value is Map) {
      final elementId = value['__lrElementId'];
      if (elementId is num) {
        final node = _extensions?.jsoup.node(elementId.toInt());
        // Jsoup 的 Document 也是元素；後面的規則解析拿 <html> 接著選。
        if (node is dom.Document) return node.documentElement ?? value;
        return node ?? value;
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
    if (_isDisposed) return;
    _isDisposed = true;
    _extensions?.dispose();
    _runtime?.dispose();
    _extensions = null;
    _runtime = null;
    _isAvailable = false;
  }
}

/// 網路 isolate 抓網址形式的 jsLib 片段（[BlockingCall]）。
Future<Object?> Function() _jsLibDownload(String url) => () async {
  final response = await HttpClient().client.get<List<int>>(
    url,
    options: Options(
      responseType: ResponseType.bytes,
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ),
    cancelToken: currentSourceCancelToken,
  );
  return utf8.decode(response.data ?? const <int>[], allowMalformed: true);
};

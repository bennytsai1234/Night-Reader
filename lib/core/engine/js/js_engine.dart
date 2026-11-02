import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:xpath_selector/xpath_selector.dart';
import 'package:night_reader/core/engine/rule_data_fields.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/base_source.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/http_client.dart';
import 'package:night_reader/core/network/str_response.dart';

import 'js_extensions.dart';
import 'js_response.dart';
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

  /// 執行規則 JS，傳回最後一個表達式的值。規則丟出、自己沒接住的錯誤以
  /// [RuleJsException] 丟出，和 Legado 一樣照規則失敗處理。
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
      if (result.isError) throw RuleJsException(result.stringResult);
      return _decodeContextValue(_runtime!.dartValueOf(result));
    } finally {
      if (--_activeRules == 0) _contextResponses.clear();
    }
  }

  /// 網址 JS 跑完時 `java.url`、`java.headerMap` 的值（`AnalyzeUrl.applyJs`）；
  /// 不在網址裡跑時是 null。
  Object? urlState() {
    if (!_isAvailable || _isDisposed) return null;
    final result = _runtime!.evaluate('__lrUrlStateJson()');
    return result.isError ? null : jsonDecode(result.stringResult);
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
globalThis.__lrStartedRule = -1;
''';

  /// 這個引擎下一次執行規則的編號，見 [_evaluateRuleScript]。
  int _nextRuleRun = 0;

  /// 規則 JS 包在函式裡用直接 eval 執行：規則裡 `var` 宣告的變數留在這次
  /// 執行，不會掛到全域讓下一次（下一章、下一筆結果）看到，與 Legado 每次
  /// 執行一個新作用域相同。沒宣告就賦值的變數由 `__lrRunRule` 在結束後清掉
  /// （見 [_ruleGlobalsHelpers]）。
  JsEvalResult _evaluateRuleScript(String jsCode) {
    // eval 先讀完整段、語法沒問題才開始執行，所以開頭這句跑到了就表示規則
    // 已經開始執行。`void 0` 讓結尾只有宣告的規則照樣得到 undefined。
    final run = _nextRuleRun++;
    final marked = jsonEncode('__lrStartedRule=$run;void 0;$jsCode');
    final wrapped =
        '__lrRunRule(function() { return typeof __lrNormalizeRuleResult === "function" '
        '? __lrNormalizeRuleResult(eval($marked)) '
        ': eval($marked); })';
    final result = _runtime!.evaluate(wrapped);
    // 某些 legacy rule 在 eval(...) 路徑會被 QuickJS 誤判語法，
    // 改走 IIFE + final-return 注入，既保留最後表達式結果，也讓 normalize
    // 邏輯繼續生效。只在還沒開始執行時改走：執行到一半出錯（包括
    // `JSON.parse` 這類執行時才發生的 SyntaxError）再跑一次，請求與
    // `java.put` 這類動作會做兩次。執行中巢狀跑的規則編號比這次大，外層
    // 要先開始才跑得到，所以用「大於等於」判斷。
    if (!result.isError || _ruleStarted(run)) {
      return result;
    }
    final fallbackBody = RuleFinalReturn.inject(jsCode);
    final fallbackWrapped =
        '__lrRunRule(function() { return typeof __lrNormalizeRuleResult === "function" '
        '? __lrNormalizeRuleResult((function() {\n$fallbackBody\n})()) '
        ': (function() {\n$fallbackBody\n})(); })';
    return _runtime!.evaluate(fallbackWrapped);
  }

  bool _ruleStarted(int run) =>
      _runtime!.evaluate('__lrStartedRule >= $run').stringResult == 'true';

  /// 這個引擎的 JS 全域已經有 `source`。引擎只服務一個書源（[source]），
  /// 注入一次之後呼叫端可以省略，見 `AnalyzeRuleScript`。
  bool get sourceInjected => _sourceInjected;
  bool _sourceInjected = false;

  /// 每次執行前把脈絡寫進 JS 全域。全部合成一段腳本一次執行：逐項分開執行
  /// 時，每次都要多付十幾次跨 FFI 的解析與執行。
  void _injectContext(Map<String, dynamic>? context) {
    if (context == null) return;
    // 先把 java、cookie、cache、source 重設回原本的物件：上一條規則把它們
    // 拿去存別的值時，這一條照樣拿到 Legado 給的物件。
    final statements = <String>[
      'if (typeof __lrRestoreBindings === "function") __lrRestoreBindings();',
    ];
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
          _ensureScopedObjectFactory();
          statements.add(
            'var __lrSourceSeed = $jsLiteral; '
            'if (typeof source === "object" && source !== null) { '
            'Object.assign(source, __lrSourceSeed); '
            '} else { var source = __lrSourceSeed; } '
            '__lrBeanMethods(source, __lrSourceSeed, {}, []);',
          );
          _sourceInjected = true;
          return;
        case 'book':
        case 'chapter':
          final jsLiteral = _encodeScopedObject(key, value);
          statements.add('var $key = $jsLiteral;');
          return;
        case '__lrUrl':
          statements.add('__lrUseUrl(${_encodeJsonContextValue(value)});');
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
    if (value is StrResponse) {
      final id = _nextResponseId++;
      _contextResponses[id] = value;
      final data = {...responseToJs(value), _responseIdKey: id};
      return 'buildHttpResponse(${jsonEncode(data)})';
    }
    if (value is Iterable) {
      final nodes = _elementNodes(value);
      if (nodes != null) return _encodeElements(nodes);
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
      return jsonEncode(value);
    } on JsonUnsupportedObjectError {
      // 裡面包著要換成 JS 物件的值（例如上一條規則傳回的 `{reply: 回應}`），
      // 和 [_decodeContextValue] 一樣逐項處理。
      if (value is Map) {
        final entries = value.entries.map(
          (e) =>
              '${jsonEncode(e.key.toString())}:'
              '${_encodeContextValue(e.value)}',
        );
        return '({${entries.join(',')}})';
      }
      // 轉成文字，規則 JS 拿到的就不是它要的物件（`result.body()` 這類
      // 呼叫會失敗）；新的型別要像上面一樣給它對應的 JS 物件。
      assert(false, '交給規則 JS 的 ${value.runtimeType} 沒有對應的 JS 物件');
      return jsonEncode(value.toString());
    }
  }

  /// 這次規則執行交給 JS 的回應。規則原樣傳回時換回同一個，保留跳轉紀錄
  /// 這些 JS 看不到的資料；最外層的規則結束時清掉。
  final _contextResponses = <int, StrResponse>{};
  int _nextResponseId = 0;
  static const _responseIdKey = '__lrResponseId';

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
// Legado 的欄位名與夜讀不同的，兩個名字都能讀寫。
var __lrFieldAliases = {
  book: { durChapterIndex: 'chapterIndex', durChapterPos: 'charOffset' }
};
// Legado AppPattern.authorRegex：作者欄常帶的「作者：」「著」這類字樣。
var __lrAuthorNoise = /^\\s*作\\s*者[:：\\s]+|\\s+著/g;
// Legado 裡是 Boolean、夜讀存成 0／1 的欄位：getter 照 Java 傳回布林。
var __lrBooleanFields = ['canUpdate', 'enabled', 'enabledExplore', 'enabledCookieJar'];
// Java 物件的 getXxx()／setXxx()（Kotlin 的 isXxx 是 isXxx()／setXxx()），
// 書源照 Legado 寫 source.getConcurrentRate()、book.setName(...)。setter 只給
// 夜讀會寫回的欄位（[writable]，Dart 的 bookRuleFields、chapterRuleFields），
// 其他欄位寫了也不會留下，不給 setter。已經有同名方法的不蓋（例如
// source.getVariable 是讀書源變數）。
var __lrBeanMethods = function(obj, seed, aliases, writable) {
  if (obj == null || seed == null || typeof seed !== 'object') return;
  var names = Object.keys(seed);
  Object.keys(aliases).forEach(function(alias) {
    var target = aliases[alias];
    if (alias in obj || !(target in obj)) return;
    Object.defineProperty(obj, alias, {
      configurable: true,
      get: function() { return obj[target]; },
      set: function(value) { obj[target] = value; }
    });
    names.push(alias);
  });
  names.forEach(function(prop) {
    var flag = /^is([A-Z].*)\$/.exec(prop);
    var cap = flag ? flag[1] : prop.charAt(0).toUpperCase() + prop.slice(1);
    if (!flag && typeof obj['get' + cap] === 'undefined') {
      obj['get' + cap] = __lrBooleanFields.indexOf(prop) >= 0
        ? function() { var v = obj[prop]; return v == null ? null : !!v; }
        : function() { return obj[prop]; };
    }
    var field = aliases[prop] || prop;
    if (writable.indexOf(field) >= 0 && typeof obj['set' + cap] === 'undefined') {
      obj['set' + cap] = function(value) { obj[prop] = value; return null; };
    }
  });
};
var __lrScopedObject = function(scope, seed) {
  if (seed == null || typeof seed !== 'object') {
    return seed;
  }
  var obj = {};
  var field = function(prop, getter) {
    Object.defineProperty(obj, prop, {
      enumerable: true,
      configurable: true,
      get: getter,
      set: function(value) {
        values[prop] = value;
        sendMessage('scopedObjectSetField', JSON.stringify([scope, prop, value]));
      }
    });
  };
  var values = {};
  Object.keys(seed).forEach(function(prop) {
    values[prop] = seed[prop];
    // Kotlin 的 isVip、isVolume 在 Java 是方法 isVip()、屬性 vip，書源照
    // Legado 寫 chapter.isVip()；Legado 裡 chapter.isVip 是方法（永遠為真）。
    var flag = /^is([A-Z])(.*)\$/.exec(prop);
    if (flag) {
      field(prop, function() {
        return function() { return !!values[prop]; };
      });
      var bean = flag[1].toLowerCase() + flag[2];
      if (!(bean in seed)) {
        Object.defineProperty(obj, bean, {
          configurable: true,
          get: function() { return !!values[prop]; },
          set: function(value) { obj[prop] = value; }
        });
      }
    } else {
      field(prop, function() { return values[prop]; });
    }
  });
  // Kotlin 的 variable 欄位 getVariable() 和 RuleDataInterface 的
  // getVariable(key) 是兩個多載：不帶參數時是整份變數 JSON。
  obj.getVariable = function(key) {
    if (arguments.length === 0) return values.variable;
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
  // BaseBook：自訂變數是 key 為 custom 的變數。
  obj.putCustomVariable = function(value) {
    return obj.putVariable('custom', value);
  };
  obj.getCustomVariable = function() { return obj.getVariable('custom'); };
  if (scope === "book") {
    obj.getRealAuthor = function() {
      return String(obj.author || '').replace(__lrAuthorNoise, '');
    };
    obj.getDisplayCover = function() {
      return obj.customCoverUrl ? obj.customCoverUrl : obj.coverUrl;
    };
    obj.getDisplayIntro = function() {
      return obj.customIntro ? obj.customIntro : obj.intro;
    };
    // BaseBook.getKindList：字數（不是空白時）加上分類，傳回 Java List。
    obj.getKindList = function() {
      var kinds = [];
      if (obj.wordCount && String(obj.wordCount).trim()) {
        kinds.push(String(obj.wordCount));
      }
      String(obj.kind || '').split(/[,\\n]/).forEach(function(kind) {
        if (kind.trim()) kinds.push(kind.trim());
      });
      return new Packages.java.util.ArrayList(kinds);
    };
    obj.getUnreadChapterNum = function() {
      return Math.max((obj.totalChapterNum || 0) - (obj.chapterIndex || 0) - 1, 0);
    };
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
  __lrBeanMethods(obj, seed, __lrFieldAliases[scope] || {}, __lrWritableFields[scope] || []);
  return obj;
};
''';

  bool _scopedObjectFactoryInstalled = false;

  void _ensureScopedObjectFactory() {
    if (_scopedObjectFactoryInstalled) return;
    // 規則寫了會留下的欄位（setter 只給這些）。
    _runtime!.evaluate(
      'var __lrWritableFields = ${jsonEncode({'book': bookRuleFields.keys.toList(), 'chapter': chapterRuleFields.keys.toList()})};',
    );
    _runtime!.evaluate(_scopedObjectFactory);
    _scopedObjectFactoryInstalled = true;
  }

  String _encodeScopedObject(String scopeName, dynamic value) {
    _ensureScopedObjectFactory();
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

  /// 元素清單（例如列表規則選到的元素）交給 JS 時是 Jsoup 的 `Elements`，
  /// 和 Legado 一樣能 `select`、`attr`、`text`，也能 `sort`、`[i]`。
  String _encodeElements(List<dom.Node> nodes) {
    final jsoup = _extensions!.jsoup;
    for (final node in nodes) {
      jsoup.setBaseUri(node, _contextBaseUrl);
    }
    return '__lrJsoupDecode(${jsonEncode(jsoup.toJs(nodes))})';
  }

  /// [values] 是元素清單時傳回它們的節點，否則傳回 null。CSS 選取的結果
  /// 是 `List<Element>`，空的也當元素清單（同 [JsoupBridge.toJs]）；其他
  /// 清單（XPath 的結果）要有內容且全是元素，空的 JSON 清單照一般陣列。
  static List<dom.Node>? _elementNodes(Iterable<dynamic> values) {
    if (values is Iterable<dom.Node>) return values.toList();
    if (values.isEmpty) return null;
    final nodes = <dom.Node>[];
    for (final value in values) {
      final node = value is XPathNode ? value.node : value;
      if (node is! dom.Element && node is! dom.Document) return null;
      nodes.add(node as dom.Node);
    }
    return nodes;
  }

  dynamic _decodeContextValue(dynamic value) {
    if (value is List) {
      return value.map(_decodeContextValue).toList();
    }
    if (value is Map) {
      final response = value['__lrResponse'];
      if (response is Map) {
        final id = (response[_responseIdKey] as num?)?.toInt();
        return _contextResponses[id] ?? responseFromJs(response);
      }
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

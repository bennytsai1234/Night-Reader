import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:xpath_selector/xpath_selector.dart' show XPathNode;
import 'package:night_reader/core/engine/analyze_rule/analyze_rule_support.dart';
import 'package:night_reader/core/engine/rule_data_fields.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/rule_data_interface.dart';
import 'package:night_reader/core/models/search_book.dart';

import 'js_extensions_base.dart';
import 'extensions/js_blocking_tasks.dart';
import 'extensions/js_network_extensions.dart';
import 'extensions/js_crypto_extensions.dart';
import 'extensions/js_string_extensions.dart';
import 'extensions/js_file_extensions.dart';
import 'extensions/js_font_extensions.dart';
import 'extensions/js_java_object.dart';
import 'extensions/js_jsoup_extensions.dart';

import 'package:night_reader/core/services/cookie_store.dart';

export 'js_extensions_base.dart';
export 'extensions/js_network_extensions.dart';
export 'extensions/js_crypto_extensions.dart';
export 'extensions/js_string_extensions.dart';
export 'extensions/js_file_extensions.dart';
export 'extensions/js_font_extensions.dart';

/// JsExtensions - JS 橋接總控 (重構後)
/// (原 Android help/JsExtensions.kt)
class JsExtensions extends JsExtensionsBase {
  JsExtensions(super.runtime, {super.source, super.ruleContext});

  /// 注入完整 JS 環境
  ///
  /// 順序重要：`installBlockingCalls` 必須在任何會用到 `__lrWait` 的 shim
  /// (`injectJavaObjectJs` / `injectNetworkExtensions` / ...) 之前。
  void inject() {
    installBlockingCalls();
    _injectCoreHandlers();
    injectNetworkExtensions();
    injectCryptoExtensions();
    injectStringExtensions();
    injectFileExtensions();
    injectFontExtensions();
    // Jsoup 在 java 物件之前：java.getElements 與 Packages.org 要用到它。
    injectJsoupExtensions();
    injectJavaObjectJs();
  }

  void _injectCoreHandlers() {
    // ─── 純同步 (sharedScope / log / toast) ─────────────────────
    runtime.onMessage('scopePut', (args) {
      final payload = args;
      if (payload is List && payload.length >= 2) {
        final key = payload[0].toString();
        final value = payload[1];
        final stringValue = value == null ? '' : value.toString();
        if (ruleContext != null) {
          try {
            ruleContext.put(key, stringValue);
          } catch (_) {
            JsExtensionsBase.sharedScope[key] = stringValue;
          }
        } else {
          JsExtensionsBase.sharedScope[key] = stringValue;
        }
        if (source != null) {
          final scopedKey = source!.ruleVariableCacheKey(key);
          cacheManager.putMemory(scopedKey, stringValue);
          unawaited(cacheManager.put(scopedKey, stringValue));
        }
      }
      return null;
    });
    runtime.onMessage('scopeGet', (args) {
      final key = args.toString();
      if (ruleContext != null) {
        try {
          final value = ruleContext.get(key);
          if (value != null && value.toString().isNotEmpty) {
            return value.toString();
          }
        } catch (_) {}
      }
      if (source != null) {
        final scopedKey = source!.ruleVariableCacheKey(key);
        final cached = cacheManager.getFromMemory(scopedKey);
        if (cached != null && cached.toString().isNotEmpty) {
          return cached.toString();
        }
      }
      final value = JsExtensionsBase.sharedScope[key];
      return value == null ? '' : value.toString();
    });
    runtime.onMessage('ruleGetString', (args) {
      final rule = args.toString();
      if (ruleContext != null) {
        try {
          return ruleContext.getString(rule);
        } catch (_) {}
      }
      return '';
    });
    runtime.onMessage('ruleGetStringList', (args) {
      final rule = args.toString();
      if (ruleContext != null) {
        try {
          return ruleContext.getStringList(rule);
        } catch (_) {}
      }
      return const <String>[];
    });
    // java.getElement(s)：HTML 的結果是真的 Jsoup 元素（JsoupBridge），
    // JSON 這類規則的結果照原樣。
    runtime.onMessage('ruleGetElement', (args) {
      final rule = args.toString();
      if (ruleContext != null) {
        try {
          return _toJsRuleValue(ruleContext.getElement(rule));
        } catch (_) {}
      }
      return '';
    });
    runtime.onMessage('ruleGetElements', (args) {
      final rule = args.toString();
      if (ruleContext != null) {
        try {
          final values = ruleContext.getElements(rule) as List;
          return values.map(_toJsRuleValue).toList();
        } catch (_) {}
      }
      return const <dynamic>[];
    });
    runtime.onMessage('ruleSetContent', (args) {
      final payload = args;
      if (payload is List && payload.isNotEmpty && ruleContext != null) {
        try {
          final nextBaseUrl = payload.length > 1
              ? payload[1]?.toString()
              : null;
          ruleContext.setContent(payload[0], baseUrl: nextBaseUrl);
        } catch (_) {}
      }
      return null;
    });
    runtime.onMessage('log', (args) {
      debugPrint('JS_LOG: ${_compactJsBridgeLog(args)}');
      return args;
    });
    runtime.onMessage('toast', (args) {
      debugPrint('JS_TOAST: ${_compactJsBridgeLog(args)}');
      return null;
    });
    runtime.onMessage('scopedObjectGetVariable', (args) {
      final payload = args;
      if (payload is List && payload.length >= 2) {
        return _getScopedObjectVariable(
          payload[0].toString(),
          payload[1].toString(),
        );
      }
      return '';
    });
    runtime.onMessage('scopedObjectPutVariable', (args) {
      final payload = args;
      if (payload is List && payload.length >= 2) {
        _putScopedObjectVariable(
          payload[0].toString(),
          payload[1].toString(),
          payload.length > 2 ? payload[2] : null,
        );
      }
      return null;
    });
    runtime.onMessage('scopedObjectGetField', (args) {
      final payload = args;
      if (payload is List && payload.length >= 2) {
        return _getScopedObjectField(
          payload[0].toString(),
          payload[1].toString(),
        );
      }
      return null;
    });
    runtime.onMessage('scopedObjectSetField', (args) {
      final payload = args;
      if (payload is List && payload.length >= 3) {
        _setScopedObjectField(
          payload[0].toString(),
          payload[1].toString(),
          payload[2],
        );
      }
      return null;
    });

    // ─── Fire-and-forget async (JS 不讀回傳值) ──────────────────
    // 直接啟動 Future，不 block handler；失敗寫 log 但不 reject JS
    runtime.onMessage('setCookie', (args) {
      if (args is List && args.length >= 2) {
        CookieStore().setCookie(args[0].toString(), args[1].toString());
      }
      return null;
    });
    runtime.onMessage('removeCookie', (args) {
      CookieStore().removeCookie(args.toString());
      return null;
    });
    runtime.onMessage('putCache', (args) {
      if (args is List && args.length >= 2) {
        final saveTime = args.length > 2
            ? int.tryParse(args[2].toString()) ?? 0
            : 0;
        cacheManager.put(
          args[0].toString(),
          args[1].toString(),
          saveTimeSeconds: saveTime,
        );
      }
      return null;
    });
    runtime.onMessage('deleteCache', (args) {
      cacheManager.delete(args.toString());
      return null;
    });
    runtime.onMessage('sourcePut', (args) {
      if (args is List && args.length >= 2 && source != null) {
        final key = args[0].toString();
        final value = args[1].toString();
        cacheManager.put(source!.ruleVariableCacheKey(key), value);
      }
      return null;
    });
    runtime.onMessage('sourcePutLoginInfo', (args) {
      if (source != null) {
        source!.putLoginInfo(args.toString());
      }
      return null;
    });
    runtime.onMessage('sourceSetVariable', (args) {
      if (source != null) {
        final decoded = args;
        source!.setVariableSync(decoded?.toString());
      }
      return null;
    });
    runtime.onMessage('sourceGetHeaderMap', (args) {
      if (source == null) return <String, String>{};
      final includeLoginHeader = args is bool ? args : true;
      return source!.getHeaderMapSync(hasLoginHeader: includeLoginHeader);
    });

    // ─── 要等的：快取、Cookie、書源變數（讀資料庫與檔案） ─────────
    onBlocking('getCache', (key) => cached('$key'));

    onBlocking('cacheTextFile', (payload) {
      final url = payload is List && payload.isNotEmpty
          ? payload[0].toString()
          : payload.toString();
      final saveTime = payload is List && payload.length > 1
          ? int.tryParse(payload[1].toString()) ?? 0
          : 0;
      return BlockingCall.run(cachedText(url, saveTime));
    });

    onBlocking('importScript', (payload) {
      final path = payload.toString();
      final content = path.startsWith('http')
          ? BlockingCall.run(cachedText(path, 0)) as String
          : (File(path).existsSync() ? File(path).readAsStringSync() : '');
      if (content.trim().isEmpty) {
        throw Exception('$path 內容獲取失敗或者為空');
      }
      return _wrapImportedScript(content);
    });

    onBlocking('sourceGet', (key) {
      if (source == null) return '';
      return cached(source!.ruleVariableCacheKey(key)) ?? '';
    });

    onBlocking('sourceGetLoginInfo', (_) {
      if (source == null) return '';
      return cached(source!.loginInfoCacheKey) ?? '';
    });

    onBlocking('sourceGetVariable', (_) {
      if (source == null) return '';
      return cached(source!.variableCacheKey) ?? '';
    });

    onBlocking('cookieGet', (url) => siteCookie('$url'));

    // CookieStore 目前沒有 allCookies API，回傳空字串維持既有行為
    onBlocking('allCookies', (_) => '');
  }

  /// 快取裡的 [key]：這個 isolate 的記憶體有就直接用，否則停住交給網路
  /// isolate 讀資料庫與檔案。
  String? cached(String key) =>
      cacheManager.getMemoryText(key) ??
      BlockingCall.run(cacheRead(key)) as String?;

  /// [url] 的站點 Cookie，和 [cached] 一樣先看記憶體。
  String siteCookie(String url) =>
      cookieStore.getMemoryCookie(url) ??
      BlockingCall.run(cookieRead(url)) as String;

  String _compactJsBridgeLog(dynamic args) {
    final text = args.toString();
    const limit = 1200;
    if (text.length <= limit) {
      return text;
    }
    return '${text.substring(0, limit)}... [truncated ${text.length - limit} chars]';
  }

  dynamic _resolveScopedObject(String scopeName) {
    if (ruleContext == null) return null;
    try {
      switch (scopeName) {
        case 'book':
          return ruleContext.ruleData;
        case 'chapter':
          return ruleContext.chapter;
      }
    } catch (_) {}
    return null;
  }

  String _getScopedObjectVariable(String scopeName, String key) {
    final target = _resolveScopedObject(scopeName);
    if (target is RuleDataInterface) {
      return target.getVariable(key);
    }
    return '';
  }

  void _putScopedObjectVariable(String scopeName, String key, dynamic value) {
    final target = _resolveScopedObject(scopeName);
    if (target is RuleDataInterface) {
      target.putVariable(key, value?.toString());
    }
  }

  dynamic _getScopedObjectField(String scopeName, String fieldName) {
    final target = _resolveScopedObject(scopeName);
    if (target is Book) {
      switch (fieldName) {
        case 'reverseToc':
          return target.readConfig?.reverseToc ?? false;
        case 'useReplaceRule':
          return target.readConfig?.useReplaceRule ?? false;
      }
    }
    return null;
  }

  void _setScopedObjectField(
    String scopeName,
    String fieldName,
    dynamic value,
  ) {
    final target = _resolveScopedObject(scopeName);
    switch (target) {
      case final Book book:
        bookRuleFields[fieldName]?.write(book, value);
      case final SearchBook book:
        searchBookRuleFields[fieldName]?.write(book, value);
      case final BookChapter chapter:
        chapterRuleFields[fieldName]?.write(chapter, value);
    }
  }

  dynamic _toJsRuleValue(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    final node = value is XPathNode ? value.node : value;
    if (node is dom.Node) {
      final context = ruleContext;
      final baseUrl = context == null
          ? null
          : (context.redirectUrl ?? context.baseUrl) as String?;
      jsoup.setBaseUri(node, baseUrl);
      return jsoup.toJs(node);
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), _toJsRuleValue(item)),
      );
    }
    if (value is Iterable) {
      return value.map(_toJsRuleValue).toList();
    }
    return stringifyRuleResult(value);
  }

  String _wrapImportedScript(String content) {
    final indented = content
        .split('\n')
        .map((line) => line.isEmpty ? '' : '  $line')
        .join('\n');
    return '''
(function(__lrGlobal) {
  var exports = undefined;
  var module = undefined;
  var define = undefined;
  var require = undefined;
$indented
}).call(
  typeof globalThis !== "undefined" ? globalThis : this,
  typeof globalThis !== "undefined" ? globalThis : this
);
''';
  }
}

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

import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/source_interaction.dart';

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
    runtime.onMessage('toast', (args) => _toast(args, long: false));
    runtime.onMessage('longToast', (args) => _toast(args, long: true));
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

    // ─── 寫入（JS 不讀回傳值） ─────────────────────────────────
    // 記憶體當下就寫好，之後讀得到；資料庫在背景寫，記在 [pendingWrites]，
    // 要確定寫完的地方用 [settleWrites] 等。
    runtime.onMessage('setCookie', (args) {
      if (args is List && args.length >= 2) {
        _track(CookieStore().setCookie(args[0].toString(), args[1].toString()));
      }
      return null;
    });
    runtime.onMessage('removeCookie', (args) {
      _track(CookieStore().removeCookie(args.toString()));
      return null;
    });
    runtime.onMessage('putCache', (args) {
      if (args is List && args.length >= 2) {
        final saveTime = args.length > 2
            ? int.tryParse(args[2].toString()) ?? 0
            : 0;
        _track(
          cacheManager.put(
            args[0].toString(),
            args[1].toString(),
            saveTimeSeconds: saveTime,
          ),
        );
      }
      return null;
    });
    runtime.onMessage('deleteCache', (args) {
      _track(cacheManager.delete(args.toString()));
      return null;
    });
    runtime.onMessage('sourcePut', (args) {
      if (args is List && args.length >= 2 && source != null) {
        final key = args[0].toString();
        final value = args[1].toString();
        _track(cacheManager.put(source!.ruleVariableCacheKey(key), value));
      }
      return null;
    });
    runtime.onMessage('sourcePutLoginInfo', (args) {
      if (source != null) _track(source!.putLoginInfo(args.toString()));
      return null;
    });
    runtime.onMessage('sourceRemoveLoginInfo', (_) {
      if (source != null) _track(source!.removeLoginInfo());
      return null;
    });
    runtime.onMessage('sourcePutLoginHeader', (args) {
      if (source != null) _track(source!.putLoginHeader(args.toString()));
      return null;
    });
    runtime.onMessage('sourceRemoveLoginHeader', (_) {
      if (source != null) _track(source!.removeLoginHeader());
      return null;
    });
    runtime.onMessage('sourceSetVariable', (args) {
      if (source != null) _track(source!.setVariable(args?.toString()));
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
      // 和 Legado 一樣原樣交出，書源自己 `eval(String(...))`：裡面的函式與
      // 變數就留在書源 eval 的地方，後面的規則叫得到。
      return content;
    });

    onBlocking('sourceGet', (key) {
      if (source == null) return '';
      return cached(source!.ruleVariableCacheKey(key)) ?? '';
    });

    onBlocking('sourceGetLoginInfo', (_) {
      if (source == null) return '';
      return cached(source!.loginInfoCacheKey) ?? '';
    });

    onBlocking('sourceGetLoginHeader', (_) {
      if (source == null) return '';
      return cached(source!.loginHeaderCacheKey) ?? '';
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

  /// 規則 JS 觸發、資料庫還沒寫完的寫入（快取、Cookie、登入資料、書源
  /// 變數）。規則 JS 不等它們；要確定寫完的地方（登入頁的動作結束前，
  /// 之後就結束它的 isolate）用 [settleWrites]。
  static final Set<Future<void>> pendingWrites = {};

  static void _track(Future<void> write) {
    pendingWrites.add(write);
    write
        .catchError(
          (Object error, StackTrace stackTrace) => AppLog.e(
            '規則 JS 的寫入失敗: $error',
            error: error,
            stackTrace: stackTrace,
          ),
        )
        .whenComplete(() => pendingWrites.remove(write));
  }

  /// 等目前觸發的寫入都寫完（失敗的已經記在日誌）。
  static Future<void> settleWrites() async {
    while (pendingWrites.isNotEmpty) {
      await Future.wait(
        pendingWrites.toList().map((write) => write.catchError((_) {})),
      );
    }
  }

  /// `java.toast`／`longToast`：登入頁按下的動作送到登入頁顯示，其他地方
  /// 只記在日誌（[SourceInteraction.show]）。
  Object? _toast(dynamic args, {required bool long}) {
    final text = '${args ?? ''}';
    AppLog.d('書源訊息: ${_compactJsBridgeLog(text)}');
    if (SourceInteraction.allowed && text.isNotEmpty) {
      SourceInteraction.show(SourceMessage(text, long: long));
    }
    return null;
  }

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
}

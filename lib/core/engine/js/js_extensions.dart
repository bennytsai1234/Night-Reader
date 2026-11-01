import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:json_path/json_path.dart';
import 'package:xpath_selector/xpath_selector.dart' show XPathNode;
import 'package:night_reader/core/engine/analyze_rule.dart' show AnalyzeRule;
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
import 'extensions/js_java_classes.dart';
import 'extensions/js_java_object.dart';
import 'extensions/js_jsoup_extensions.dart';
import 'extensions/js_url_extensions.dart';

import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/source_interaction.dart';
import 'package:night_reader/core/utils/html_formatter.dart';

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
    // Java 類別用到 java 物件與它定義的加解密類別。
    injectJavaClasses();
    // 網址裡的 java 用到 Java 類別（LinkedHashMap、ByteArrayInputStream）。
    injectUrlExtensions();
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
    // java.getString(rule[, mContent, isUrl])、getString(rule, unescape)、
    // getStringList(rule[, mContent, isUrl])：JS 送 [規則, 內容, isUrl, unescape]，
    // 內容是 null 時解析目前內容（同 Legado）。
    runtime.onMessage('ruleGetString', (args) {
      final (rule, content, isUrl, unescape) = _ruleCall(args);
      if (ruleContext != null) {
        try {
          return ruleContext.getString(
            rule,
            mContent: content,
            isUrl: isUrl,
            unescape: unescape,
          );
        } catch (_) {}
      }
      return '';
    });
    runtime.onMessage('ruleGetStringList', (args) {
      final (rule, content, isUrl, _) = _ruleCall(args);
      if (ruleContext != null) {
        try {
          return ruleContext.getStringList(
            rule,
            mContent: content,
            isUrl: isUrl,
          );
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
    // java.setBaseUrl／setRedirectUrl：之後的規則用這個網址補相對網址。
    // setRedirectUrl 同 Legado：data: 與不是網址的不改，傳回改完的網址。
    runtime.onMessage('ruleSetUrl', (args) {
      final rule = ruleContext;
      if (rule is! AnalyzeRule || args is! List || args.length < 2) return null;
      final url = args[1]?.toString();
      if (args[0] == 'base') {
        if (url != null) rule.baseUrl = url;
        return null;
      }
      final parsed = url == null ? null : Uri.tryParse(url);
      if (url != null &&
          !url.startsWith('data:') &&
          parsed != null &&
          parsed.hasScheme &&
          parsed.host.isNotEmpty) {
        rule.setRedirectUrl(url);
      }
      return rule.redirectUrl;
    });
    onBlocking('ruleRefreshTocUrl', (_) {
      final rule = ruleContext;
      if (rule is! AnalyzeRule) {
        throw StateError('java.refreshTocUrl() 只能在目錄的預整理 JS（preUpdateJs）裡呼叫');
      }
      rule.requestTocUrlRefresh();
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
    runtime.onMessage('clearCookies', (_) {
      _track(CookieStore().clearAll());
      return null;
    });
    runtime.onMessage(
      'cookieToMap',
      (args) => CookieStore().cookieToMap(args?.toString() ?? ''),
    );
    runtime.onMessage(
      'mapToCookie',
      (args) => CookieStore().mapToCookie({
        for (final MapEntry(:key, :value) in (args as Map).entries)
          key.toString(): value.toString(),
      }),
    );
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
    // cache.putMemory／getFromMemory／deleteMemory：只在記憶體，App 關掉就
    // 沒了（同 Legado）。值照 JSON 存取，物件與陣列讀回來是內容相同的新物件。
    runtime.onMessage('cachePutMemory', (args) {
      if (args is List && args.isNotEmpty) {
        cacheManager.putMemory(
          args[0].toString(),
          args.length > 1 ? args[1] : null,
        );
      }
      return null;
    });
    runtime.onMessage(
      'cacheGetMemory',
      (args) => cacheManager.getFromMemory(args.toString()),
    );
    runtime.onMessage('cacheDeleteMemory', (args) {
      cacheManager.deleteMemory(args.toString());
      return null;
    });
    // java.htmlFormat：HTML 轉文字、保留圖片。
    runtime.onMessage(
      'htmlFormat',
      (args) => HtmlFormatter.formatKeepImg(args?.toString()),
    );
    // java.toURL(url[, baseUrl])：網址拆成 host、origin、pathname、searchParams
    // （Legado JsURL；查詢參數的值照 UTF-8 解碼）。
    // 網址不完整（沒有協定）時是 null，由 JS 丟 MalformedURLException。
    runtime.onMessage('toURL', (args) {
      final list = args is List ? args : [args];
      final raw = list.first.toString();
      final base = list.length > 1 && list[1] != null ? list[1].toString() : '';
      final Uri? uri;
      try {
        uri = base.isEmpty ? Uri.parse(raw) : Uri.parse(base).resolve(raw);
      } on FormatException {
        return null;
      }
      if (!uri.hasScheme) return null;
      final origin = uri.hasPort
          ? '${uri.scheme}://${uri.host}:${uri.port}'
          : '${uri.scheme}://${uri.host}';
      Map<String, String>? params;
      if (uri.hasQuery) {
        params = {};
        for (final pair in uri.query.split('&')) {
          final eq = pair.indexOf('=');
          if (eq < 0) continue;
          params[pair.substring(0, eq)] = _urlDecode(pair.substring(eq + 1));
        }
      }
      return {
        'host': uri.host,
        'origin': origin,
        'pathname': uri.path,
        'searchParams': params,
        // java.net.URL 也用這裡拆好的網址：query 是原樣，不解碼。
        'protocol': uri.scheme,
        'port': uri.hasPort ? uri.port : -1,
        'query': uri.hasQuery ? uri.query : null,
        'ref': uri.hasFragment ? uri.fragment : null,
        'userInfo': uri.userInfo.isEmpty ? null : uri.userInfo,
        'href': uri.toString(),
      };
    });
    // Thread.sleep／LockSupport.parkNanos：這條書源 isolate 停住，同 Java。
    // 只有書源 isolate 停得起；畫面那條 isolate 不能停（ADR 0034），丟錯誤
    // 讓規則 JS 接到，和其他要等的呼叫一樣。
    onBlocking('_sleep', (args) {
      if (!BlockingCall.available) throw const BlockingCallUnavailable();
      final ms = args is num ? args.toInt() : int.tryParse('$args') ?? 0;
      if (ms > 0) sleep(Duration(milliseconds: ms));
      return null;
    });
    // com.jayway.jsonpath.JsonPath.read(json, path)：確定的路徑傳回那個值，
    // 有萬用字元、切片、篩選或 `..` 的傳回清單。
    runtime.onMessage('_jsonPathRead', (args) {
      final payload = args as List;
      var json = payload[0];
      if (json is String) json = jsonDecode(json);
      final path = payload[1].toString();
      final values = JsonPath(path).readValues(json).toList();
      final indefinite = RegExp(r'\*|\.\.|\[\?|\[[^\]]*[:,][^\]]*\]')
          .hasMatch(path);
      if (indefinite) return values;
      return values.isEmpty ? null : values.first;
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
      // 網址抓回來存著；其他是快取資料夾裡的相對路徑（同 Legado）。
      final content = path.startsWith('http')
          ? BlockingCall.run(cachedText(path, 0)) as String
          : readCacheText(path);
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

  /// Java 的 URLDecoder.decode(s, "utf-8")：+ 變空白、%XX 照 UTF-8 解，解不出
  /// 的位元組換成 �（Legado JsURL 的 searchParams）。
  static String _urlDecode(String text) {
    final bytes = <int>[];
    final chars = text.replaceAll('+', ' ').runes.toList();
    bool isHex(int c) =>
        (c >= 0x30 && c <= 0x39) ||
        (c >= 0x41 && c <= 0x46) ||
        (c >= 0x61 && c <= 0x66);
    for (var i = 0; i < chars.length; i++) {
      if (chars[i] == 0x25 &&
          i + 2 < chars.length &&
          isHex(chars[i + 1]) &&
          isHex(chars[i + 2])) {
        bytes.add(
          int.parse(String.fromCharCodes(chars, i + 1, i + 3), radix: 16),
        );
        i += 2;
      } else {
        bytes.addAll(utf8.encode(String.fromCharCode(chars[i])));
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  (String, dynamic, bool, bool) _ruleCall(dynamic args) {
    if (args is! List) return (args.toString(), null, false, true);
    return (
      args[0].toString(),
      args.length > 1 ? _fromJsRuleValue(args[1]) : null,
      args.length > 2 && args[2] == true,
      args.length <= 3 || args[3] != false,
    );
  }

  /// JS 交來的規則內容（`__lrNormalizeRuleResult` 的結果）換回 Dart：元素
  /// 換回真的節點，其他照 JSON。
  dynamic _fromJsRuleValue(dynamic value) {
    if (value is List) return value.map(_fromJsRuleValue).toList();
    if (value is Map) {
      final id = value['__lrElementId'];
      if (id is num) return jsoup.node(id.toInt()) ?? value['outerHtml'];
      if (value['__html'] != null) return value['__html'].toString();
      return value.map((k, v) => MapEntry(k.toString(), _fromJsRuleValue(v)));
    }
    return value;
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

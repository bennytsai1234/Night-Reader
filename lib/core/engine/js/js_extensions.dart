import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:reader/core/engine/analyze_rule/analyze_rule_support.dart';
import 'package:reader/core/engine/parsers/css/analyze_by_css_support.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/models/chapter.dart';
import 'package:reader/core/models/rule_data_interface.dart';
import 'package:reader/core/models/search_book.dart';
import 'js_extensions_base.dart';
import 'extensions/js_network_extensions.dart';
import 'extensions/js_crypto_extensions.dart';
import 'extensions/js_string_extensions.dart';
import 'extensions/js_file_extensions.dart';
import 'extensions/js_font_extensions.dart';
import 'extensions/js_java_object.dart';
import 'js_encode_utils.dart';
import 'package:reader/core/services/http_client.dart';
import 'package:reader/core/services/cookie_store.dart';

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
  /// 順序重要：`setupPromiseBridge` 必須在任何會用到 `__asyncCall` 的 shim
  /// (`injectJavaObjectJs` / `injectNetworkExtensions` / ...) 之前。
  void inject() {
    setupPromiseBridge();
    _injectCoreHandlers();
    injectNetworkExtensions();
    injectCryptoExtensions();
    injectStringExtensions();
    injectFileExtensions();
    injectFontExtensions();
    injectJavaObjectJs();
  }

  void _injectCoreHandlers() {
    // ─── 純同步 (sharedScope / log / toast) ─────────────────────
    runtime.onMessage('scopePut', (args) {
      final payload = _decodeSyncArgs(args);
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
          final scopedKey = 'v_${source!.getKey()}_$key';
          cacheManager.putMemory(scopedKey, stringValue);
          unawaited(cacheManager.put(scopedKey, stringValue));
        }
      }
      return null;
    });
    runtime.onMessage('scopeGet', (args) {
      final key = _decodeSyncArgs(args).toString();
      if (ruleContext != null) {
        try {
          final value = ruleContext.get(key);
          if (value != null && value.toString().isNotEmpty) {
            return value.toString();
          }
        } catch (_) {}
      }
      if (source != null) {
        final scopedKey = 'v_${source!.getKey()}_$key';
        final cached = cacheManager.getFromMemory(scopedKey);
        if (cached != null && cached.toString().isNotEmpty) {
          return cached.toString();
        }
      }
      final value = JsExtensionsBase.sharedScope[key];
      return value == null ? '' : value.toString();
    });
    runtime.onMessage('ruleGetString', (args) {
      final rule = _decodeSyncArgs(args).toString();
      if (ruleContext != null) {
        try {
          return ruleContext.getString(rule);
        } catch (_) {}
      }
      return '';
    });
    runtime.onMessage('ruleGetStringList', (args) {
      final rule = _decodeSyncArgs(args).toString();
      if (ruleContext != null) {
        try {
          return ruleContext.getStringList(rule);
        } catch (_) {}
      }
      return const <String>[];
    });
    runtime.onMessage('ruleGetElement', (args) {
      final rule = _decodeSyncArgs(args).toString();
      if (ruleContext != null) {
        try {
          return _toJsRuleValue(ruleContext.getElement(rule));
        } catch (_) {}
      }
      return '';
    });
    runtime.onMessage('ruleGetElements', (args) {
      final rule = _decodeSyncArgs(args).toString();
      if (ruleContext != null) {
        try {
          final values = ruleContext.getElements(rule);
          return values.map(_toJsRuleValue).toList();
        } catch (_) {}
      }
      return const <dynamic>[];
    });
    runtime.onMessage('ruleSetContent', (args) {
      final payload = _decodeSyncArgs(args);
      if (payload is List && payload.isNotEmpty && ruleContext != null) {
        try {
          final nextBaseUrl =
              payload.length > 1 ? payload[1]?.toString() : null;
          ruleContext.setContent(payload[0], baseUrl: nextBaseUrl);
        } catch (_) {}
      }
      return null;
    });
    runtime.onMessage('log', (args) {
      debugPrint('JS_LOG: ${_compactJsBridgeLog(args)}');
      return _decodeSyncArgs(args);
    });
    runtime.onMessage('toast', (args) {
      debugPrint('JS_TOAST: ${_compactJsBridgeLog(args)}');
      return null;
    });
    runtime.onMessage('htmlSelectText', (args) {
      final payload = _decodeSyncArgs(args);
      if (payload is List && payload.length >= 2) {
        return _selectHtmlText(payload[0].toString(), payload[1].toString());
      }
      return '';
    });
    runtime.onMessage('htmlSelectHtml', (args) {
      final payload = _decodeSyncArgs(args);
      if (payload is List && payload.length >= 2) {
        return _selectHtmlHtml(payload[0].toString(), payload[1].toString());
      }
      return '';
    });
    runtime.onMessage('htmlSelectAttr', (args) {
      final payload = _decodeSyncArgs(args);
      if (payload is List && payload.length >= 3) {
        return _selectHtmlAttr(
          payload[0].toString(),
          payload[1].toString(),
          payload[2].toString(),
        );
      }
      return '';
    });
    runtime.onMessage('htmlSelectData', (args) {
      final payload = _decodeSyncArgs(args);
      if (payload is List && payload.length >= 2) {
        return _selectHtmlData(payload[0].toString(), payload[1].toString());
      }
      return '';
    });
    runtime.onMessage('htmlSelectAttributes', (args) {
      final payload = _decodeSyncArgs(args);
      if (payload is List && payload.length >= 2) {
        return _selectHtmlAttributes(
          payload[0].toString(),
          payload[1].toString(),
        );
      }
      return const <String>[];
    });
    runtime.onMessage('htmlSelectCount', (args) {
      final payload = _decodeSyncArgs(args);
      if (payload is List && payload.length >= 2) {
        return _selectHtmlElements(
          payload[0].toString(),
          payload[1].toString(),
        ).length;
      }
      return 0;
    });
    runtime.onMessage('htmlSelectTextList', (args) {
      final payload = _decodeSyncArgs(args);
      if (payload is List && payload.length >= 2) {
        return _selectHtmlElements(
          payload[0].toString(),
          payload[1].toString(),
        ).map((element) => element.text.trim()).toList();
      }
      return const <String>[];
    });
    runtime.onMessage('htmlRemove', (args) {
      final payload = _decodeSyncArgs(args);
      if (payload is List && payload.length >= 2) {
        return _removeHtml(payload[0].toString(), payload[1].toString());
      }
      return '';
    });
    runtime.onMessage('scopedObjectGetVariable', (args) {
      final payload = _decodeSyncArgs(args);
      if (payload is List && payload.length >= 2) {
        return _getScopedObjectVariable(
          payload[0].toString(),
          payload[1].toString(),
        );
      }
      return '';
    });
    runtime.onMessage('scopedObjectPutVariable', (args) {
      final payload = _decodeSyncArgs(args);
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
      final payload = _decodeSyncArgs(args);
      if (payload is List && payload.length >= 2) {
        return _getScopedObjectField(
          payload[0].toString(),
          payload[1].toString(),
        );
      }
      return null;
    });
    runtime.onMessage('scopedObjectSetField', (args) {
      final payload = _decodeSyncArgs(args);
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
        final saveTime =
            args.length > 2 ? int.tryParse(args[2].toString()) ?? 0 : 0;
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
        cacheManager.put('v_${source!.getKey()}_$key', value);
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
        final decoded = _decodeSyncArgs(args);
        source!.setVariableSync(decoded?.toString());
      }
      return null;
    });
    runtime.onMessage('sourceGetHeaderMap', (args) {
      if (source == null) return <String, String>{};
      final includeLoginHeader =
          _decodeSyncArgs(args) is bool ? _decodeSyncArgs(args) as bool : true;
      return source!.getHeaderMapSync(hasLoginHeader: includeLoginHeader);
    });

    // ─── Promise bridge: async with return value ────────────────
    runtime.onMessage('getCache', (args) {
      final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
      final key = parsed.payload.toString();
      cacheManager
          .get(key)
          .then((v) {
            resolveJsPending(parsed.callId, v);
          })
          .catchError((e) {
            rejectJsPending(parsed.callId, e);
          });
      return null;
    });

    runtime.onMessage('cacheTextFile', (args) {
      final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
      final payload = parsed.payload;
      final url =
          payload is List && payload.isNotEmpty
              ? payload[0].toString()
              : payload.toString();
      final saveTime =
          payload is List && payload.length > 1
              ? int.tryParse(payload[1].toString()) ?? 0
              : 0;
      cacheFile(url, saveTime)
          .then((content) {
            resolveJsPending(parsed.callId, content);
          })
          .catchError((e) {
            rejectJsPending(parsed.callId, e);
          });
      return null;
    });

    runtime.onMessage('importScript', (args) {
      final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
      final path = parsed.payload.toString();
      () async {
        try {
          if (path.startsWith('http')) {
            final content = await cacheFile(path, 0);
            if (content.trim().isEmpty) {
              throw Exception('$path 內容獲取失敗或者為空');
            }
            resolveJsPending(parsed.callId, _wrapImportedScript(content));
            return;
          }
          final file = File(path);
          if (!await file.exists()) {
            throw Exception('$path 內容獲取失敗或者為空');
          }
          final content = await file.readAsString();
          if (content.trim().isEmpty) {
            throw Exception('$path 內容獲取失敗或者為空');
          }
          resolveJsPending(parsed.callId, _wrapImportedScript(content));
        } catch (e) {
          rejectJsPending(parsed.callId, e);
        }
      }();
      return null;
    });

    runtime.onMessage('sourceGet', (args) {
      final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
      if (source == null) {
        resolveJsPending(parsed.callId, '');
        return null;
      }
      final key = parsed.payload.toString();
      cacheManager
          .get('v_${source!.getKey()}_$key')
          .then((v) {
            resolveJsPending(parsed.callId, v ?? '');
          })
          .catchError((e) {
            rejectJsPending(parsed.callId, e);
          });
      return null;
    });

    runtime.onMessage('sourceGetLoginInfo', (args) {
      final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
      if (source == null) {
        resolveJsPending(parsed.callId, '');
        return null;
      }
      source!
          .getLoginInfo()
          .then((v) {
            resolveJsPending(parsed.callId, v ?? '');
          })
          .catchError((e) {
            rejectJsPending(parsed.callId, e);
          });
      return null;
    });

    runtime.onMessage('sourceGetVariable', (args) {
      final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
      if (source == null) {
        resolveJsPending(parsed.callId, '');
        return null;
      }
      source!
          .getVariable()
          .then((v) {
            resolveJsPending(parsed.callId, v);
          })
          .catchError((e) {
            rejectJsPending(parsed.callId, e);
          });
      return null;
    });

    runtime.onMessage('cookieGet', (args) {
      final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
      final url = parsed.payload.toString();
      CookieStore()
          .getCookie(url)
          .then((v) {
            resolveJsPending(parsed.callId, v);
          })
          .catchError((e) {
            rejectJsPending(parsed.callId, e);
          });
      return null;
    });

    runtime.onMessage('allCookies', (args) {
      final parsed = JsExtensionsBase.parseAsyncCallArgs(args);
      // CookieStore 目前沒有 allCookies API，回傳空字串維持既有行為
      resolveJsPending(parsed.callId, '');
      return null;
    });

    // cacheFile 供 Dart 端內部使用 (例如 font cache)
    runtime.onMessage('cacheFile', (args) {
      // 歷史上是同步呼叫，但底層是 async HTTP。維持原行為：fire-and-forget
      // 並回傳空字串。若 rule JS 實際需要讀結果，應改用 java.get(...).body()。
      if (args is List && args.isNotEmpty) {
        cacheFile(args[0].toString(), args.length > 1 ? args[1] as int : 0);
      }
      return '';
    });
  }

  dynamic _decodeSyncArgs(dynamic args) {
    if (args is String) {
      try {
        return jsonDecode(args);
      } catch (_) {
        return args;
      }
    }
    return args;
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
    if (target is Book) {
      _setBookField(target, fieldName, value);
      return;
    }
    if (target is SearchBook) {
      _setSearchBookField(target, fieldName, value);
      return;
    }
    if (target is BookChapter) {
      _setChapterField(target, fieldName, value);
    }
  }

  void _setBookField(Book book, String fieldName, dynamic value) {
    switch (fieldName) {
      case 'bookUrl':
        book.bookUrl = _asString(value);
        return;
      case 'tocUrl':
        book.tocUrl = _asString(value);
        return;
      case 'origin':
        book.origin = _asString(value);
        return;
      case 'originName':
        book.originName = _asString(value);
        return;
      case 'name':
        book.name = _asString(value);
        return;
      case 'author':
        book.author = _asString(value);
        return;
      case 'kind':
        book.kind = _asNullableString(value);
        return;
      case 'coverUrl':
        book.coverUrl = _asNullableString(value);
        return;
      case 'intro':
        book.intro = _asNullableString(value);
        return;
      case 'latestChapterTitle':
        book.latestChapterTitle = _asNullableString(value);
        return;
      case 'wordCount':
        book.wordCount = _asNullableString(value);
        return;
      case 'type':
        book.type = _asInt(value, fallback: book.type);
        return;
      case 'chapterIndex':
        book.chapterIndex = _asInt(value, fallback: book.chapterIndex);
        return;
      case 'variable':
        book.variable = _asNullableString(value);
        return;
      case 'isInBookshelf':
        book.isInBookshelf = _asBool(value, fallback: book.isInBookshelf);
        return;
      case 'reverseToc':
        (book.readConfig ??= ReadConfig()).reverseToc = _asBool(
          value,
          fallback: book.readConfig?.reverseToc ?? false,
        );
        return;
      case 'useReplaceRule':
        (book.readConfig ??= ReadConfig()).useReplaceRule = _asBool(
          value,
          fallback: book.readConfig?.useReplaceRule ?? false,
        );
        return;
      default:
        return;
    }
  }

  void _setSearchBookField(SearchBook book, String fieldName, dynamic value) {
    switch (fieldName) {
      case 'bookUrl':
        book.bookUrl = _asString(value);
        return;
      case 'name':
        book.name = _asString(value);
        return;
      case 'author':
        book.author = _asNullableString(value);
        return;
      case 'kind':
        book.kind = _asNullableString(value);
        return;
      case 'coverUrl':
        book.coverUrl = _asNullableString(value);
        return;
      case 'intro':
        book.intro = _asNullableString(value);
        return;
      case 'wordCount':
        book.wordCount = _asNullableString(value);
        return;
      case 'latestChapterTitle':
        book.latestChapterTitle = _asNullableString(value);
        return;
      case 'origin':
        book.origin = _asString(value);
        return;
      case 'originName':
        book.originName = _asNullableString(value);
        return;
      case 'originOrder':
        book.originOrder = _asInt(value, fallback: book.originOrder);
        return;
      case 'type':
        book.type = _asInt(value, fallback: book.type);
        return;
      case 'variable':
        book.variable = _asNullableString(value);
        return;
      case 'tocUrl':
        book.tocUrl = _asNullableString(value);
        return;
      case 'respondTime':
        book.respondTime = _asInt(value, fallback: book.respondTime);
        return;
      default:
        return;
    }
  }

  void _setChapterField(BookChapter chapter, String fieldName, dynamic value) {
    switch (fieldName) {
      case 'url':
        chapter.url = _asString(value);
        return;
      case 'title':
        chapter.title = _asString(value);
        return;
      case 'baseUrl':
        chapter.baseUrl = _asString(value);
        return;
      case 'bookUrl':
        chapter.bookUrl = _asString(value);
        return;
      case 'index':
        chapter.index = _asInt(value, fallback: chapter.index);
        return;
      case 'isVolume':
        chapter.isVolume = _asBool(value, fallback: chapter.isVolume);
        return;
      case 'isVip':
        chapter.isVip = _asBool(value, fallback: chapter.isVip);
        return;
      case 'isPay':
        chapter.isPay = _asBool(value, fallback: chapter.isPay);
        return;
      case 'resourceUrl':
        chapter.resourceUrl = _asNullableString(value);
        return;
      case 'tag':
        chapter.tag = _asNullableString(value);
        return;
      case 'wordCount':
        chapter.wordCount = _asNullableString(value);
        return;
      case 'start':
        chapter.start = _asNullableInt(value);
        return;
      case 'end':
        chapter.end = _asNullableInt(value);
        return;
      case 'startFragmentId':
        chapter.startFragmentId = _asNullableString(value);
        return;
      case 'endFragmentId':
        chapter.endFragmentId = _asNullableString(value);
        return;
      case 'variable':
        chapter.variable = _asNullableString(value);
        return;
      case 'content':
        chapter.content = _asNullableString(value);
        return;
      default:
        return;
    }
  }

  String _asString(dynamic value) => value?.toString() ?? '';

  String? _asNullableString(dynamic value) => value?.toString();

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  int? _asNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  bool _asBool(dynamic value, {bool fallback = false}) {
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return fallback;
  }

  List<dom.Element> _selectHtmlElements(String html, String selector) {
    final doc = html_parser.parse(html);
    return _selectHtmlElementsFromDocument(doc, selector);
  }

  List<dom.Element> _selectHtmlElementsFromDocument(
    dom.Document document,
    String selector,
  ) {
    final normalizedSelector = _normalizeJsoupSelectorCompat(selector);
    try {
      return _selectHtmlElementsFromDocumentInternal(
        document,
        normalizedSelector,
      );
    } catch (_) {
      final compatFallback = _selectHtmlElementsWithCompatFallback(
        document,
        normalizedSelector,
      );
      if (compatFallback.isNotEmpty) {
        return compatFallback;
      }
      final pseudoFallback = _selectHtmlElementsWithPseudoFallback(
        document,
        normalizedSelector,
      );
      if (pseudoFallback.isNotEmpty) {
        return pseudoFallback;
      }
      final simplified = _simplifyUnsupportedSelector(normalizedSelector);
      if (simplified.isEmpty || simplified == normalizedSelector) {
        return const <dom.Element>[];
      }
      return _selectHtmlElementsFromDocumentInternal(document, simplified);
    }
  }

  List<dom.Element> _selectHtmlElementsWithCompatFallback(
    dom.Document document,
    String selector,
  ) {
    final root = document.documentElement;
    if (root == null) {
      return const <dom.Element>[];
    }
    try {
      return querySelectorAllCompat(root, selector);
    } catch (_) {
      return const <dom.Element>[];
    }
  }

  List<dom.Element> _selectHtmlElementsFromDocumentInternal(
    dom.Document document,
    String selector,
  ) {
    final eqMatch = RegExp(r'^(.*):eq\((-?\d+)\)\s*$').firstMatch(selector);
    if (eqMatch != null) {
      final baseSelector = eqMatch.group(1)!.trim();
      final index = int.tryParse(eqMatch.group(2)!) ?? 0;
      final items = document.querySelectorAll(baseSelector);
      if (items.isEmpty) return const <dom.Element>[];
      final resolvedIndex = index < 0 ? items.length + index : index;
      if (resolvedIndex < 0 || resolvedIndex >= items.length) {
        return const <dom.Element>[];
      }
      return <dom.Element>[items[resolvedIndex]];
    }
    return document.querySelectorAll(selector);
  }

  List<dom.Element> _selectHtmlElementsWithPseudoFallback(
    dom.Document document,
    String selector,
  ) {
    final selectors =
        selector
            .split(',')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty)
            .toList();
    final results = <dom.Element>[];
    final seen = <dom.Element>{};

    for (final part in selectors) {
      final matched = _selectHtmlElementsForSinglePseudoSelector(
        document,
        part,
      );
      for (final element in matched) {
        if (seen.add(element)) {
          results.add(element);
        }
      }
    }
    return results;
  }

  List<dom.Element> _selectHtmlElementsForSinglePseudoSelector(
    dom.Document document,
    String selector,
  ) {
    final nthChildMatch = RegExp(
      r'^(.*):nth-child\((\d+)\)\s*$',
    ).firstMatch(selector);
    if (nthChildMatch != null) {
      final baseSelector = nthChildMatch.group(1)!.trim();
      final targetIndex = int.parse(nthChildMatch.group(2)!);
      final candidates = document.querySelectorAll(baseSelector);
      return candidates.where((element) {
        final siblings = element.parent?.children ?? const <dom.Element>[];
        return siblings.indexOf(element) + 1 == targetIndex;
      }).toList();
    }

    final nthLastChildMatch = RegExp(
      r'^(.*):nth-last-child\((\d+)\)\s*$',
    ).firstMatch(selector);
    if (nthLastChildMatch != null) {
      final baseSelector = nthLastChildMatch.group(1)!.trim();
      final targetIndex = int.parse(nthLastChildMatch.group(2)!);
      final candidates = document.querySelectorAll(baseSelector);
      return candidates.where((element) {
        final siblings = element.parent?.children ?? const <dom.Element>[];
        final reverseIndex = siblings.length - siblings.indexOf(element);
        return reverseIndex == targetIndex;
      }).toList();
    }

    final firstChildMatch = RegExp(
      r'^(.*):first-child\s*$',
    ).firstMatch(selector);
    if (firstChildMatch != null) {
      final baseSelector = firstChildMatch.group(1)!.trim();
      final candidates = document.querySelectorAll(baseSelector);
      return candidates.where((element) {
        final siblings = element.parent?.children ?? const <dom.Element>[];
        return siblings.isNotEmpty && identical(siblings.first, element);
      }).toList();
    }

    final lastChildMatch = RegExp(r'^(.*):last-child\s*$').firstMatch(selector);
    if (lastChildMatch != null) {
      final baseSelector = lastChildMatch.group(1)!.trim();
      final candidates = document.querySelectorAll(baseSelector);
      return candidates.where((element) {
        final siblings = element.parent?.children ?? const <dom.Element>[];
        return siblings.isNotEmpty && identical(siblings.last, element);
      }).toList();
    }

    return const <dom.Element>[];
  }

  String _simplifyUnsupportedSelector(String selector) {
    return selector
        .replaceAll(RegExp(r':nth-last-child\([^)]*\)'), '')
        .replaceAll(RegExp(r':nth-child\([^)]*\)'), '')
        .replaceAll(RegExp(r':first-child\b'), '')
        .replaceAll(RegExp(r':last-child\b'), '')
        .replaceAll(RegExp(r':not\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'\s*,\s*'), ',')
        .trim();
  }

  String _normalizeJsoupSelectorCompat(String selector) {
    var normalized = selector.trim();
    if (normalized.isEmpty) {
      return normalized;
    }
    normalized = normalized.replaceAllMapped(
      RegExp(r'\[([^\]=~\^\$\*\|\s]+)~=(.+?)\]'),
      (match) {
        final attr = match.group(1)!.trim();
        final rawPattern = match.group(2)!.trim();
        final converted = _convertRegexAttributeSelector(rawPattern);
        return '[$attr$converted]';
      },
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r':matchesOwn\(([^()]*)\)'),
      (match) => _convertMatchesPseudo(
        rawPattern: match.group(1)!.trim(),
        pseudoName: ':containsOwn',
      ),
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r':matches\(([^()]*)\)'),
      (match) => _convertMatchesPseudo(
        rawPattern: match.group(1)!.trim(),
        pseudoName: ':contains',
      ),
    );
    normalized = normalized.replaceAllMapped(
      RegExp(r':has\(\s*>\s*'),
      (_) => ':has(',
    );
    return normalized;
  }

  String _convertRegexAttributeSelector(String rawPattern) {
    final trimmed = _stripSelectorQuotes(rawPattern).trim();
    if (trimmed.isEmpty ||
        trimmed == r'\S' ||
        trimmed == r'\\S' ||
        trimmed == '.+' ||
        trimmed == '.*') {
      return '';
    }

    final normalized = trimmed.replaceAll(r'\\', r'\');
    final literal = _tryExtractAnchoredLiteral(normalized);
    if (literal != null) {
      return '="$literal"';
    }

    final startsWithLiteral = _tryExtractPrefixLiteral(normalized);
    if (startsWithLiteral != null) {
      return '^="$startsWithLiteral"';
    }

    final endsWithLiteral = _tryExtractSuffixLiteral(normalized);
    if (endsWithLiteral != null) {
      return '\$="$endsWithLiteral"';
    }

    final plainLiteral = _tryExtractPlainLiteral(normalized);
    if (plainLiteral != null) {
      return '*="$plainLiteral"';
    }

    return '';
  }

  String _convertMatchesPseudo({
    required String rawPattern,
    required String pseudoName,
  }) {
    final normalized = _stripSelectorQuotes(rawPattern).replaceAll(r'\\', r'\');
    if (normalized.isEmpty ||
        normalized == r'\S' ||
        normalized == r'\\S' ||
        normalized == '^\\S' ||
        normalized == r'^\S' ||
        normalized == '.+' ||
        normalized == '.*') {
      return '';
    }

    final literal =
        _tryExtractAnchoredLiteral(normalized) ??
        _tryExtractPlainLiteral(normalized);
    if (literal == null || literal.isEmpty) {
      return '';
    }
    final escaped = literal.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '$pseudoName("$escaped")';
  }

  String _stripSelectorQuotes(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2 &&
        ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
            (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  String? _tryExtractAnchoredLiteral(String pattern) {
    final match = RegExp(
      r'^\^((?:\\.|[^\\^$.*+?()[\]{}|])+)\$$',
    ).firstMatch(pattern);
    return match == null ? null : _unescapeSelectorLiteral(match.group(1)!);
  }

  String? _tryExtractPrefixLiteral(String pattern) {
    final match = RegExp(
      r'^\^((?:\\.|[^\\^$.*+?()[\]{}|])+)$',
    ).firstMatch(pattern);
    return match == null ? null : _unescapeSelectorLiteral(match.group(1)!);
  }

  String? _tryExtractSuffixLiteral(String pattern) {
    final match = RegExp(
      r'^((?:\\.|[^\\^$.*+?()[\]{}|])+)\$$',
    ).firstMatch(pattern);
    return match == null ? null : _unescapeSelectorLiteral(match.group(1)!);
  }

  String? _tryExtractPlainLiteral(String pattern) {
    if (RegExp(r'[\\^$.*+?()[\]{}|]').hasMatch(pattern)) {
      return null;
    }
    return pattern;
  }

  String _unescapeSelectorLiteral(String value) {
    return value.replaceAllMapped(RegExp(r'\\(.)'), (match) => match.group(1)!);
  }

  String _selectHtmlText(String html, String selector) {
    final elements = _selectHtmlElements(html, selector);
    return elements
        .map((element) => element.text.trim())
        .where((text) => text.isNotEmpty)
        .join(' ');
  }

  String _selectHtmlHtml(String html, String selector) {
    final elements = _selectHtmlElements(html, selector);
    return elements.map((element) => element.outerHtml).join();
  }

  String _selectHtmlAttr(String html, String selector, String attr) {
    final elements = _selectHtmlElements(html, selector);
    for (final element in elements) {
      final value = element.attributes[attr]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  String _selectHtmlData(String html, String selector) {
    if (selector == 'html') {
      final document = html_parser.parse(html);
      final contentElements =
          document
              .querySelectorAll('*')
              .where(
                (element) =>
                    element.localName != 'html' &&
                    element.localName != 'head' &&
                    element.localName != 'body',
              )
              .toList();
      if (contentElements.length == 1) {
        return contentElements.first.innerHtml;
      }
    }
    final elements = _selectHtmlElements(html, selector);
    return elements.map((element) => element.innerHtml).join();
  }

  List<String> _selectHtmlAttributes(String html, String selector) {
    final elements = _selectHtmlElements(html, selector);
    if (elements.isEmpty) {
      return const <String>[];
    }
    return elements.first.attributes.entries
        .map((entry) => '${entry.key}="${entry.value}"')
        .toList();
  }

  String _removeHtml(String html, String selector) {
    final document = html_parser.parse(html);
    final targets = _selectHtmlElementsFromDocument(document, selector);
    if (targets.isEmpty) {
      return html;
    }

    for (final target in targets) {
      target.remove();
    }

    if (html.contains('<html') || html.contains('<!DOCTYPE')) {
      return document.outerHtml;
    }
    return document.body?.innerHtml ?? html;
  }

  /// 下載到快取資料夾並回傳內容；目前僅 Dart 內部呼叫 (非 JS 路徑)
  Future<String> cacheFile(String url, int saveTime) async {
    final key = JsEncodeUtils.md5Encode16(url);
    final cached = await cacheManager.get(key);
    if (cached != null) return cached;
    try {
      final response = await HttpClient().client.get(url);
      final content = response.data.toString();
      if (content.isNotEmpty) await cacheManager.put(key, content);
      return content;
    } catch (_) {
      return '';
    }
  }

  dynamic _toJsRuleValue(dynamic value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
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

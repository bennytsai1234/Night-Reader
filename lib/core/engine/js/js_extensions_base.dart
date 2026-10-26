import 'dart:typed_data';

import 'package:flutter_js/flutter_js.dart';
import 'package:night_reader/core/models/base_source.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/cache_manager.dart';

import 'jsoup/jsoup_bridge.dart';
import 'query_ttf.dart';

/// JsExtensions 的基礎狀態與共用緩存。
///
/// 規則 JS 呼叫 Dart 一律同步拿到結果：要等的（網路、資料庫裡的快取、
/// Cookie）由 [onBlocking] 註冊，在書源 isolate 停住等（[BlockingCall]，
/// ADR 0034）。
abstract class JsExtensionsBase {
  final JavascriptRuntime runtime;
  final BaseSource? source;

  /// 規則 JS 裡 `java` 代表的 AnalyzeRule；共用引擎時由 [JsEngine] 每次執行前
  /// 換成當下的規則。
  dynamic ruleContext;
  final CookieStore cookieStore = CookieStore();
  final CacheManager cacheManager = CacheManager();

  /// 交給規則 JS 的 Jsoup 節點（[JsoupBridge]）。
  final JsoupBridge jsoup = JsoupBridge();

  static final Map<String, QueryTTF> ttfCache = {};
  static final Map<String, String> fontReplaceCache = {};

  /// 全域 JS 作用域 (原 Android SharedJsScope)
  static final Map<String, dynamic> sharedScope = {};

  /// 清除 session 級別的靜態快取，在批次校驗結束後呼叫以釋放記憶體。
  ///
  /// ttfCache 存放字型二進位（數百 KB/個），sharedScope 持續累積書源寫入的
  /// JS 變數，兩者在長時間校驗後會佔用大量記憶體。
  static void clearCaches() {
    ttfCache.clear();
    fontReplaceCache.clear();
    sharedScope.clear();
  }

  JsExtensionsBase(this.runtime, {this.source, this.ruleContext});

  /// 安裝 JS 端的 `__lrWait`：[onBlocking] 註冊的呼叫經由它拿結果。
  void installBlockingCalls() {
    runtime.evaluate(r'''
      // 要等的呼叫：Dart 那邊停住書源 isolate 等到結果（ADR 0034），回傳
      // {value} 或 {error}。錯誤不直接丟過 FFI 的橋，JavaScriptCore 接不住。
      function __lrWait(channel, payload) {
        var reply = sendMessage(channel, JSON.stringify(payload));
        if (reply == null) return null;
        if (reply.error !== undefined && reply.error !== null) {
          throw new Error(String(reply.error));
        }
        return reply.value === undefined ? null : reply.value;
      }
    ''');
  }

  /// 註冊規則 JS 經 `__lrWait(channel, payload)` 呼叫的 [handler]。它同步做
  /// 完，要等的部分交給 [BlockingCall]；結果包成 `{value}`、丟出的錯誤包成
  /// `{error}`。位元組照 JS 陣列傳回，和 Legado 的 Java byte[] 一樣能逐一讀取。
  void onBlocking(String channel, Object? Function(dynamic payload) handler) {
    runtime.onMessage(channel, (dynamic payload) {
      try {
        final value = handler(payload);
        return {'value': value is Uint8List ? List<int>.of(value) : value};
      } catch (error) {
        return {'error': '$error'};
      }
    });
  }

  void dispose() {
    jsoup.clear();
  }
}

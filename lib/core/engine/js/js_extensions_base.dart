import 'dart:async';
import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:reader/core/models/base_source.dart';
import 'package:reader/core/services/cookie_store.dart';
import 'package:reader/core/services/cache_manager.dart';
import 'package:reader/core/services/app_log_service.dart';
import 'query_ttf.dart';

/// JsExtensions 的基礎狀態與共用緩存
///
/// 同時負責 **Dart ↔ JS Promise bridge** 的基礎設施：
///
/// 1. **async java/cache/source/cookie 方法** — JS 端呼叫時會經由 `__asyncCall(channel, [id, payload])`
///    注冊一個 pending Promise；Dart 端 handler 完成 async 工作後透過
///    [resolveJsPending] / [rejectJsPending] 跨越 flutter_js 的同步 onMessage 限制
///    重新進入 JS runloop 來 resolve 該 Promise。
///
/// 2. **rule-level 整段 JS 執行** — `AnalyzeRule.evalJSAsync` 會把使用者 JS
///    包在 async IIFE 內並以唯一 ruleCallId 註冊 [registerRuleCall]，最終 JS 會
///    `sendMessage('__ruleDone', [id, value, error])` 通知 Dart 側 [_pendingRuleCalls]
///    中對應的 Completer 完成。
abstract class JsExtensionsBase {
  final JavascriptRuntime runtime;
  final BaseSource? source;
  final dynamic ruleContext;
  final CookieStore cookieStore = CookieStore();
  final CacheManager cacheManager = CacheManager();

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

  // ─── Promise bridge state ───────────────────────────────────────────
  /// 下一個 rule-level 執行的 id
  int _nextRuleCallId = 0;

  /// rule-level JS 執行的 pending Completer，鍵為 ruleCallId
  final Map<int, Completer<dynamic>> _pendingRuleCalls = {};

  /// bridge 是否已經初始化 (防重複 inject)
  bool _bridgeInitialised = false;

  JsExtensionsBase(this.runtime, {this.source, this.ruleContext});

  /// 安裝 Dart↔JS Promise bridge 的 JS 端基礎設施與對應 onMessage handler
  ///
  /// 必須在任何一個會用到 `__asyncCall` 的 extension 之前呼叫。
  /// JsExtensions.inject() 會負責調用此方法。
  void setupPromiseBridge() {
    if (_bridgeInitialised) return;
    _bridgeInitialised = true;

    runtime.evaluate(r'''
      var __lr = __lr || {};
      __lr.nextAsyncId = 0;
      __lr.pendingResolvers = {};
      __lr.pendingRejecters = {};

      // JS 側 async 呼叫入口：分配 id、註冊 resolver/rejecter、同步
      // sendMessage 到 Dart。Dart handler 處理完 async 工作後，會從外部
      // 呼叫 __resolvePending / __rejectPending 完成該 Promise。
      function __asyncCall(channel, payload) {
        var id = ++__lr.nextAsyncId;
        return new Promise(function(resolve, reject) {
          __lr.pendingResolvers[id] = resolve;
          __lr.pendingRejecters[id] = reject;
          sendMessage(channel, JSON.stringify([id, payload]));
        });
      }

      function __resolvePending(id, value) {
        var r = __lr.pendingResolvers[id];
        delete __lr.pendingResolvers[id];
        delete __lr.pendingRejecters[id];
        if (r) r(value);
      }

      function __rejectPending(id, errMsg) {
        var r = __lr.pendingRejecters[id];
        delete __lr.pendingResolvers[id];
        delete __lr.pendingRejecters[id];
        if (r) r(new Error(errMsg == null ? 'unknown error' : String(errMsg)));
      }
    ''');

    // rule-level 完成通知：args = [ruleCallId, resultJson, errorMsg]
    runtime.onMessage('__ruleDone', (dynamic args) {
      try {
        final list = args is List ? args : jsonDecode(args.toString()) as List;
        final id = (list[0] as num).toInt();
        final value = list[1];
        final err = list.length > 2 ? list[2] : null;
        final completer = _pendingRuleCalls.remove(id);
        if (completer == null || completer.isCompleted) return null;
        if (err != null && err != '') {
          completer.completeError(_RuleJsError(err.toString()));
        } else {
          completer.complete(value);
        }
      } catch (e) {
        AppLog.e('__ruleDone handler error: $e');
      }
      return null;
    });
  }

  /// 註冊一個 rule-level JS 執行，回傳唯一 id 與綁定的 Completer
  ///
  /// 呼叫端應在 `runtime.evaluate(...)` 包好的 async IIFE 之前取得 id，
  /// 然後 await 回傳的 future。Completer 會在 JS 端 `sendMessage('__ruleDone', ...)`
  /// 觸發時完成。
  (int, Future<dynamic>) registerRuleCall() {
    final id = _nextRuleCallId++;
    final completer = Completer<dynamic>();
    _pendingRuleCalls[id] = completer;
    return (id, completer.future);
  }

  /// 主動清除一個 pending rule call（timeout 或 abort 時使用）
  void cancelRuleCall(int id, Object error) {
    final c = _pendingRuleCalls.remove(id);
    if (c != null && !c.isCompleted) {
      c.completeError(error);
    }
  }

  /// 從 Dart 主動 resolve 一個 JS 側 pending Promise
  ///
  /// [callId] 是 JS 側 `__asyncCall` 分配並透過 sendMessage payload 第 0 欄
  /// 傳來的 id（儲存於 `__lr.pendingResolvers[id]`）。
  /// [value] 必須是 JSON-safe 的 Dart 物件（string / num / bool / List / Map / null）。
  ///
  /// 呼叫本方法後會立刻 pump QuickJS microtask queue，讓等待中的 await
  /// 繼續往下執行。
  void resolveJsPending(int callId, dynamic value) {
    final payload = _safeJsonEncode(value);
    runtime.evaluate('__resolvePending($callId, $payload);');
    runtime.executePendingJob();
  }

  /// 從 Dart 主動 reject 一個 JS 側 pending Promise
  void rejectJsPending(int callId, Object error) {
    final msg = _safeJsonEncode(error.toString());
    runtime.evaluate('__rejectPending($callId, $msg);');
    runtime.executePendingJob();
  }

  /// 從 onMessage handler 收到的 args 中解析出 `[callId, payload]`
  ///
  /// 便於各個 extension handler 統一從 `[id, ...]` 格式提取 id 與實際參數。
  static ({int callId, dynamic payload}) parseAsyncCallArgs(dynamic args) {
    if (args is List && args.length >= 2) {
      final id = (args[0] as num).toInt();
      return (callId: id, payload: args[1]);
    }
    throw ArgumentError('async call args malformed: $args');
  }

  /// JSON-encode 並保證不會炸掉：若值無法序列化則退化為 toString
  static String _safeJsonEncode(dynamic value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return jsonEncode(value.toString());
    }
  }
}

/// 由 rule-level JS 執行拋出的錯誤包裝
class _RuleJsError implements Exception {
  _RuleJsError(this.message);
  final String message;
  @override
  String toString() => 'RuleJsError: $message';
}

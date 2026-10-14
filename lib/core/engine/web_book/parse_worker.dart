import 'dart:async';
import 'dart:isolate';

import 'package:night_reader/core/engine/js/js_bridge_guard.dart';
import 'package:night_reader/core/engine/js/js_engine.dart';
import 'package:night_reader/core/models/base_source.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/source_validation_context.dart';

/// 一組規則能不能交給 [ParseWorker]，以及需不需要 JS 引擎。
enum ParseWorkerFit {
  /// 留在原地解析。
  none,

  /// 不帶 JS 與變數存取。
  pure,

  /// 帶 JS，但 JS 只做字串、編碼、加解密與取規則結果這類計算。
  js,
}

/// 把書源頁面的解析交給一個常駐的背景 isolate，主 isolate 只收結果。
///
/// 收兩種解析（[fit]）：
/// - 規則不帶 JS：只讀傳進去的 HTML 與書源。
/// - 規則帶 JS，但 JS 用不到網路、Cookie、快取、書源變數、WebView 與繁簡
///   字典：背景 isolate 也有自己的 QuickJS，這類 JS 在哪裡跑結果都一樣。
///   搜尋時上百個書源的結果多半靠這類 JS 整理，原地跑會讓畫面一直掉幀。
/// 其他帶 JS 的規則會經由 `java.*` 用到主 isolate 的網路、資料庫與 Cookie，
/// 維持原地解析（docs/research/source-engine-off-main-isolate.md）。
///
/// 只在 App 的主 isolate 開啟（`main.dart`）；測試、書源校驗這類已經在背景
/// 的 isolate 維持原地解析，不再多開一層。
abstract final class ParseWorker {
  static bool enabled = false;

  static Future<SendPort>? _port;

  static final RegExp _js = RegExp(
    r'@js:|<js>|\{\{|java\.',
    caseSensitive: false,
  );

  static final RegExp _variables = RegExp(r'@put|@get', caseSensitive: false);

  /// 一看就知道背景 isolate 給不了正確結果的寫法：會用到主 isolate 狀態的
  /// `java.*`（網路、檔案、WebView、紀錄、快取、Cookie、字型、繁簡字典）、
  /// `cookie`／`cache`／`source` 物件、改動 `book`／`chapter`（背景改到的是
  /// 複本，改動會遺失），以及瀏覽器的網路 API。這只是先篩掉明顯不行的，省一
  /// 趟來回；別的寫法（中括號、別名）由背景 isolate 的 [JsBridgeGuard] 在
  /// 執行時擋下，任務改回原地。
  static final RegExp _workerUnsafe = RegExp(
    r'java\s*\.\s*(ajax|ajaxAll|cacheFile|connect|get|post|head|webView\w*|'
    r'startBrowser\w*|getVerificationCode|downloadFile|importScript|'
    r'readFile|readTxtFile|getZipByteArrayContent|unArchiveFile|'
    r'getTxtInFolder|log|toast|put|queryTTF|replaceFont|getCookie|setCookie|'
    r't2s|s2t)\s*\(|'
    r'\b(cookie|cache|source)\s*\.|'
    r'\b(book|chapter)\s*\.\s*(put|set)\w*\s*\(|'
    r'\b(book|chapter)\s*\.\s*\w+\s*=(?!=)|'
    r'fetch\s*\(|XMLHttpRequest',
    caseSensitive: false,
  );

  /// [source] 的這組 [rules] 交給背景 isolate 的方式。書源的 jsLib 會載進
  /// 每個 JS 引擎，所以也要符合條件；以 JSON 列出外部網址的 jsLib 要抓網路，
  /// 不交出去。
  ///
  /// `@put`／`@get` 寫讀的是當下的書、章節或規則自己的暫存；只有這些都跟著
  /// 結果傳回時（[variablesInResult]，例如搜尋列表的每一筆）才交出去，否則
  /// 背景寫進的值會遺失。
  static ParseWorkerFit fit(
    BaseSource source,
    Iterable<String?> rules, {
    bool variablesInResult = false,
  }) {
    final present = rules.whereType<String>().toList();
    if (!variablesInResult && present.any(_variables.hasMatch)) {
      return ParseWorkerFit.none;
    }
    if (present.every((rule) => !_js.hasMatch(rule))) {
      return ParseWorkerFit.pure;
    }
    if (present.any(_workerUnsafe.hasMatch)) return ParseWorkerFit.none;
    final jsLib = source.jsLib?.trim() ?? '';
    if (jsLib.startsWith('{') || _workerUnsafe.hasMatch(jsLib)) {
      return ParseWorkerFit.none;
    }
    return ParseWorkerFit.js;
  }

  /// 在背景 isolate 執行 [task] 並回傳結果；沒開啟、送不出去、執行失敗、
  /// 背景的 JS 引擎不能用（[usesJs]）、JS 呼叫了被 [JsBridgeGuard] 擋下的
  /// 頻道或逾時都回傳 null，由呼叫端改在原地
  /// 解析（失敗時原地再跑一次，例外照原樣丟出）。
  ///
  /// [task] 連同它捕捉的變數會複製到背景 isolate，所以要在只捕捉書源、書籍與
  /// 字串的地方建立，不能捕捉回呼或資料庫連線。
  static Future<R?> run<R extends Object>(
    Future<R> Function() task, {
    bool usesJs = false,
  }) async {
    if (!enabled) return null;
    final reply = ReceivePort();
    try {
      final port = await (_port ??= _spawn());
      port.send((task, usesJs, reply.sendPort));
      // 規則 JS 自己有 20 秒逾時；超過這個時間還沒回覆，表示背景 isolate
      // 卡住了，改回原地解析。
      final (ok, value) = await reply.first.timeout(
        const Duration(seconds: 30),
      ) as (bool, Object?);
      if (ok) return value as R;
      AppLog.w('ParseWorker task failed, parsing in place: $value');
    } catch (e) {
      AppLog.w('ParseWorker unavailable, parsing in place: $e');
    } finally {
      reply.close();
    }
    return null;
  }

  static Future<SendPort> _spawn() async {
    final ready = ReceivePort();
    try {
      await Isolate.spawn(
        _main,
        ready.sendPort,
        debugName: 'ParseWorker',
        // 規則 JS 留下的非同步錯誤不能讓整個背景 isolate 結束，否則之後
        // 的解析都等不到回覆。
        errorsAreFatal: false,
      );
      return await ready.first as SendPort;
    } catch (_) {
      // 開不起來就整段改回原地解析，不在每次解析時重試。
      enabled = false;
      _port = null;
      rethrow;
    } finally {
      ready.close();
    }
  }

  static void _main(SendPort ready) {
    JsBridgeGuard.restricted = true;
    final requests = ReceivePort();
    ready.send(requests.sendPort);
    requests.listen((message) async {
      final (task, usesJs, reply) =
          message as (Future<Object> Function(), bool, SendPort);
      try {
        if (usesJs && !await _jsUsable()) {
          reply.send((false, 'JS engine unavailable in ParseWorker'));
          return;
        }
        final blockedBefore = JsBridgeGuard.blockedCalls;
        // 非互動模式：JS 引擎不載入瀏覽器的 fetch／XHR（背景 isolate 拿不到
        // rootBundle），也不會開瀏覽器或驗證流程。
        final result = await SourceValidationContext.runNonInteractive(task);
        // JS 碰到只有主 isolate 才有的東西：這個結果不可信，改回原地。同時
        // 在跑的其他任務也會因此改回原地，只是多解析一次。
        if (JsBridgeGuard.blockedCalls != blockedBefore) {
          reply.send((false, 'JS used a bridge only the main isolate has'));
          return;
        }
        reply.send((true, result));
      } catch (e, stack) {
        reply.send((false, '$e\n$stack'));
      }
    });
  }

  static bool? _jsWorks;

  /// 背景 isolate 的 JS 引擎能不能用。引擎建不起來時 [JsEngine] 會改用
  /// 模擬結果，背景解析就會默默給出錯的值，所以先確認一次。
  static Future<bool> _jsUsable() async {
    final known = _jsWorks;
    if (known != null) return known;
    final works = await SourceValidationContext.runNonInteractive(() async {
      final engine = JsEngine();
      try {
        return engine.isAvailable && '${engine.evaluate('1 + 1')}' == '2';
      } catch (_) {
        return false;
      } finally {
        engine.dispose();
      }
    });
    return _jsWorks = works;
  }
}

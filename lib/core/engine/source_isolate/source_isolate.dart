import 'dart:async';
import 'dart:isolate';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:drift/isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart' show fetchPolyfillSource;
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/web_book/headless_webview_service.dart';
import 'package:night_reader/core/network/cloudflare.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/backstage_webview.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/services/rate_limiter.dart';

import 'isolate_channel.dart';

/// 書源 isolate：常駐的背景 isolate，書源的抓取與解析（含規則 JS）在這裡
/// 跑，主 isolate 只收結果，畫面不會被解析卡住（ADR 0028）。它是一個
/// [SourceWorker]。
abstract final class SourceIsolate {
  /// 只在 App 的主 isolate 開（`main.dart`）。測試與 Workmanager 不開，
  /// [run] 原地執行。
  static bool enabled = false;

  static Future<SourceWorker?>? _worker;

  /// 開始開書源 isolate（[enabled] 時），不等它開好，[run] 會等。開不起來
  /// 時記下原因，書源工作改回主 isolate 執行。[database] 預設為主 isolate
  /// 的資料庫。
  static void start({Future<DriftIsolate>? database}) {
    if (!enabled || _worker != null) return;
    _worker =
        SourceWorker.spawn(
          debugName: 'SourceIsolate',
          withDictionaries: true,
          database: database,
        ).then<SourceWorker?>(
          (worker) => worker,
          onError: (Object error, StackTrace stackTrace) {
            AppLog.e(
              '書源 isolate 開不起來，書源工作改在主 isolate 執行: $error',
              error: error,
              stackTrace: stackTrace,
            );
            return null;
          },
        );
  }

  /// 在書源 isolate 執行 [task] 並傳回結果；沒開時原地執行。[task] 拿到的
  /// [CancelToken] 屬於執行它的 isolate，[cancelToken] 取消時跟著取消。
  /// 錯誤照原樣丟出（送不回來時見 [IsolateTaskError]）。
  ///
  /// [task] 連同它捕捉的變數會複製到書源 isolate，要在只捕捉書源、書籍與
  /// 字串這類資料的地方建立（例如頂層函式），不能捕捉頁面、回呼或資料庫
  /// 連線。
  static Future<R> run<R>(
    Future<R> Function(CancelToken cancelToken) task, {
    CancelToken? cancelToken,
  }) async {
    final worker = await _worker;
    if (worker == null) {
      // 測試多半不開書源 isolate；照樣試送一次，捕捉了送不出去的東西時
      // 在測試裡就失敗，不等到 App 裡才改回主 isolate。
      assert(_sendable(task));
      return _runCancellable(task, cancelToken);
    }
    try {
      return await worker.run(task, cancelToken: cancelToken);
    } on _TaskNotSendable catch (e) {
      assert(_sendable(task));
      AppLog.e('書源工作送不進書源 isolate，改在主 isolate 執行: ${e.error}', error: e.error);
      return _runCancellable(task, cancelToken);
    }
  }

  /// 測試用：結束書源 isolate，回到原地執行。
  @visibleForTesting
  static Future<void> stop() async {
    final worker = await _worker;
    worker?.kill(StateError('書源 isolate 已結束'));
    _worker = null;
  }
}

/// 送一次 [task] 給自己，看它連同捕捉的變數能不能跨 isolate；不能時丟出
/// 錯誤，指出要改在只捕捉資料的頂層函式裡建立（`CODING_STANDARDS.md`）。
bool _sendable(Object task) {
  final port = RawReceivePort();
  try {
    port.sendPort.send(task);
    return true;
  } on ArgumentError catch (e) {
    throw ArgumentError(
      '送進書源 isolate 的工作捕捉了不能跨 isolate 的東西，要在只捕捉資料的'
      '頂層函式裡建立（CODING_STANDARDS.md 背景執行）：$e',
    );
  } finally {
    port.close();
  }
}

/// 執行書源工作的背景 isolate。主 isolate 替它做只有主 isolate 能做的事：
///
/// - 資料庫：兩邊連到同一個 drift isolate（[AppDatabase.sharedIsolate]）。
/// - Cookie 檔與書源限流：在主 isolate；這裡的請求經由 [_MainCookieJar]、
///   [_MainRateLimits] 交給主 isolate。worker 可能被一段同步的規則 JS 佔住
///   好幾秒，擁有者放在這裡的話，主 isolate 上的請求都得等它。
/// - WebView（渲染網頁、通過 Cloudflare 檢查）：平台訊息只送到主
///   isolate，交給主 isolate。
/// - 紀錄與提示：送回主 isolate（[AppLog.delegate]），未接住的錯誤寫進
///   主 isolate 的錯誤紀錄。
/// - 快取與 Cookie 的記憶體層：每個 isolate 各一份，寫入轉送給其他所有
///   isolate。
///
/// 書源 isolate 是一個常駐的 worker；書源校驗每個書源開一個，逾時就直接
/// 結束它，卡住的同步規則 JS 也停得下來。
final class SourceWorker {
  SourceWorker._(this._isolate, this._channel, this._inbox, this._errors);

  final Isolate _isolate;
  final IsolateChannel _channel;
  final ReceivePort _inbox;
  final ReceivePort _errors;
  int _nextTaskId = 0;
  bool _killed = false;

  /// 活著的 worker；主 isolate 的記憶體寫入轉送給它們。
  static final Set<SourceWorker> _live = {};

  /// worker 借走、還沒交回的限流紀錄。
  static final Map<int, ConcurrentRecord?> _rateTickets = {};
  static int _nextRateTicket = 0;

  /// 開一個 worker，等它連上資料庫、網路設定好才傳回。[withDictionaries]
  /// 為 false 時不載入繁簡字典（校驗用，省下每個書源解析一次字典），
  /// `java.t2s` 這類轉換原樣返回。
  static Future<SourceWorker> spawn({
    required String debugName,
    required bool withDictionaries,
    Future<DriftIsolate>? database,
  }) async {
    final inbox = ReceivePort('$debugName main');
    final errors = ReceivePort('$debugName errors');
    errors.listen(_recordUncaughtError);
    final remote = Completer<SendPort>();
    IsolateChannel? channel;
    inbox.listen((message) {
      if (!remote.isCompleted) {
        remote.complete(message as SendPort);
        return;
      }
      channel?.receive(message);
    });
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _main,
        inbox.sendPort,
        debugName: debugName,
        // 規則 JS 留下的非同步錯誤不能讓 worker 結束，否則之後的書源工作
        // 都等不到回覆。
        errorsAreFatal: false,
        onError: errors.sendPort,
      );
    } catch (_) {
      inbox.close();
      errors.close();
      rethrow;
    }
    late final SourceWorker worker;
    channel = IsolateChannel(
      await remote.future,
      onRequest: _answerWorker,
      onNotice: (notice) => _onWorkerNotice(worker, notice),
    );
    worker = SourceWorker._(isolate, channel, inbox, errors);
    _live.add(worker);
    _installMainMirrors();
    try {
      await channel.request(
        _Initialize(
          databasePort:
              (await (database ?? AppDatabase.sharedIsolate)).connectPort,
          rootToken: RootIsolateToken.instance,
          dictionaries: withDictionaries ? await _dictionaries() : null,
          fetchPolyfill: await _fetchPolyfill(),
          webViewUserAgent: WebViewUserAgent.value,
        ),
      );
    } catch (_) {
      worker.kill(StateError('$debugName 開不起來'));
      rethrow;
    }
    return worker;
  }

  /// 在 worker 執行 [task] 並傳回結果。[task] 拿到的 [CancelToken] 屬於
  /// worker，[cancelToken] 取消時跟著取消。
  Future<R> run<R>(
    Future<R> Function(CancelToken cancelToken) task, {
    CancelToken? cancelToken,
  }) async {
    final id = _nextTaskId++;
    final Future<Object?> result;
    try {
      result = _channel.request(_RunTask(id, task));
    } on ArgumentError catch (e) {
      throw _TaskNotSendable(e);
    }
    unawaited(
      cancelToken?.whenCancel.then((_) {
        if (!_killed) _channel.notify(_CancelTask(id));
      }),
    );
    return await result as R;
  }

  /// 立刻結束 worker；還在等的工作以 [error] 結束。
  void kill(Object error) {
    if (_killed) return;
    _killed = true;
    _live.remove(this);
    if (_live.isEmpty) _uninstallMainMirrors();
    _channel.close(error);
    _isolate.kill(priority: Isolate.immediate);
    _inbox.close();
    _errors.close();
  }

  // ── 主 isolate 一次讀好、給每個 worker 的資源 ──────────────────────

  static Future<List<String>?>? _dictionariesFuture;
  static Future<String?>? _fetchPolyfillFuture;

  static Future<List<String>?> _dictionaries() =>
      _dictionariesFuture ??= _loadOrNull(
        () => Future.wait(
          ChineseUtils.dictionaryAssetPaths.map(rootBundle.loadString),
        ),
      );

  static Future<String?> _fetchPolyfill() =>
      _fetchPolyfillFuture ??= _loadOrNull(
        () => rootBundle.loadString('packages/flutter_js/assets/js/fetch.js'),
      );

  /// 讀不到（例如測試沒有這個資源）時給 null：繁簡轉換原樣返回、規則的
  /// fetch 不能用，其他照常。
  static Future<T?> _loadOrNull<T>(Future<T> Function() load) async {
    try {
      return await load();
    } catch (e) {
      AppLog.w('書源 worker 的資源讀不到: $e');
      return null;
    }
  }

  static void _recordUncaughtError(Object? message) {
    if (message is! List || message.isEmpty) return;
    final error = '${message[0]}';
    final stack = message.length > 1 ? message[1]?.toString() : null;
    final stackTrace = stack == null || stack.isEmpty
        ? null
        : StackTrace.fromString(stack);
    AppLog.e('書源 isolate 未處理的錯誤: $error', stackTrace: stackTrace);
    CrashHandler.recordError('書源 isolate: $error', stackTrace);
  }

  // ── 主 isolate 替 worker 做的事 ────────────────────────────────────

  static Future<Object?> _answerWorker(Object request) async {
    switch (request) {
      case final _RenderHtml render:
        return HeadlessWebViewService().getRenderedHtml(
          url: render.url,
          headers: render.headers,
          userAgent: render.userAgent,
          js: render.js,
          delayTime: render.delayTime,
        );
      case final BackstageWebView webView:
        return webView.getStrResponse();
      case _Clearance(:final uri):
        return CloudflareClearance.clear(uri);
      case _CookieJarLoad(:final uri):
        return NetworkService().cookieJar.loadForRequest(uri);
      case _CookieJarSave(:final uri, :final cookies):
        await NetworkService().cookieJar.saveFromResponse(uri, cookies);
        return null;
      case _CookieJarDelete(:final uri, :final withDomainSharedCookie):
        final jar = NetworkService().cookieJar;
        if (uri == null) {
          await jar.deleteAll();
        } else {
          await jar.delete(uri, withDomainSharedCookie);
        }
        return null;
      case _RateAcquire(:final key, :final concurrentRate):
        final record = await ConcurrentRateLimiter.acquire(key, concurrentRate);
        final ticket = _nextRateTicket++;
        _rateTickets[ticket] = record;
        return ticket;
    }
    throw UnsupportedError('Unknown source worker request: $request');
  }

  static void _onWorkerNotice(SourceWorker from, Object notice) {
    switch (notice) {
      case _Log(:final message, :final error, :final stackTrace, :final toast):
        AppLog.put(
          message,
          error: error,
          stackTrace: stackTrace == null
              ? null
              : StackTrace.fromString(stackTrace),
          toast: toast,
        );
      case _RateRelease(:final ticket):
        ConcurrentRateLimiter.release(_rateTickets.remove(ticket));
      case _CacheWrite(:final key, :final value, :final deadline):
        CacheManager().applyMirroredWrite(key, value, deadline);
        _notifyWorkers(notice, except: from);
      case _CookieWrite(:final domain, :final cookie):
        CookieStore().applyMirroredWrite(domain, cookie);
        _notifyWorkers(notice, except: from);
    }
  }

  static void _installMainMirrors() {
    CacheManager.onMemoryWrite = (key, value, deadline) =>
        _notifyWorkers(_CacheWrite(key, value, deadline));
    CookieStore.onMemoryWrite = (domain, cookie) =>
        _notifyWorkers(_CookieWrite(domain, cookie));
    WebViewUserAgent.onChanged = (userAgent) =>
        _notifyWorkers(_UserAgent(userAgent));
  }

  static void _uninstallMainMirrors() {
    CacheManager.onMemoryWrite = null;
    CookieStore.onMemoryWrite = null;
    WebViewUserAgent.onChanged = null;
  }

  static void _notifyWorkers(Object notice, {SourceWorker? except}) {
    for (final worker in _live) {
      if (identical(worker, except)) continue;
      _tryNotify(worker._channel, notice);
    }
  }
}

/// [SourceWorker.run] 的工作連同捕捉的變數送不進 worker。
final class _TaskNotSendable implements Exception {
  const _TaskNotSendable(this.error);

  final ArgumentError error;
}

/// 正在執行的書源工作的取消訊號。規則 JS 自己發的請求（`java.ajax` 這類）
/// 和規則裡的資源載入拿不到呼叫端傳的 [CancelToken]，從這裡取；工作被取消
/// 時它們跟著停。
CancelToken? get currentSourceCancelToken =>
    Zone.current[_cancelTokenZoneKey] as CancelToken?;

final Object _cancelTokenZoneKey = Object();

/// 在記著 [cancelToken] 的 Zone 裡執行 [task]。沒給時沿用外層工作的：書源
/// 工作裡又叫 [SourceIsolate.run] 的（原地執行），跟著外層一起取消。
Future<R> _runCancellable<R>(
  Future<R> Function(CancelToken cancelToken) task,
  CancelToken? cancelToken,
) {
  final token = cancelToken ?? currentSourceCancelToken ?? CancelToken();
  return runZoned(() => task(token), zoneValues: {_cancelTokenZoneKey: token});
}

/// 快取裡存的值理論上都是字串；送不過去的不同步，只記下來。
void _tryNotify(IsolateChannel channel, Object notice) {
  try {
    channel.notify(notice);
  } on ArgumentError catch (e) {
    AppLog.w('記憶體快取的寫入無法同步到另一個 isolate: $e');
  }
}

// ── worker 這一端 ───────────────────────────────────────────────────

void _main(SendPort mainPort) {
  final inbox = ReceivePort('SourceWorker');
  final tasks = <int, CancelToken>{};
  late final IsolateChannel channel;
  channel = IsolateChannel(
    mainPort,
    onRequest: (request) async {
      switch (request) {
        case _RunTask(:final id, :final task):
          final cancelToken = CancelToken();
          tasks[id] = cancelToken;
          try {
            return await _runCancellable(task, cancelToken);
          } finally {
            tasks.remove(id);
          }
        case final _Initialize init:
          await _initialize(init, channel);
          return null;
      }
      throw UnsupportedError('Unknown request for the source worker: $request');
    },
    onNotice: (notice) {
      switch (notice) {
        case _CancelTask(:final id):
          tasks[id]?.cancel('已取消');
        case _CacheWrite(:final key, :final value, :final deadline):
          CacheManager().applyMirroredWrite(key, value, deadline);
        case _CookieWrite(:final domain, :final cookie):
          CookieStore().applyMirroredWrite(domain, cookie);
        case _UserAgent(:final userAgent):
          WebViewUserAgent.value = userAgent;
      }
    },
  );
  inbox.listen(channel.receive);
  mainPort.send(inbox.sendPort);
}

Future<void> _initialize(_Initialize init, IsolateChannel channel) async {
  final rootToken = init.rootToken;
  // 讓外掛（例如規則檔案 API 用的 path_provider）能用；平台送來的訊息仍
  // 只到主 isolate，所以 WebView 交給主 isolate。
  if (rootToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
  }
  AppLog.delegate = (message, error, stackTrace, toast) => channel.notify(
    _Log(
      message,
      error: error?.toString(),
      stackTrace: stackTrace?.toString(),
      toast: toast,
    ),
  );
  HeadlessWebViewService.delegate =
      ({
        required String url,
        Map<String, String>? headers,
        String? userAgent,
        String? js,
        int delayTime = 0,
      }) async => await channel.request(
        _RenderHtml(
          url: url,
          headers: headers,
          userAgent: userAgent,
          js: js,
          delayTime: delayTime,
        ),
      ) as String;
  BackstageWebView.delegate = (request) async =>
      (await channel.request(request) as Map).cast<String, dynamic>();
  CloudflareClearance.delegate = (uri) async =>
      await channel.request(_Clearance(uri)) as ClearanceResult;
  WebViewUserAgent.value = init.webViewUserAgent;
  ConcurrentRateLimiter.delegate = _MainRateLimits(channel);
  CacheManager.onMemoryWrite = (key, value, deadline) =>
      _tryNotify(channel, _CacheWrite(key, value, deadline));
  CookieStore.onMemoryWrite = (domain, cookie) =>
      _tryNotify(channel, _CookieWrite(domain, cookie));

  // 規則的 fetch／XHR：沒有 rootBundle，用主 isolate 讀好的 polyfill；讀不到
  // 時給空字串，fetch 不能用，但不會去碰 rootBundle。
  fetchPolyfillSource = init.fetchPolyfill ?? '';
  final dictionaries = init.dictionaries;
  if (dictionaries != null) {
    ChineseUtils.initializeFromDictionaryData(dictionaries);
  }

  final connection = await DriftIsolate.fromConnectPort(init.databasePort)
      .connect();
  registerDatabase(AppDatabase.connected(connection));
  await NetworkService().init(cookieJar: _MainCookieJar(channel));
}

/// Cookie 檔在主 isolate：載入與寫入都交給它。
final class _MainCookieJar implements CookieJar {
  _MainCookieJar(this._channel);

  final IsolateChannel _channel;

  @override
  bool get ignoreExpires => false;

  @override
  Future<List<Cookie>> loadForRequest(Uri uri) async =>
      (await _channel.request(_CookieJarLoad(uri)) as List).cast<Cookie>();

  @override
  Future<void> saveFromResponse(Uri uri, List<Cookie> cookies) =>
      _channel.request(_CookieJarSave(uri, cookies));

  @override
  Future<void> delete(Uri uri, [bool withDomainSharedCookie = false]) =>
      _channel.request(_CookieJarDelete(uri, withDomainSharedCookie));

  @override
  Future<void> deleteAll() => _channel.request(const _CookieJarDelete(null));
}

/// 書源限流紀錄在主 isolate：發請求前向它借，結束時交回。
final class _MainRateLimits implements ConcurrentRateDelegate {
  _MainRateLimits(this._channel);

  final IsolateChannel _channel;

  @override
  Future<int> acquire(String key, String concurrentRate) async =>
      await _channel.request(_RateAcquire(key, concurrentRate)) as int;

  @override
  void release(int ticket) => _channel.notify(_RateRelease(ticket));
}

// ── 訊息 ────────────────────────────────────────────────────────────

final class _Initialize {
  const _Initialize({
    required this.databasePort,
    required this.rootToken,
    required this.dictionaries,
    required this.fetchPolyfill,
    required this.webViewUserAgent,
  });

  final SendPort databasePort;
  final RootIsolateToken? rootToken;
  final List<String>? dictionaries;
  final String? fetchPolyfill;
  final String? webViewUserAgent;
}

final class _RunTask {
  const _RunTask(this.id, this.task);

  final int id;
  final Future<Object?> Function(CancelToken cancelToken) task;
}

final class _CancelTask {
  const _CancelTask(this.id);

  final int id;
}

final class _Log {
  const _Log(
    this.message, {
    required this.error,
    required this.stackTrace,
    required this.toast,
  });

  final String message;
  final String? error;
  final String? stackTrace;
  final bool toast;
}

final class _RenderHtml {
  const _RenderHtml({
    required this.url,
    required this.headers,
    required this.userAgent,
    required this.js,
    required this.delayTime,
  });

  final String url;
  final Map<String, String>? headers;
  final String? userAgent;
  final String? js;
  final int delayTime;
}

final class _Clearance {
  const _Clearance(this.uri);

  final Uri uri;
}

final class _CookieJarLoad {
  const _CookieJarLoad(this.uri);

  final Uri uri;
}

final class _CookieJarSave {
  const _CookieJarSave(this.uri, this.cookies);

  final Uri uri;
  final List<Cookie> cookies;
}

/// [uri] 為 null 是全部刪除。
final class _CookieJarDelete {
  const _CookieJarDelete(this.uri, [this.withDomainSharedCookie = false]);

  final Uri? uri;
  final bool withDomainSharedCookie;
}

final class _RateAcquire {
  const _RateAcquire(this.key, this.concurrentRate);

  final String key;
  final String concurrentRate;
}

final class _RateRelease {
  const _RateRelease(this.ticket);

  final int ticket;
}

final class _CacheWrite {
  const _CacheWrite(this.key, this.value, this.deadline);

  final String key;
  final Object? value;
  final int deadline;
}

final class _CookieWrite {
  const _CookieWrite(this.domain, this.cookie);

  final String? domain;
  final String? cookie;
}

final class _UserAgent {
  const _UserAgent(this.userAgent);

  final String userAgent;
}

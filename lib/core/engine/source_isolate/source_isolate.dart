import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:drift/isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart' show fetchPolyfillSource;
import 'package:native_synchronization/mailbox.dart';
import 'package:native_synchronization/sendable.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/web_book/headless_webview_service.dart';
import 'package:night_reader/core/network/cloudflare.dart';
import 'package:night_reader/core/network/request_log.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/backstage_webview.dart';
import 'package:night_reader/core/services/cache_manager.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/core/services/cookie_store.dart';
import 'package:night_reader/core/services/crash_handler.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/core/services/rate_limiter.dart';
import 'package:night_reader/core/services/source_interaction.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';

import 'isolate_channel.dart';

part 'blocking_call.dart';

/// 書源 isolate：常駐的背景 isolate，書源的抓取與解析（含規則 JS）在這裡
/// 跑，主 isolate 只收結果，畫面不會被解析卡住（ADR 0028）。共有
/// [workerCount] 條，每條是一個 [SourceWorker]；規則 JS 等網路時那一條整條
/// 停住（[BlockingCall]，ADR 0034），其他條照常跑。
abstract final class SourceIsolate {
  /// 只在 App 的主 isolate 開（`main.dart`）。測試與 Workmanager 不開，
  /// [run] 原地執行。
  static bool enabled = false;

  /// 書源 isolate 的條數。規則 JS 等網路時整條停住，一條的話一個書源在等，
  /// 其他書源全部排隊；搜尋一次上百個書源，等的時間會疊起來。每條約多
  /// 8MB（幾乎都是繁簡字典）。手機多半八核，畫面、繪製、資料庫、網路
  /// （[SourceIo]）各佔一條，留四條給書源。
  static const int workerCount = 4;

  static List<Future<SourceWorker?>>? _workers;
  static int _nextUnkeyed = 0;

  /// 開始開書源 isolate（[enabled] 時），不等它開好，[run] 會等。開不起來
  /// 的那一條記下原因，送到那一條的工作改回主 isolate 執行。[database]
  /// 預設為主 isolate 的資料庫；[databaseFile] 是它的檔案，網路 isolate
  /// 用它另開一條連線（見 [SourceIo]），沒給時（例如測試的記憶體資料庫）
  /// 改連同一個。給了 [database] 的，要先開過（查詢過一次）再呼叫。
  static void start({
    Future<DriftIsolate>? database,
    Future<String?>? databaseFile,
  }) {
    if (!enabled || _workers != null) return;
    SourceIo.configure(
      database: database,
      databaseFile:
          databaseFile ?? (database == null ? AppDatabase.sharedFile : null),
    );
    // 先在主 isolate 把資料庫開好：版本升級（migration）跑完，網路 isolate
    // 另開的連線才不會碰到升級到一半的資料庫，也不必先經過 drift isolate
    // 確認（那會排在書源 isolate 的交易後面，見 [SourceIo]）。
    final opened = database == null
        ? AppDatabase().customSelect('SELECT 1').get()
        : Future<void>.value();
    _workers = [
      for (var i = 1; i <= workerCount; i++)
        opened
            .then(
              (_) => SourceWorker.spawn(
                debugName: 'SourceIsolate $i',
                withDictionaries: true,
                database: database,
              ),
            )
            .then<SourceWorker?>(
              (worker) => worker,
              onError: (Object error, StackTrace stackTrace) {
                AppLog.e(
                  '第 $i 條書源 isolate 開不起來，送到這條的書源工作改在主 isolate '
                  '執行: $error',
                  error: error,
                  stackTrace: stackTrace,
                );
                return null;
              },
            ),
    ];
  }

  /// 在書源 isolate 執行 [task] 並傳回結果；沒開時原地執行。[task] 拿到的
  /// [CancelToken] 屬於執行它的 isolate，[cancelToken] 取消時跟著取消。
  /// 錯誤照原樣丟出（送不回來時見 [IsolateTaskError]）。
  ///
  /// [affinity] 相同的工作送到同一條：同一個書源的工作共用那條的 jsLib 與
  /// 規則引擎快取；下載一輪的書與章節只存在規劃它的那一條。沒給時輪流送。
  ///
  /// [task] 連同它捕捉的變數會複製到書源 isolate，要在只捕捉書源、書籍與
  /// 字串這類資料的地方建立（例如頂層函式），不能捕捉頁面、回呼或資料庫
  /// 連線。
  static Future<R> run<R>(
    Future<R> Function(CancelToken cancelToken) task, {
    String? affinity,
    CancelToken? cancelToken,
  }) async {
    final workers = _workers;
    final worker = workers == null
        ? null
        : await workers[(affinity?.hashCode ?? _nextUnkeyed++) %
              workers.length];
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

  /// 測試用：結束書源 isolate 與網路 isolate，回到原地執行。
  @visibleForTesting
  static Future<void> stop() async {
    final workers = _workers;
    _workers = null;
    for (final worker in await Future.wait(
      workers ?? const <Future<SourceWorker?>>[],
    )) {
      worker?.kill(StateError('書源 isolate 已結束'));
    }
    await SourceIo.stop();
  }
}

/// 網路 isolate：替停住的書源 isolate 做要等的事（[BlockingCall]）——網路、
/// 快取與 Cookie 的資料庫讀取、平台的檔案路徑。它自己從不停住，也不跑規則
/// JS，所以停住的那一條等得到它（ADR 0034）。
///
/// 資料庫另開一條連線（[_databaseFile]）：drift 的交易進行中，同一個 drift
/// isolate 的其他查詢都要等它結束；停住的書源 isolate 手上若有一段交易，
/// 它等的讀取又排在這段交易後面，兩邊就互相等死。
abstract final class SourceIo {
  static Future<DriftIsolate>? _database;
  static Future<String?>? _databaseFile;
  static Future<SourceWorker>? _worker;

  static void configure({
    Future<DriftIsolate>? database,
    Future<String?>? databaseFile,
  }) {
    _database = database;
    _databaseFile = databaseFile;
  }

  /// 第一次有書源 isolate 停住時才開；結束了（例如當掉）下一次再開。
  static Future<SourceWorker> get worker => _worker ??= () async {
    try {
      final worker = await SourceWorker._spawn(
        debugName: 'SourceIo',
        role: _Role.io,
        withDictionaries: false,
        database: _database,
        databaseFile: await _databaseFile,
      );
      worker._onExit = () => _worker = null;
      return worker;
    } catch (_) {
      _worker = null;
      rethrow;
    }
  }();

  static Future<void> stop() async {
    final worker = _worker;
    _worker = null;
    try {
      (await worker)?.kill(StateError('網路 isolate 已結束'));
    } catch (_) {
      // 本來就沒開起來。
    }
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
/// - 規則 JS 要等的呼叫：worker 整條停住，交給網路 isolate（[SourceIo]）
///   做，結果由主 isolate 放進 worker 的 [_replies]（[BlockingCall]）。
///
/// 書源 isolate 是常駐的 worker；書源校驗每個書源開一個，逾時就直接
/// 結束它，卡住的同步規則 JS 也停得下來。
final class SourceWorker {
  SourceWorker._(
    this._isolate,
    this._channel,
    this._inbox,
    this._errors,
    this._replies,
  );

  final Isolate _isolate;
  final IsolateChannel _channel;
  final ReceivePort _inbox;
  final ReceivePort _errors;
  int _nextTaskId = 0;
  bool _killed = false;

  /// 停住的 worker 從這裡拿回結果。由主 isolate 建立與擁有：worker 被結束
  /// 時網路 isolate 可能還在做它的事，信箱的記憶體不能跟著 worker 釋放。
  final Mailbox _replies;

  /// worker 現在停住等的那一次呼叫。停住的 worker 不會再發，所以同時只有
  /// 一次。
  _Blocked? _blocked;

  /// isolate 結束（當掉或被結束）時呼叫一次。
  void Function()? _onExit;

  /// 這個 worker 借走、還沒交回的限流紀錄；結束 worker 時一併交回，否則
  /// 固定間隔限流的書源之後的請求會一直排隊。
  final Set<int> _tickets = {};

  /// 活著的 worker；主 isolate 的記憶體寫入轉送給它們。
  static final Set<SourceWorker> _live = {};

  /// worker 借走、還沒交回的限流紀錄。worker 停住時它的紀錄提早交回，
  /// 這裡留著 null，之後真的交回時什麼都不做。
  static final Map<int, ConcurrentRecord?> _rateTickets = {};
  static int _nextRateTicket = 0;
  static int _nextBlockedCall = 0;

  /// 開一個 worker，等它連上資料庫、網路設定好才傳回。[withDictionaries]
  /// 為 false 時不載入繁簡字典（校驗用，省下每個書源解析一次字典），
  /// `java.t2s` 這類轉換原樣返回。
  static Future<SourceWorker> spawn({
    required String debugName,
    required bool withDictionaries,
    Future<DriftIsolate>? database,
  }) => _spawn(
    debugName: debugName,
    role: _Role.source,
    withDictionaries: withDictionaries,
    database: database,
  );

  /// [databaseFile] 只給網路 isolate：另開一條連到這個檔案的連線，不排在
  /// drift isolate 的交易後面（見 [SourceIo]）。
  static Future<SourceWorker> _spawn({
    required String debugName,
    required _Role role,
    required bool withDictionaries,
    Future<DriftIsolate>? database,
    String? databaseFile,
  }) async {
    final inbox = ReceivePort('$debugName main');
    final errors = ReceivePort('$debugName errors');
    final exit = ReceivePort('$debugName exit');
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
        onExit: exit.sendPort,
      );
    } catch (_) {
      inbox.close();
      errors.close();
      exit.close();
      rethrow;
    }
    late final SourceWorker worker;
    channel = IsolateChannel(
      await remote.future,
      onRequest: (request) => _answerWorker(worker, request),
      onNotice: (notice) => _onWorkerNotice(worker, notice),
    );
    worker = SourceWorker._(isolate, channel, inbox, errors, Mailbox());
    exit.listen((_) {
      exit.close();
      worker.kill(StateError('$debugName 已結束'));
    });
    _live.add(worker);
    _installMainMirrors();
    try {
      await channel.request(
        _Initialize(
          role: role,
          databasePort:
              (await (database ?? AppDatabase.sharedIsolate)).connectPort,
          databaseFile: databaseFile,
          replies: role == _Role.source ? worker._replies.asSendable : null,
          rootToken: RootIsolateToken.instance,
          dictionaries: withDictionaries ? await _dictionaries() : null,
          fetchPolyfill: await _fetchPolyfill(),
          storageRoots: await _storageRoots(),
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
        if (_killed) return;
        _channel.notify(_CancelTask(id));
        // 停住的 worker 收不到取消，替它把等的那一次也取消；它醒來後同一個
        // 工作再發的也直接以取消結束（[_serveBlock]）。
        _cancelledTasks.add(id);
        final blocked = _blocked;
        if (blocked != null && blocked.taskId == id) blocked.cancel();
      }),
    );
    try {
      return await result as R;
    } finally {
      _cancelledTasks.remove(id);
    }
  }

  /// 已經取消、還沒跑完的工作。worker 從停住醒來時還沒收到取消的通知
  /// （它在停住時排在後面），接著同步再發的要等的呼叫由這裡擋下。
  final Set<int> _cancelledTasks = {};

  /// 立刻結束 worker；還在等的工作以 [error] 結束。
  void kill(Object error) {
    if (_killed) return;
    _killed = true;
    _live.remove(this);
    if (_live.isEmpty) _uninstallMainMirrors();
    for (final ticket in _tickets) {
      ConcurrentRateLimiter.release(_rateTickets.remove(ticket));
    }
    _tickets.clear();
    _blocked?.cancel();
    // 停在原生的等待裡時 isolate 結束不了；關掉信箱叫醒它。
    _replies.close();
    _channel.close(error);
    _isolate.kill(priority: Isolate.immediate);
    _inbox.close();
    _errors.close();
    _onExit?.call();
  }

  /// worker 停住了：交給網路 isolate 做 [block]，把結果放進 [_replies]。
  Future<void> _serveBlock(_Block block) async {
    final call = _Blocked(block.taskId, _nextBlockedCall++);
    _blocked = call;
    _releaseTicketsWhileBlocked();
    Uint8List outcome;
    try {
      if (_cancelledTasks.contains(block.taskId)) throw _cancelled();
      final io = await SourceIo.worker;
      // 開網路 isolate 的這段時間裡被取消了。
      if (call.cancelled) throw _cancelled();
      call.io = io;
      final reply = await io._channel.request(
        _Perform(call.id, block.task, recordRequests: block.recordRequests),
      );
      outcome = (reply as TransferableTypedData).materialize().asUint8List();
    } catch (error) {
      outcome = _Outcome.failure(error, const []);
    }
    _blocked = null;
    if (_killed) return;
    _replies.put(outcome);
  }

  static DioException _cancelled() => DioException(
    requestOptions: RequestOptions(),
    type: DioExceptionType.cancel,
    error: '已取消',
  );

  /// 停住的 worker 手上的限流名額先交回：它在等的請求可能正是同一個書源，
  /// 名額卻被它自己凍住的另一個請求佔著，網路 isolate 永遠借不到。被凍住
  /// 的那些請求多半已經送出，回應躺在 worker 的連線裡等它醒來。
  void _releaseTicketsWhileBlocked() {
    for (final ticket in _tickets) {
      ConcurrentRateLimiter.release(_rateTickets[ticket]);
      _rateTickets[ticket] = null;
    }
  }

  // ── 主 isolate 一次讀好、給每個 worker 的資源 ──────────────────────

  static Future<List<String>?>? _dictionariesFuture;
  static Future<String?>? _fetchPolyfillFuture;
  static Future<StorageRoots>? _storageRootsFuture;

  /// 路徑不會變，問一次就好：書源校驗每個書源開一個 worker。
  static Future<StorageRoots> _storageRoots() =>
      _storageRootsFuture ??= AppStoragePaths.roots();

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

  static Future<Object?> _answerWorker(
    SourceWorker from,
    Object request,
  ) async {
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
      case _ClearanceRejected(:final uri):
        await CloudflareClearance.markRejected(uri);
        return null;
      case final SourceInteractionRequest interaction:
        return SourceInteraction.serve(interaction);
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
        if (from._killed) {
          // 排隊時 worker 已經結束，沒有人會交回。
          ConcurrentRateLimiter.release(record);
          throw StateError('書源 worker 已結束');
        }
        final ticket = _nextRateTicket++;
        from._tickets.add(ticket);
        // 排到時 worker 停住了：它收不到這張票，名額照停住的規則先交回。
        if (from._blocked != null) {
          ConcurrentRateLimiter.release(record);
          _rateTickets[ticket] = null;
        } else {
          _rateTickets[ticket] = record;
        }
        return ticket;
    }
    throw UnsupportedError('Unknown source worker request: $request');
  }

  static void _onWorkerNotice(SourceWorker from, Object notice) {
    switch (notice) {
      case final _Block block:
        unawaited(from._serveBlock(block));
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
        from._tickets.remove(ticket);
        ConcurrentRateLimiter.release(_rateTickets.remove(ticket));
      case final SourceMessage message:
        SourceInteraction.deliver(message);
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

/// worker 上正在執行的工作在主 isolate 的編號；停住時主 isolate 用它把
/// 那一次呼叫跟著工作一起取消。
final Object _taskIdZoneKey = Object();

/// 在記著 [cancelToken] 的 Zone 裡執行 [task]。沒給時沿用外層工作的：書源
/// 工作裡又叫 [SourceIsolate.run] 的（原地執行），跟著外層一起取消。
Future<R> _runCancellable<R>(
  Future<R> Function(CancelToken cancelToken) task,
  CancelToken? cancelToken, {
  int? taskId,
}) {
  final token = cancelToken ?? currentSourceCancelToken ?? CancelToken();
  return runZoned(
    () => task(token),
    zoneValues: {_cancelTokenZoneKey: token, _taskIdZoneKey: ?taskId},
  );
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
  final performs = <int, CancelToken>{};
  late final IsolateChannel channel;
  channel = IsolateChannel(
    mainPort,
    onRequest: (request) async {
      switch (request) {
        case _RunTask(:final id, :final task):
          final cancelToken = CancelToken();
          tasks[id] = cancelToken;
          try {
            return await _runCancellable(task, cancelToken, taskId: id);
          } finally {
            tasks.remove(id);
          }
        case _Perform(:final id, :final task, :final recordRequests):
          final cancelToken = CancelToken();
          performs[id] = cancelToken;
          try {
            return TransferableTypedData.fromList([
              await _perform(task, cancelToken, recordRequests: recordRequests),
            ]);
          } finally {
            performs.remove(id);
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
        case _CancelPerform(:final id):
          performs[id]?.cancel('已取消');
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
  CloudflareClearance.rejectedDelegate = (uri) =>
      channel.request(_ClearanceRejected(uri));
  // 登入頁的書源要使用者操作：書源 isolate 停住，網路 isolate 把請求轉給
  // 主 isolate 的登入頁；訊息不用等，書源 isolate 直接送過去。
  SourceInteraction.delegate = channel.request;
  SourceInteraction.messageDelegate = (message) => _tryNotify(channel, message);
  WebViewUserAgent.value = init.webViewUserAgent;
  ConcurrentRateLimiter.delegate = _MainRateLimits(channel);
  CacheManager.onMemoryWrite = (key, value, deadline) =>
      _tryNotify(channel, _CacheWrite(key, value, deadline));
  CookieStore.onMemoryWrite = (domain, cookie) =>
      _tryNotify(channel, _CookieWrite(domain, cookie));

  // 規則的 fetch／XHR：沒有 rootBundle，用主 isolate 讀好的 polyfill；讀不到
  // 時給空字串，fetch 不能用，但不會去碰 rootBundle。
  fetchPolyfillSource = init.fetchPolyfill ?? '';
  AppStoragePaths.useRoots(init.storageRoots);
  final dictionaries = init.dictionaries;
  if (dictionaries != null) {
    ChineseUtils.initializeFromDictionaryData(dictionaries);
  }

  final databaseFile = init.databaseFile;
  // 另開的連線不經過 drift isolate：開書源 isolate 之前主 isolate 已經把
  // 資料庫開好（[SourceIsolate.start]），版本升級（migration）跑完了。
  registerDatabase(
    databaseFile == null
        ? AppDatabase.connected(
            await DriftIsolate.fromConnectPort(init.databasePort).connect(),
          )
        : AppDatabase.separateConnection(databaseFile),
  );
  await NetworkService().init(cookieJar: _MainCookieJar(channel));

  final replies = init.replies;
  if (init.role == _Role.source && replies != null) {
    BlockingCall._install(channel, replies.materialize());
  }
}

/// 網路 isolate 做停住的 worker 交來的 [task]，結果編成一段位元組
/// （[_Outcome]）。取消時 [task] 裡的請求跟著停。
Future<Uint8List> _perform(
  Future<Object?> Function() task,
  CancelToken cancelToken, {
  required bool recordRequests,
}) async {
  final requestUrls = <String>[];
  try {
    final value = await _runCancellable(
      (_) => recordRequests ? recordRequestUrls(requestUrls, task) : task(),
      cancelToken,
    );
    return _Outcome.success(value, requestUrls);
  } catch (error) {
    return _Outcome.failure(error, requestUrls);
  }
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

/// 書源 isolate 跑書源工作、可以停住等；網路 isolate 替它們做要等的事，
/// 自己從不停住（[SourceIo]）。
enum _Role { source, io }

final class _Initialize {
  const _Initialize({
    required this.role,
    required this.databasePort,
    required this.databaseFile,
    required this.replies,
    required this.rootToken,
    required this.dictionaries,
    required this.fetchPolyfill,
    required this.storageRoots,
    required this.webViewUserAgent,
  });

  final _Role role;
  final SendPort databasePort;
  final String? databaseFile;
  final Sendable<Mailbox>? replies;
  final RootIsolateToken? rootToken;
  final List<String>? dictionaries;
  final String? fetchPolyfill;
  final StorageRoots storageRoots;
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

/// worker 停住了，請主 isolate 交給網路 isolate 做 [task]。[taskId] 是它
/// 停在哪一個書源工作裡。
final class _Block {
  const _Block(this.taskId, this.task, {required this.recordRequests});

  final int? taskId;
  final Future<Object?> Function() task;

  /// 書源除錯正在記這個工作送出的請求網址（`recordRequestUrls`）。
  final bool recordRequests;
}

/// 主 isolate 請網路 isolate 做停住的 worker 交來的 [task]。
final class _Perform {
  const _Perform(this.id, this.task, {required this.recordRequests});

  final int id;
  final Future<Object?> Function() task;
  final bool recordRequests;
}

final class _CancelPerform {
  const _CancelPerform(this.id);

  final int id;
}

/// 主 isolate 這邊記著的、某個 worker 停住等的那一次呼叫。
final class _Blocked {
  _Blocked(this.taskId, this.id);

  final int? taskId;
  final int id;

  /// 做這件事的網路 isolate；還在開時是 null，開好後看 [cancelled]。
  SourceWorker? io;
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    io?._channel.notify(_CancelPerform(id));
  }
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

final class _ClearanceRejected {
  const _ClearanceRejected(this.uri);

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

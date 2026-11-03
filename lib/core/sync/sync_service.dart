import 'dart:async';

import 'package:drift/drift.dart' show TableInfo, TableUpdateQuery;
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:synchronized/synchronized.dart';

import 'bookmark_sync.dart';
import 'highlight_sync.dart';
import 'bookshelf_sync.dart';
import 'google_drive_auth.dart';
import 'google_drive_sync_store.dart';
import 'login_data_sync.dart';
import 'progress_sync.dart';
import 'read_stats_sync.dart';
import 'replace_rule_sync.dart';
import 'settings_sync.dart';
import 'source_sync.dart';
import 'sync_base_storage.dart';
import 'sync_kind.dart';
import 'sync_merge.dart';
import 'sync_records.dart';
import 'sync_settings.dart';
import 'sync_store.dart';
import 'webdav_sync_store.dart';

/// 同步的狀態，給「備份與同步」頁顯示。
@immutable
class SyncStatus {
  const SyncStatus({
    this.space = SyncSpace.none,
    this.running = false,
    this.lastSyncAt,
    this.error,
    this.progress,
  });

  final SyncSpace space;
  final bool running;
  final DateTime? lastSyncAt;

  /// 目前正在處理的資料及順序；不是傳輸百分比。
  final ({String kind, int step, int total})? progress;

  /// 上次同步失敗的原因；成功一次就清掉。
  final String? error;

  bool get enabled => space != SyncSpace.none;

  SyncStatus copyWith({
    SyncSpace? space,
    bool? running,
    DateTime? lastSyncAt,
    String? error,
    bool clearError = false,
    ({String kind, int step, int total})? progress,
    bool clearProgress = false,
  }) => SyncStatus(
    space: space ?? this.space,
    running: running ?? this.running,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    error: clearError ? null : error ?? this.error,
    progress: clearProgress ? null : progress ?? this.progress,
  );
}

/// 閱讀器開書或回到前景時抓到、比這台新的進度。跳過去、存好位置之後，用
/// 存下的那一筆（[ProgressSync.recordOf]）呼叫 [commit]，把它記成和雲端那筆
/// 同步過，離開時不會再當成新的改動上傳；之後又讀了的話，和它比得出來。
/// 沒跳成（取不到那一章、被別的操作取代）就不要呼叫，下次還會再抓到。
class PulledProgress {
  PulledProgress(this.progress, this._commit, {bool Function()? isCurrent})
    : _isCurrent = isCurrent ?? _always;

  final SyncedProgress progress;
  final Future<void> Function(SyncRecord applied) _commit;
  final bool Function() _isCurrent;

  static bool _always() => true;

  /// 抓的這段時間沒有換同步空間、也沒停用：換過的話抓到的是舊空間的進度，
  /// 不能跳過去，不然之後會被當成這台的新進度送進新的空間。
  bool get isCurrent => _isCurrent();

  Future<void> commit(SyncRecord applied) => _commit(applied);
}

/// 多台手機同步（ADR 0039）：每種資料（[SyncKind]）讀雲端、每筆合併、
/// 寫回。日常只同步閱讀進度（[syncProgress]），全部種類要使用者按「立即
/// 全面同步」（[syncAll]，ADR 0046）。同一時間只跑一次；跑的途中又有人要
/// 同步，跑完再補一次。
class SyncService {
  SyncService({
    SyncSettings? settings,
    SyncBaseStorage? bases,
    SyncStore? Function(
      SyncSpace space,
      WebDavAccount? webDav,
      String? googleAccount,
    )?
    storeFactory,
    this._bookDao,
    this._chapterDao,
    this._database,
    List<SyncKind> Function(SyncService service)? kinds,
    GoogleDriveAuth? googleAuth,
    DateTime Function()? clock,
    SyncRunner? runner,
  }) : _settings = settings ?? SyncSettings(),
       _bases = bases ?? SyncBaseStorage(),
       _googleAuth = googleAuth ?? GoogleSignInDriveAuth.instance,
       _storeFactory =
           storeFactory ??
           ((space, webDav, googleAccount) => _defaultStore(
             space,
             webDav,
             googleAccount,
             googleAuth ?? GoogleSignInDriveAuth.instance,
           )),
       _kinds = kinds ?? _defaultKinds,
       _clock = clock ?? DateTime.now,
       _runner = runner ?? runSyncWorkInBackground;

  static SyncService instance = SyncService();

  final SyncSettings _settings;
  final SyncBaseStorage _bases;
  final SyncStore? Function(
    SyncSpace space,
    WebDavAccount? webDav,
    String? googleAccount,
  )
  _storeFactory;
  final GoogleDriveAuth _googleAuth;
  final BookDao? _bookDao;
  final ChapterDao? _chapterDao;

  /// 看書源與替換規則有沒有改（[_watchEdits]）；沒給時用 App 的資料庫。
  final AppDatabase? _database;
  final List<SyncKind> Function(SyncService service) _kinds;
  final DateTime Function() _clock;

  /// 合併計算交給誰跑：預設背景 isolate；元件測試的假時間等不到 isolate
  /// 回覆，給 [runSyncWorkInline]。
  final SyncRunner _runner;
  final Lock _lock = Lock();

  /// 同一份檔案被別台同時寫入時，重讀再合併的次數。
  static const int _maxAttempts = 3;

  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus());

  /// 閱讀器開著的書：全部同步時不改這幾本（進度由閱讀器自己跳，移出書架
  /// 與使用者改的資料等關掉後下次同步）。
  final Set<String> _openBooks = {};

  /// 換同步空間或停用時加一：之前抓到、還沒 commit 的進度屬於舊的空間，
  /// 不再記進上次同步的紀錄。
  int _generation = 0;

  Future<void>? _running;
  bool _again = false;

  /// Google 系統登入畫面會使 App 暫停／恢復，這段期間不需要額外同步舊空間。
  bool _authorizingGoogleDrive = false;

  static SyncStore? _defaultStore(
    SyncSpace space,
    WebDavAccount? webDav,
    String? googleAccount,
    GoogleDriveAuth googleAuth,
  ) {
    return switch (space) {
      SyncSpace.none => null,
      SyncSpace.webdav when webDav != null => WebDavSyncStore(
        url: webDav.url,
        user: webDav.user,
        password: webDav.password,
      ),
      SyncSpace.googleDrive when googleAccount != null => GoogleDriveSyncStore(
        auth: googleAuth,
        account: googleAccount,
      ),
      SyncSpace.webdav || SyncSpace.googleDrive => null,
    };
  }

  ProgressSync get _progress => ProgressSync(
    bookDao: _bookDao ?? getIt<BookDao>(),
    chapterDao: _chapterDao ?? getIt<ChapterDao>(),
    isOpen: isBookOpen,
  );

  /// 書名加作者是 [key] 的書正開在閱讀器裡（[openBook]）。
  bool isBookOpen(String key) => _openBooks.contains(key);

  /// 全面同步的順序：閱讀進度最先，正在等的閱讀器先拿到另一台讀到的地方
  /// （[progressReady]）。書源先到，書架上新加的書才
  /// 找得到書源；書先加進書架，進度才套用得上，所以書架之後再同步一次進度
  /// （只在中間有套用改動時，[_syncOnce]）。
  static List<SyncKind> _defaultKinds(SyncService service) => [
    service._progress,
    SourceSync(),
    ReplaceRuleSync(),
    BookshelfSync(isOpen: service.isBookOpen),
    service._progress,
    BookmarkSync(),
    HighlightSync(),
    ReadStatsSync(settings: service._settings, bases: service._bases),
    SettingsSync(),
    ...LoginDataSync.kinds(),
  ];

  /// 讀出設定，更新 [status]。
  Future<void> load() async {
    status.value = status.value.copyWith(
      space: await _settings.space(),
      lastSyncAt: await _settings.lastSyncAt(),
    );
  }

  /// 目前設定的同步空間。要寫入的只在 [_lock] 裡呼叫：讀設定到用完同步空間
  /// 之間，不會被停用或換帳號插進來，寫到已經不用的空間。
  Future<SyncStore?> _store() async {
    final space = await _settings.space();
    return _storeFactory(
      space,
      await _settings.webDavAccount(),
      await _settings.googleAccount(),
    );
  }

  /// 上次同步的紀錄屬於哪個同步空間的檔名。
  static const String _ownerFile = 'owner';

  /// 上次同步的紀錄是另一個同步空間的（在「同步空間」換了，或還原備份直接
  /// 改了同步設定），就全部作廢，照從沒同步過合併；不然會拿另一個空間的
  /// 紀錄判斷，把舊資料當成新的改動蓋掉這個空間。只在 [_lock] 裡呼叫。
  Future<void> _claimBases() async {
    final identity = await _settings.identity();
    final owner = (await _bases.readJson(_ownerFile))['space'];
    if (owner == identity) return;
    _generation++;
    _settled.clear();
    await _bases.clear();
    await _bases.writeJson(_ownerFile, {'space': identity});
  }

  /// 改用 [account] 的 WebDAV：先試連，連得上才存起來。換了空間照從沒同步過
  /// 合併；同一個空間（只改了密碼）留著上次同步的紀錄。接著由畫面開進度框
  /// 全面同步一次（`runFullSync`；使用者 2026-11-03 定的：選好就全面同步）。
  Future<void> useWebDav(WebDavAccount account) async {
    final store = _storeFactory(SyncSpace.webdav, account, null);
    await store!.check();
    await _lock.synchronized(() async {
      await _settings.useWebDav(account);
      await _claimBases();
    });
    status.value = status.value.copyWith(space: SyncSpace.webdav);
  }

  /// 改用這個 Google 帳號的雲端硬碟：跳出 Google 登入與授權，連得上才存起來；
  /// 接著由畫面開進度框全面同步一次（同 [useWebDav]）。只在使用者按了按鈕時
  /// 呼叫；授權失效後重新登入同一個帳號也走這裡，留著上次同步的紀錄。
  Future<void> useGoogleDrive() async {
    _authorizingGoogleDrive = true;
    try {
      final account = await _googleAuth.signIn();
      final store = _storeFactory(SyncSpace.googleDrive, null, account);
      await store!.check();
      await _lock.synchronized(() async {
        await _settings.useGoogleDrive(account);
        await _claimBases();
      });
      status.value = status.value.copyWith(space: SyncSpace.googleDrive);
    } finally {
      _authorizingGoogleDrive = false;
    }
  }

  Future<void> disable() async {
    final wasGoogle = await _settings.space() == SyncSpace.googleDrive;
    await _lock.synchronized(() async {
      _generation++;
      _settled.clear();
      await _settings.disable();
      await _bases.clear();
    });
    status.value = const SyncStatus();
    if (wasGoogle) {
      try {
        await _googleAuth.signOut();
      } catch (error, stackTrace) {
        AppLog.e('登出 Google 帳號失敗', error: error, stackTrace: stackTrace);
      }
    }
  }

  void openBook(Book book) => _openBooks.add(ProgressSync.keyOf(book));

  void closeBook(Book book) => _openBooks.remove(ProgressSync.keyOf(book));

  /// 日常的同步（開 App、回到前景、退到背景、離開閱讀器）：只同步閱讀進度，
  /// 不等結果。其他資料在主執行緒上比對很重，開書時跟著跑會讓動畫掉幀，
  /// 只在使用者按「立即全面同步」時同步（[syncAll]，ADR 0046）。正在同步
  /// 時，跑完再補一次。
  void syncProgress() => unawaited(_request(full: false));

  /// 全面同步：書架、書源、替換規則、設定、登入資料……全部種類。使用者在
  /// 「備份與同步」按「立即全面同步」、或剛選好同步空間時呼叫。正在同步時
  /// 不搶先，等含全部種類的那一輪做完才完成。失敗記在 [status]、不丟出來；
  /// 沒設定同步空間時什麼都不做。
  Future<void> syncAll() => _request(full: true);

  /// 取消全面同步：正在跑的那一輪目前這一種做完就停，已經寫完的種類留著，
  /// 不回滾；還沒開始的那一輪不跑。之後才要求的進度同步照常補跑。
  void cancelSync() {
    if (_running == null) return;
    _fullPending = false;
    _cancelled = true;
  }

  /// App 進入背景時同步本機改動；Google 帳號選取造成的暫停不算。
  void syncBeforeBackground() {
    if (_authorizingGoogleDrive) return;
    syncProgress();
  }

  /// 離開閱讀器、剛存好閱讀進度時用：同步閱讀進度，而且優先送出。正在全面
  /// 同步的話，不等這一輪全部做完，目前這一種做完就先把進度再同步一次，
  /// 另一台才在幾秒內拿得到。
  void requestSyncProgressFirst() {
    _progressFirst = true;
    syncProgress();
  }

  /// 有人要閱讀進度優先送出（[requestSyncProgressFirst]），還沒送。
  bool _progressFirst = false;

  /// 有人要全面同步（[syncAll]），還沒開始那一輪。
  bool _fullPending = false;

  /// 使用者取消了正在跑的那一輪全面同步（[cancelSync]）；下一輪開始時清掉。
  bool _cancelled = false;

  Future<void> _request({required bool full}) {
    if (full) _fullPending = true;
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final future = _runUntilSettled().whenComplete(_finishRun);
    _running = future;
    return future;
  }

  Future<void> _runUntilSettled() async {
    final timer = Stopwatch()..start();
    var rounds = 0;
    do {
      _again = false;
      _cancelled = false;
      final full = _fullPending;
      _fullPending = false;
      rounds++;
      await _syncOnce(full: full);
      // 取消只停全面同步；取消之後才要求的進度同步（回到前景、退到背景）
      // 照樣補一輪。
    } while (_again || _fullPending);
    if (status.value.enabled && timer.elapsedMilliseconds >= 1000) {
      AppLog.i('同步總耗時：${timer.elapsedMilliseconds}ms，共 $rounds 輪');
    }
  }

  /// 整輪（包含途中補跑的輪次）結束。先放下 [_running] 再通知畫面：聽到
  /// 「同步完成」時又要求同步的，會開新的一輪，不會拿到這一輪的 future。
  void _finishRun() {
    _running = null;
    _cancelled = false;
    status.value = status.value.copyWith(running: false, clearProgress: true);
    // 沒設定同步空間、或沒走到閱讀進度就失敗了，開書也不再等。
    _progressDone();
  }

  /// 開 App 進場播完時：讀出設定、同步一次閱讀進度，並開始數這台的改動
  /// （[_watchEdits]）。
  Future<void> start() async {
    _expectProgress();
    try {
      await load();
    } catch (error, stackTrace) {
      AppLog.e('讀同步設定失敗', error: error, stackTrace: stackTrace);
      _progressDone();
      return;
    }
    _watchEdits();
    await _request(full: false);
  }

  /// App 回到前景：同步閱讀進度，把別台在這段時間讀到的地方接過來。開書等
  /// 它做完（[progressReady]）。
  void syncAfterResume() {
    if (_authorizingGoogleDrive) return;
    _expectProgress();
    syncProgress();
  }

  /// 開 App 或回到前景後，閱讀進度還沒同步完時是這次同步做完進度那一步的
  /// 時候；其他時候是 null。
  Completer<void>? _progressPending;

  void _expectProgress() => _progressPending ??= Completer<void>();

  void _progressDone() {
    _progressPending?.complete();
    _progressPending = null;
  }

  /// 開 App 或回到前景後的這次同步，閱讀進度那一步做完（不論成功、失敗或
  /// 沒設定同步空間）時完成；已經做完就是 null。開書等它，書就開在另一台
  /// 讀到的地方，開書本身不連網。
  Future<void>? get progressReady => _progressPending?.future;

  final List<StreamSubscription<void>> _edits = [];

  /// 這台改了幾次，鍵是 [SyncKind.name]；只數書源、替換規則、書籤與標註
  /// （[_watchEdits]）。
  final Map<String, int> _localEdits = {};

  /// 上次同步時兩邊都沒變的種類：當時雲端檔的版本與這台改了幾次。之後兩邊
  /// 都還一樣，就不讀出整份來比（書源可能有幾百個），只問一次雲端檔的版本。
  final Map<String, ({String version, int edits})> _settled = {};

  /// 數書源、替換規則、書籤與標註改了幾次，給 [_settled] 判斷這台有沒有
  /// 改過；改了不自動同步，等下次全面同步。同步自己套用雲端的改動也算，
  /// 下次全面同步會整份比一次。
  void _watchEdits() {
    if (_edits.isNotEmpty) return;
    final db =
        _database ??
        (getIt.isRegistered<AppDatabase>() ? getIt<AppDatabase>() : null);
    if (db == null) return;
    for (final (table, kind) in <(TableInfo, String)>[
      (db.bookSources, SourceSync.kind),
      (db.replaceRules, ReplaceRuleSync.kind),
      (db.bookmarks, BookmarkSync.kind),
      (db.highlights, HighlightSync.kind),
    ]) {
      _localEdits[kind] = 0;
      _edits.add(
        db
            .tableUpdates(TableUpdateQuery.onTable(table))
            .listen((_) => _localEdits.update(kind, (count) => count + 1)),
      );
    }
  }

  /// 同步一輪：[full] 是全部種類，否則只有閱讀進度。
  Future<void> _syncOnce({required bool full}) async {
    final kindTimes = <String, int>{};
    try {
      await _lock.synchronized(() async {
        final store = await _store();
        if (store == null) return;
        status.value = status.value.copyWith(
          running: true,
          clearProgress: true,
        );
        // 換了同步空間就作廢上次同步的紀錄，只同步進度時也要。
        await _claimBases();
        // 一種資料失敗不擋其他種：都試過一次，再報第一個失敗。
        Object? failure;
        StackTrace? failureStack;
        // 排了兩次的種類，第二次只在中間有別種套用了改動時才跑。
        final appliedAfter = <String, bool>{};
        final kinds = full
            ? _kinds(this)
            : _kinds(this).whereType<ProgressSync>().take(1).toList();
        for (final (index, kind) in kinds.indexed) {
          // 取消在種類之間停：寫到一半的那一種做完，已經寫完的留著。
          if (full && _cancelled) return;
          if (appliedAfter[kind.name] == false) continue;
          appliedAfter[kind.name] = false;
          // 這一種讀這台資料的時候，要求優先送出的進度已經存好了。
          if (kind is ProgressSync) _progressFirst = false;
          status.value = status.value.copyWith(
            progress: (kind: kind.name, step: index + 1, total: kinds.length),
          );
          final kindTimer = Stopwatch()..start();
          try {
            if (await _syncKind(store, kind)) {
              appliedAfter.updateAll((name, _) => name != kind.name);
            }
          } catch (error, stackTrace) {
            // 整個空間用不了（連不上、授權失效）才停下；只有這一份檔案被
            // 拒絕（[SyncStoreException.file]），其他種類照常同步，最後仍
            // 報第一個失敗。
            if (error is SyncStoreException && error.wholeSpace) rethrow;
            AppLog.e(
              '同步 ${kind.name} 失敗',
              error: error,
              stackTrace: stackTrace,
            );
            failure ??= error;
            failureStack ??= stackTrace;
          } finally {
            kindTimes.update(
              kind.name,
              (elapsed) => elapsed + kindTimer.elapsedMilliseconds,
              ifAbsent: () => kindTimer.elapsedMilliseconds,
            );
            if (kind is ProgressSync) _progressDone();
          }
          if (_progressFirst) await _syncProgressAgain(store, kinds);
        }
        if (failure != null) {
          Error.throwWithStackTrace(failure, failureStack!);
        }
        if (!full) {
          status.value = status.value.copyWith(clearError: true);
          return;
        }
        // 「上次全面同步」只記全面同步：其他資料到這時才算同步過。
        final now = _clock();
        await _settings.setLastSyncAt(now);
        status.value = status.value.copyWith(lastSyncAt: now, clearError: true);
      });
    } catch (error, stackTrace) {
      AppLog.e('同步失敗', error: error, stackTrace: stackTrace);
      status.value = status.value.copyWith(error: _messageOf(error));
    } finally {
      if (kindTimes.values.any((ms) => ms >= 500)) {
        AppLog.i(
          '同步各類耗時（ms）：${kindTimes.entries.map((e) => '${e.key}=${e.value}').join('、')}',
        );
      }
    }
  }

  /// 同步途中有人要進度優先送出：把閱讀進度再同步一次，之後才接著做下一種。
  /// 失敗只記下來：這一輪本來就會報錯，下一次同步也還會再送。
  Future<void> _syncProgressAgain(SyncStore store, List<SyncKind> kinds) async {
    _progressFirst = false;
    final progress = kinds.whereType<ProgressSync>().firstOrNull;
    if (progress == null) return;
    try {
      await _syncKind(store, progress);
    } catch (error, stackTrace) {
      AppLog.e('優先同步閱讀進度失敗', error: error, stackTrace: stackTrace);
    }
  }

  static String _messageOf(Object error) => switch (error) {
    SyncStoreException(:final message) => message,
    FormatException() => '同步空間裡的檔案不是夜讀寫的，沒有動它',
    _ => '同步失敗',
  };

  /// 同步一種資料：讀雲端、每筆和上次同步時三方比對、寫回雲端，再把雲端
  /// 較新的套用到這台。傳回有沒有套用到這台。
  Future<bool> _syncKind(SyncStore store, SyncKind kind) async {
    final edits = _localEdits[kind.name];
    if (_settled[kind.name] case final last? when last.edits == edits) {
      final version = await store.version(kind.fileName);
      // 問版本的這段時間這台又改了，就照常整份比。
      if (version == last.version && _localEdits[kind.name] == edits) {
        return false;
      }
    }
    _settled.remove(kind.name);
    final fingerprint = kind.fingerprint;
    for (var attempt = 1; ; attempt++) {
      // 讀寫同步空間、讀這台的資料、套用在主執行緒；解 JSON、算指紋、比對
      // 與編碼在背景 isolate（ADR 0046）。
      final file = await store.read(kind.fileName);
      final remote = file == null
          ? <String, SyncRecord>{}
          : await decodeSyncFileOn(_runner, file.content, kind.prune);
      final base = await _bases.read(kind.name);
      final now = _clock().millisecondsSinceEpoch;
      SyncMergeInput inputFor(Map<String, SyncRecord> local) => SyncMergeInput(
        remote: remote,
        local: local,
        base: base,
        now: now,
        fingerprint: fingerprint,
        hasOwnTime: kind.hasOwnTime,
        syncsDeletion: kind.syncsDeletion,
      );
      final plan = await planSyncMergeOn(
        _runner,
        inputFor(await kind.reconcile(await kind.local(), remote, base)),
      );
      final nextBase = plan.base;
      final toApply = [
        for (final MapEntry(:key, value: (:mine, print: _))
            in plan.incoming.entries)
          if (kind.canApply(key, mine)) key,
      ];

      final changesRemote = plan.upload != null;
      if (plan.upload case final upload?) {
        try {
          // 試到最後一次仍被別台搶先，就不再比版本直接寫：寧可蓋掉別台
          // 剛寫的（下次同步會再合併回來），不讓同步一直失敗。
          final lastTry = attempt >= _maxAttempts;
          await store.write(
            kind.fileName,
            upload,
            ifVersion: lastTry ? null : file?.version,
            ifAbsent: !lastTry && file == null,
          );
        } on SyncConflict {
          continue;
        }
      }

      var appliedAny = false;
      if (toApply.isNotEmpty) {
        // 寫雲端的這段時間，這台可能又改了（書被打開讀了幾頁、書源剛編輯
        // 過）：和合併時不同的不套用，上次同步的紀錄留著，下次重新比。
        // 讀完馬上比，不交給背景 isolate：等它回覆的空檔裡使用者改的會被
        // 漏看、蓋掉。只算要套用的那幾筆。
        final fresh = inputFor(await kind.local());
        final ready = <String, SyncRecord>{
          for (final key in toApply)
            if (timedSyncRecordOf(fresh, key) case final current
                when _printOf(fingerprint, current) ==
                        plan.incoming[key]!.print &&
                    kind.canApply(key, current))
              key: remote[key]!,
        };
        final applied = ready.isEmpty
            ? const <String, SyncRecord>{}
            : await kind.apply(ready);
        appliedAny = applied.isNotEmpty;
        for (final MapEntry(:key, value: mine) in applied.entries) {
          final theirs = ready[key]!;
          nextBase[key] = SyncBaseEntry(
            local: fingerprint(mine),
            remote: fingerprint(theirs),
            time: theirs.time,
          );
        }
      }
      await _bases.write(kind.name, nextBase);
      if ((file?.version, edits) case (final version?, final edits?)
          when !changesRemote && toApply.isEmpty) {
        _settled[kind.name] = (version: version, edits: edits);
      }
      return appliedAny;
    }
  }

  static String? _printOf(SyncFingerprint fingerprint, SyncRecord? record) =>
      record == null ? null : fingerprint(record);

  /// 閱讀器開著、App 回到前景時抓這本書的雲端進度（整次同步不改開著的
  /// 書）：比這台的新才傳回，否則 null。連不上、沒設定同步空間也是 null，
  /// 閱讀器照常停在原處。
  ///
  /// 不等 [_lock]：回到前景時整次同步也在跑，這本書的進度不排在它後面。
  /// 這裡只讀不寫；寫上次同步的紀錄在 [PulledProgress.commit]，在鎖裡、
  /// 換過同步空間就不寫。
  Future<PulledProgress?> pullProgress(String bookUrl) async {
    try {
      final generation = _generation;
      final store = await _store();
      if (store == null) return null;
      final bookDao = _bookDao ?? getIt<BookDao>();
      final book = await bookDao.getByUrl(bookUrl);
      if (book == null) return null;
      final key = ProgressSync.keyOf(book);
      final file = await store.read(_progress.fileName);
      if (file == null) return null;
      final theirs = SyncDocument.decode(file.content).records[key];
      // 上次同步的紀錄是另一個同步空間的：當成從沒同步過，由下次同步作廢
      // 它（[_claimBases]）。
      final owned =
          (await _bases.readJson(_ownerFile))['space'] ==
          await _settings.identity();
      final base = owned
          ? await _bases.read(ProgressSync.kind)
          : const <String, SyncBaseEntry>{};
      final decision = decideSync(
        local: ProgressSync.recordOf(book),
        remote: theirs,
        base: base[key],
        fingerprint: ProgressSync.fingerprintOf,
      );
      if (decision != SyncDecision.apply ||
          theirs == null ||
          generation != _generation) {
        return null;
      }
      return PulledProgress(
        SyncedProgress.fromRecord(theirs),
        (applied) => _commitPulled(key, theirs, applied, generation),
        isCurrent: () => generation == _generation,
      );
    } catch (error, stackTrace) {
      AppLog.e('抓雲端進度失敗', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  /// 閱讀器跳到雲端的進度、存好之後：存下的那一筆（[applied]）記成和雲端那筆
  /// 同步過。用存下的那一筆、不重讀資料庫：等這把鎖的期間又讀了幾頁的話，
  /// 新的位置下次同步看得出是改過的。
  Future<void> _commitPulled(
    String key,
    SyncRecord theirs,
    SyncRecord applied,
    int generation,
  ) {
    return _lock.synchronized(() async {
      if (generation != _generation) return;
      final base = await _bases.read(ProgressSync.kind);
      base[key] = SyncBaseEntry(
        local: ProgressSync.fingerprintOf(applied),
        remote: ProgressSync.fingerprintOf(theirs),
        time: theirs.time,
      );
      await _bases.write(ProgressSync.kind, base);
    });
  }
}

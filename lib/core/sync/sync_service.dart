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

import 'bookshelf_sync.dart';
import 'login_data_sync.dart';
import 'progress_sync.dart';
import 'read_stats_sync.dart';
import 'replace_rule_sync.dart';
import 'settings_sync.dart';
import 'source_sync.dart';
import 'sync_base_storage.dart';
import 'sync_kind.dart';
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
  });

  final SyncSpace space;
  final bool running;
  final DateTime? lastSyncAt;

  /// 上次同步失敗的原因；成功一次就清掉。
  final String? error;

  bool get enabled => space != SyncSpace.none;

  SyncStatus copyWith({
    SyncSpace? space,
    bool? running,
    DateTime? lastSyncAt,
    String? error,
    bool clearError = false,
  }) => SyncStatus(
    space: space ?? this.space,
    running: running ?? this.running,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    error: clearError ? null : error ?? this.error,
  );
}

/// 閱讀器開書或回到前景時抓到、比這台新的進度。跳過去、存好位置之後，用
/// 存下的那一筆（[ProgressSync.recordOf]）呼叫 [commit]，把它記成和雲端那筆
/// 同步過，離開時不會再當成新的改動上傳；之後又讀了的話，和它比得出來。
/// 沒跳成（取不到那一章、被別的操作取代）就不要呼叫，下次還會再抓到。
class PulledProgress {
  PulledProgress(this.progress, this._commit);

  final SyncedProgress progress;
  final Future<void> Function(SyncRecord applied) _commit;

  Future<void> commit(SyncRecord applied) => _commit(applied);
}

/// 多台手機同步（ADR 0039）：每種資料（[SyncKind]）讀雲端、每筆合併、
/// 寫回。同一時間只跑一次；跑的途中又有人要同步，跑完再補一次。
class SyncService {
  SyncService({
    SyncSettings? settings,
    SyncBaseStorage? bases,
    SyncStore? Function(SyncSpace space, WebDavAccount? account)? storeFactory,
    this._bookDao,
    this._chapterDao,
    this._database,
    List<SyncKind> Function(SyncService service)? kinds,
    DateTime Function()? clock,
  }) : _settings = settings ?? SyncSettings(),
       _bases = bases ?? SyncBaseStorage(),
       _storeFactory = storeFactory ?? _defaultStore,
       _kinds = kinds ?? _defaultKinds,
       _clock = clock ?? DateTime.now;

  static SyncService instance = SyncService();

  final SyncSettings _settings;
  final SyncBaseStorage _bases;
  final SyncStore? Function(SyncSpace space, WebDavAccount? account)
  _storeFactory;
  final BookDao? _bookDao;
  final ChapterDao? _chapterDao;

  /// 看書源與替換規則有沒有改（[_watchEdits]）；沒給時用 App 的資料庫。
  final AppDatabase? _database;
  final List<SyncKind> Function(SyncService service) _kinds;
  final DateTime Function() _clock;
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

  static SyncStore? _defaultStore(SyncSpace space, WebDavAccount? account) {
    return switch (space) {
      SyncSpace.none => null,
      SyncSpace.webdav when account != null => WebDavSyncStore(
        url: account.url,
        user: account.user,
        password: account.password,
      ),
      SyncSpace.webdav => null,
    };
  }

  ProgressSync get _progress => ProgressSync(
    bookDao: _bookDao ?? getIt<BookDao>(),
    chapterDao: _chapterDao ?? getIt<ChapterDao>(),
    isOpen: isBookOpen,
  );

  /// 書名加作者是 [key] 的書正開在閱讀器裡（[openBook]）。
  bool isBookOpen(String key) => _openBooks.contains(key);

  /// 同步的順序：書源先到，書架上的書才找得到書源；書先加進書架，進度才
  /// 套用得上。
  static List<SyncKind> _defaultKinds(SyncService service) => [
    SourceSync(),
    ReplaceRuleSync(),
    BookshelfSync(isOpen: service.isBookOpen),
    service._progress,
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

  /// 目前設定的同步空間。只在 [_lock] 裡呼叫：讀設定到用完同步空間之間，
  /// 不會被停用或換帳號插進來，寫到已經不用的空間。
  Future<SyncStore?> _store() async {
    final space = await _settings.space();
    return _storeFactory(space, await _settings.webDavAccount());
  }

  /// 上次同步的紀錄屬於哪個同步空間的檔名。
  static const String _ownerFile = 'owner';

  /// 上次同步的紀錄是另一個同步空間的（還原備份直接改了同步設定，沒經過
  /// [useWebDav]），就全部作廢，照從沒同步過合併；不然會拿另一個空間的
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

  /// 改用 [account] 的 WebDAV：先試連，連得上才存起來、從頭同步一次。
  Future<void> useWebDav(WebDavAccount account) async {
    final store = _storeFactory(SyncSpace.webdav, account);
    await store!.check();
    await _lock.synchronized(() async {
      _generation++;
      _settled.clear();
      await _settings.useWebDav(account);
      await _bases.clear();
    });
    status.value = const SyncStatus(space: SyncSpace.webdav);
    await syncNow();
  }

  Future<void> disable() async {
    await _lock.synchronized(() async {
      _generation++;
      _settled.clear();
      await _settings.disable();
      await _bases.clear();
    });
    status.value = const SyncStatus();
  }

  void openBook(Book book) => _openBooks.add(ProgressSync.keyOf(book));

  void closeBook(Book book) => _openBooks.remove(ProgressSync.keyOf(book));

  /// 要同步一次，不等結果：正在同步時，跑完再補一次。
  void requestSync() => unawaited(syncNow());

  /// 同步一次，失敗記在 [status]、不丟出來。沒設定同步空間時什麼都不做。
  Future<void> syncNow() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final future = _runUntilSettled();
    _running = future;
    return future.whenComplete(() {
      _running = null;
      if (_editedWhileSyncing) {
        _editedWhileSyncing = false;
        _scheduleAfterEdit();
      }
    });
  }

  Future<void> _runUntilSettled() async {
    do {
      _again = false;
      await _syncOnce();
    } while (_again);
  }

  /// 開 App 進場播完時：讀出設定、同步第一次，之後書源或替換規則一改就
  /// 排一次同步。
  Future<void> start() async {
    try {
      await load();
    } catch (error, stackTrace) {
      AppLog.e('讀同步設定失敗', error: error, stackTrace: stackTrace);
      return;
    }
    _watchEdits();
    await syncNow();
  }

  final List<StreamSubscription<void>> _edits = [];
  Timer? _editTimer;
  bool _editedWhileSyncing = false;

  void _scheduleAfterEdit() {
    if (!status.value.enabled) return;
    _editTimer?.cancel();
    _editTimer = Timer(_editDelay, requestSync);
  }

  /// 改完隔多久同步：連續改好幾個（匯入、批次啟用）合併成一次。
  static const Duration _editDelay = Duration(seconds: 5);

  /// 這台改了幾次，鍵是 [SyncKind.name]；只數書源與替換規則（[_watchEdits]）。
  final Map<String, int> _localEdits = {};

  /// 上次同步時兩邊都沒變的種類：當時雲端檔的版本與這台改了幾次。之後兩邊
  /// 都還一樣，就不讀出整份來比（書源可能有幾百個，每次回到 App 都讀一遍
  /// 太重），只問一次雲端檔的版本。
  final Map<String, ({String version, int edits})> _settled = {};

  /// 書源與替換規則改了就排一次同步。書架與進度不看：讀書時每翻一頁都會
  /// 寫書，離開閱讀器與 App 退到背景時才同步；設定在 App 退到背景時同步。
  /// 同步自己套用雲端的改動時不排（那時正在同步），但照樣算改過，下次
  /// 同步會整份比一次。
  void _watchEdits() {
    if (_edits.isNotEmpty) return;
    final db =
        _database ??
        (getIt.isRegistered<AppDatabase>() ? getIt<AppDatabase>() : null);
    if (db == null) return;
    for (final (table, kind) in <(TableInfo, String)>[
      (db.bookSources, SourceSync.kind),
      (db.replaceRules, ReplaceRuleSync.kind),
    ]) {
      _localEdits[kind] = 0;
      _edits.add(
        db.tableUpdates(TableUpdateQuery.onTable(table)).listen((_) {
          _localEdits.update(kind, (count) => count + 1);
          // 同步途中改的（可能這一種已經同步過了），這輪結束再排一次；同步
          // 自己套用引起的也算，多的那次比不出差異、不寫雲端。
          if (_running != null) {
            _editedWhileSyncing = true;
          } else {
            _scheduleAfterEdit();
          }
        }),
      );
    }
  }

  Future<void> _syncOnce() async {
    try {
      await _lock.synchronized(() async {
        final store = await _store();
        if (store == null) return;
        await _claimBases();
        status.value = status.value.copyWith(running: true);
        // 一種資料失敗不擋其他種：都試過一次，再報第一個失敗。
        Object? failure;
        StackTrace? failureStack;
        for (final kind in _kinds(this)) {
          try {
            await _syncKind(store, kind);
          } on SyncStoreException {
            rethrow;
          } catch (error, stackTrace) {
            AppLog.e(
              '同步 ${kind.name} 失敗',
              error: error,
              stackTrace: stackTrace,
            );
            failure ??= error;
            failureStack ??= stackTrace;
          }
        }
        if (failure != null) {
          Error.throwWithStackTrace(failure, failureStack!);
        }
        final now = _clock();
        await _settings.setLastSyncAt(now);
        status.value = status.value.copyWith(
          running: false,
          lastSyncAt: now,
          clearError: true,
        );
      });
    } catch (error, stackTrace) {
      AppLog.e('同步失敗', error: error, stackTrace: stackTrace);
      status.value = status.value.copyWith(
        running: false,
        error: _messageOf(error),
      );
    }
  }

  static String _messageOf(Object error) => switch (error) {
    SyncStoreException(:final message) => message,
    FormatException() => '同步空間裡的檔案不是夜讀寫的，沒有動它',
    _ => '同步失敗',
  };

  /// 同步一種資料：讀雲端、每筆和上次同步時三方比對、寫回雲端，再把雲端
  /// 較新的套用到這台。
  Future<void> _syncKind(SyncStore store, SyncKind kind) async {
    final edits = _localEdits[kind.name];
    if (_settled[kind.name] case final last? when last.edits == edits) {
      final version = await store.version(kind.fileName);
      // 問版本的這段時間這台又改了，就照常整份比。
      if (version == last.version && _localEdits[kind.name] == edits) return;
    }
    _settled.remove(kind.name);
    final fingerprint = kind.fingerprint;
    for (var attempt = 1; ; attempt++) {
      final file = await store.read(kind.fileName);
      final remote = kind.prune(
        file == null
            ? <String, SyncRecord>{}
            : SyncDocument.decode(file.content).records,
      );
      final base = await _bases.read(kind.name);
      final now = _clock().millisecondsSinceEpoch;
      final local = _timed(
        kind,
        await kind.reconcile(await kind.local(), remote, base),
        remote,
        base,
        now,
      );

      final nextRemote = Map.of(remote);
      final nextBase = <String, SyncBaseEntry>{};
      final toApply = <String>[];
      for (final key in {...local.keys, ...remote.keys}) {
        final mine = local[key];
        final theirs = remote[key];
        switch (decideSync(
          local: mine,
          remote: theirs,
          base: base[key],
          fingerprint: fingerprint,
        )) {
          case SyncDecision.same:
            if (mine != null && theirs != null) {
              nextBase[key] = SyncBaseEntry(
                local: fingerprint(mine),
                remote: fingerprint(theirs),
                time: theirs.time,
              );
            } else if (base[key] case final kept?) {
              nextBase[key] = kept;
            }
          case SyncDecision.upload:
            nextRemote[key] = mine!;
            nextBase[key] = SyncBaseEntry(
              local: fingerprint(mine),
              remote: fingerprint(mine),
              time: mine.time,
            );
          case SyncDecision.apply:
            if (kind.canApply(key, mine)) toApply.add(key);
            if (base[key] case final kept?) nextBase[key] = kept;
        }
      }

      final changesRemote = !_sameRecords(remote, nextRemote);
      if (changesRemote) {
        try {
          // 試到最後一次仍被別台搶先，就不再比版本直接寫：寧可蓋掉別台
          // 剛寫的（下次同步會再合併回來），不讓同步一直失敗。
          final lastTry = attempt >= _maxAttempts;
          await store.write(
            kind.fileName,
            SyncDocument(nextRemote).encode(),
            ifVersion: lastTry ? null : file?.version,
            ifAbsent: !lastTry && file == null,
          );
        } on SyncConflict {
          continue;
        }
      }

      if (toApply.isNotEmpty) {
        // 寫雲端的這段時間，這台可能又改了（書被打開讀了幾頁、書源剛編輯
        // 過）：和合併時不同的不套用，上次同步的紀錄留著，下次重新比。
        final fresh = _timed(kind, await kind.local(), remote, base, now);
        final ready = <String, SyncRecord>{
          for (final key in toApply)
            if (_printOf(kind, fresh[key]) == _printOf(kind, local[key]) &&
                kind.canApply(key, fresh[key]))
              key: remote[key]!,
        };
        final applied = ready.isEmpty
            ? const <String, SyncRecord>{}
            : await kind.apply(ready);
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
      return;
    }
  }

  static String? _printOf(SyncKind kind, SyncRecord? record) =>
      record == null ? null : kind.fingerprint(record);

  /// 補上本機每筆的修改時間與刪除紀錄。有自己記時間的（[SyncKind.hasOwnTime]）
  /// 照原樣。其他的照上次同步的紀錄推算：
  ///
  /// - 和上次同步時一樣：沿用上次的時間。
  /// - 改過了（或上次之後才新增的）：算成這次同步的時間 [now]。
  /// - 從沒同步過、雲端也有同一筆：時間算 0，內容不同時雲端的贏。剛開始用
  ///   同步、或重裝後第一次同步的這台，不拿手上可能是舊的資料蓋掉雲端。
  /// - 上次同步時有、現在沒有：這台刪掉了，補一筆刪除紀錄讓別台跟著刪
  ///   （[SyncKind.syncsDeletion]）。
  static Map<String, SyncRecord> _timed(
    SyncKind kind,
    Map<String, SyncRecord> local,
    Map<String, SyncRecord> remote,
    Map<String, SyncBaseEntry> base,
    int now,
  ) {
    if (kind.hasOwnTime) return local;
    final timed = <String, SyncRecord>{};
    for (final MapEntry(:key, value: record) in local.entries) {
      final last = base[key];
      final time = switch (last) {
        null => remote.containsKey(key) ? 0 : now,
        _ when kind.fingerprint(record) == last.local => last.time,
        _ => now,
      };
      timed[key] = SyncRecord(
        time: time,
        data: record.data,
        deleted: record.deleted,
      );
    }
    if (kind.syncsDeletion) {
      for (final MapEntry(:key, value: last) in base.entries) {
        if (timed.containsKey(key)) continue;
        final gone = SyncRecord(time: now, data: const {}, deleted: true);
        timed[key] = kind.fingerprint(gone) == last.local
            ? SyncRecord(time: last.time, data: const {}, deleted: true)
            : gone;
      }
    }
    return timed;
  }

  static bool _sameRecords(
    Map<String, SyncRecord> a,
    Map<String, SyncRecord> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!identical(b[entry.key], entry.value)) return false;
    }
    return true;
  }

  /// 開書或回到前景時抓這本書的雲端進度：比這台的新才傳回，否則 null。
  /// 連不上、沒設定同步空間也是 null，閱讀器照常停在這台的位置。
  Future<PulledProgress?> pullProgress(String bookUrl) async {
    try {
      return await _lock.synchronized(() async {
        final store = await _store();
        if (store == null) return null;
        await _claimBases();
        final generation = _generation;
        final bookDao = _bookDao ?? getIt<BookDao>();
        final book = await bookDao.getByUrl(bookUrl);
        if (book == null) return null;
        final key = ProgressSync.keyOf(book);
        final file = await store.read(_progress.fileName);
        if (file == null) return null;
        final theirs = SyncDocument.decode(file.content).records[key];
        final base = await _bases.read(ProgressSync.kind);
        final decision = decideSync(
          local: ProgressSync.recordOf(book),
          remote: theirs,
          base: base[key],
          fingerprint: ProgressSync.fingerprintOf,
        );
        if (decision != SyncDecision.apply || theirs == null) return null;
        return PulledProgress(
          SyncedProgress.fromRecord(theirs),
          (applied) => _commitPulled(key, theirs, applied, generation),
        );
      });
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

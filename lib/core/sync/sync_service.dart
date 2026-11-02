import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:synchronized/synchronized.dart';

import 'progress_sync.dart';
import 'sync_base_storage.dart';
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

/// 多台手機同步（ADR 0039）：讀雲端、每筆合併、寫回。同一時間只跑一次；
/// 跑的途中又有人要同步，跑完再補一次。
class SyncService {
  SyncService({
    SyncSettings? settings,
    SyncBaseStorage? bases,
    SyncStore? Function(SyncSpace space, WebDavAccount? account)? storeFactory,
    this._bookDao,
    this._chapterDao,
    DateTime Function()? clock,
  }) : _settings = settings ?? SyncSettings(),
       _bases = bases ?? SyncBaseStorage(),
       _storeFactory = storeFactory ?? _defaultStore,
       _clock = clock ?? DateTime.now;

  static SyncService instance = SyncService();

  final SyncSettings _settings;
  final SyncBaseStorage _bases;
  final SyncStore? Function(SyncSpace space, WebDavAccount? account)
  _storeFactory;
  final BookDao? _bookDao;
  final ChapterDao? _chapterDao;
  final DateTime Function() _clock;
  final Lock _lock = Lock();

  /// 同一份檔案被別台同時寫入時，重讀再合併的次數。
  static const int _maxAttempts = 3;

  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus());

  /// 閱讀器開著的書：全部同步時不改這幾本的進度，由閱讀器自己跳。
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
  );

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

  /// 改用 [account] 的 WebDAV：先試連，連得上才存起來、從頭同步一次。
  Future<void> useWebDav(WebDavAccount account) async {
    final store = _storeFactory(SyncSpace.webdav, account);
    await store!.check();
    await _lock.synchronized(() async {
      _generation++;
      await _settings.useWebDav(account);
      await _bases.clear();
    });
    status.value = const SyncStatus(space: SyncSpace.webdav);
    await syncNow();
  }

  Future<void> disable() async {
    await _lock.synchronized(() async {
      _generation++;
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
    return future.whenComplete(() => _running = null);
  }

  Future<void> _runUntilSettled() async {
    do {
      _again = false;
      await _syncOnce();
    } while (_again);
  }

  /// 開 App 進場播完時：讀出設定、同步第一次。
  Future<void> start() async {
    try {
      await load();
    } catch (error, stackTrace) {
      AppLog.e('讀同步設定失敗', error: error, stackTrace: stackTrace);
      return;
    }
    await syncNow();
  }

  Future<void> _syncOnce() async {
    try {
      await _lock.synchronized(() async {
        final store = await _store();
        if (store == null) return;
        status.value = status.value.copyWith(running: true);
        await _syncProgress(store);
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

  Future<void> _syncProgress(SyncStore store) async {
    final progress = _progress;
    for (var attempt = 1; ; attempt++) {
      final file = await store.read(ProgressSync.fileName);
      final remote = file == null
          ? <String, SyncRecord>{}
          : SyncDocument.decode(file.content).records;
      final base = await _bases.read(ProgressSync.kind);
      final books = await progress.shelfBooks();
      final local = {
        for (final entry in books.entries)
          entry.key: ProgressSync.recordOf(entry.value),
      };

      const fingerprint = ProgressSync.fingerprint;
      final nextRemote = Map.of(remote);
      final nextBase = Map.of(base);
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
            }
          case SyncDecision.upload:
            nextRemote[key] = mine!;
            nextBase[key] = SyncBaseEntry(
              local: fingerprint(mine),
              remote: fingerprint(mine),
              time: mine.time,
            );
          case SyncDecision.apply:
            // 書不在這台的書架上就留在雲端；閱讀器開著的書由閱讀器自己跳。
            if (books.containsKey(key) && !_openBooks.contains(key)) {
              toApply.add(key);
            }
        }
      }

      if (!_sameRecords(remote, nextRemote)) {
        try {
          // 試到最後一次仍被別台搶先，就不再比版本直接寫：寧可蓋掉別台
          // 剛寫的（下次同步會再合併回來），不讓同步一直失敗。
          final lastTry = attempt >= _maxAttempts;
          await store.write(
            ProgressSync.fileName,
            SyncDocument(nextRemote).encode(),
            ifVersion: lastTry ? null : file?.version,
            ifAbsent: !lastTry && file == null,
          );
        } on SyncConflict {
          continue;
        }
      }

      for (final key in toApply) {
        // 寫雲端的這段時間，書可能被打開、讀了幾頁：這台的位置已經和合併時
        // 不同就不套用，上次同步的紀錄留著，下次同步重新比。
        if (_openBooks.contains(key)) continue;
        final current = await progress.bookDao.getByUrl(books[key]!.bookUrl);
        if (current == null ||
            fingerprint(ProgressSync.recordOf(current)) !=
                fingerprint(local[key]!)) {
          continue;
        }
        final theirs = remote[key]!;
        final applied = await progress.apply(current, theirs);
        nextBase[key] = SyncBaseEntry(
          local: fingerprint(applied),
          remote: fingerprint(theirs),
          time: theirs.time,
        );
      }
      await _bases.write(ProgressSync.kind, nextBase);
      return;
    }
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
        final generation = _generation;
        final bookDao = _bookDao ?? getIt<BookDao>();
        final book = await bookDao.getByUrl(bookUrl);
        if (book == null) return null;
        final key = ProgressSync.keyOf(book);
        final file = await store.read(ProgressSync.fileName);
        if (file == null) return null;
        final theirs = SyncDocument.decode(file.content).records[key];
        final base = await _bases.read(ProgressSync.kind);
        final decision = decideSync(
          local: ProgressSync.recordOf(book),
          remote: theirs,
          base: base[key],
          fingerprint: ProgressSync.fingerprint,
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
        local: ProgressSync.fingerprint(applied),
        remote: ProgressSync.fingerprint(theirs),
        time: theirs.time,
      );
      await _bases.write(ProgressSync.kind, base);
    });
  }
}

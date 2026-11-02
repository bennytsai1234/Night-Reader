import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_service.dart';

import 'reader_v2_location.dart';
import 'reader_v2_open_target.dart';
import 'reader_v2_runtime.dart';
import 'reader_v2_state.dart';

/// 閱讀器這一頭的進度同步（ADR 0039）：接著上次讀的地方開書時，開書的
/// 換頁動畫播放期間同時抓這本書的雲端進度，比這台新就直接開在那裡，不先
/// 排這台的位置再跳；回到前景時再抓一次。離開閱讀器、App 退到背景時把進度
/// 存好再上傳。
class ReaderV2ProgressSync {
  ReaderV2ProgressSync({
    required this.book,
    required this._runtime,
    required this._onJumped,
    required this._bookDao,
    ReaderV2OpenTarget? openTarget,
    SyncService? sync,
  }) : _resumes =
           openTarget == null || openTarget.intent == ReaderV2OpenIntent.resume,
       _sync = sync ?? SyncService.instance;

  /// 同一章裡差這麼多字以內不跳：多半是另一台螢幕大小不同、存的是畫面頂端
  /// 的那個字，跳了只是畫面抖一下。
  static const int nearChars = 100;

  /// 換頁動畫播完時雲端進度還沒回來，最多再等這麼久（期間畫面停在骨架）；
  /// 再晚就先開在這台的位置，回來後照回到前景的方式跳過去。
  static const Duration openGrace = Duration(milliseconds: 500);

  final Book book;
  final ReaderV2Runtime? Function() _runtime;

  /// 停到另一台的位置之後呼叫，[previous] 是這台原本的位置，給「回到原處」用。
  final void Function(ReaderV2Location previous) _onJumped;
  final BookDao _bookDao;
  final SyncService _sync;

  /// 接著上次讀的地方開書（不是從目錄或詳情點了某一章）：只有這時才照
  /// 另一台的進度開。
  final bool _resumes;

  Future<PulledProgress?>? _openPull;
  Future<Book?>? _stored;

  /// 開在另一台的位置時記下，開好後提示並記成已同步（[bookOpened]）。
  _OpenedAt? _openedAt;
  AppLifecycleListener? _lifecycle;
  bool _opened = false;
  bool _disposed = false;

  /// 閱讀器一建立就開始抓，和開書的換頁動畫同時進行；比的是開書前這台存的
  /// 位置。
  void start() {
    _sync.openBook(book);
    if (_resumes) {
      _openPull = _sync.pullProgress(book.bookUrl);
      _stored = _bookDao
          .getByUrl(book.bookUrl)
          .then<Book?>(
            (book) => book,
            onError: (Object error, StackTrace stackTrace) {
              AppLog.e('讀閱讀紀錄失敗', error: error, stackTrace: stackTrace);
              return null;
            },
          );
    }
    _lifecycle = AppLifecycleListener(onShow: _onShow, onHide: _onHide);
  }

  /// 換頁動畫播完、開書之前呼叫：要開在哪裡。null 就照原本要開的位置。
  ///
  /// 先看這台資料庫裡的紀錄：開書前背景同步可能已經套用了另一台的進度，
  /// 書架或詳情頁拿著的書還是舊的。再等雲端進度，最多 [openGrace]。
  Future<ReaderV2Location?> openLocation(ReaderV2Runtime runtime) async {
    final pull = _openPull;
    if (pull == null) return null;
    final opening = runtime.state.visibleLocation;
    final stored = await _stored;
    final storedAt = stored == null
        ? null
        : ReaderV2OpenTarget.resume(stored).location;
    final local = storedAt != null && !_samePlace(storedAt, opening)
        ? storedAt
        : null;
    final (arrived, pulled) = await _within(pull, openGrace);
    if (!arrived) return local;
    _openPull = null;
    if (pulled == null || _disposed || runtime.disposed) return local;
    try {
      // 章節要照這台的目錄對：開書本來就要讀目錄，這裡先讀好。
      await runtime.ensureChapters();
    } catch (_) {
      // 目錄取不到由開書接手處理；進度下次開書或回到前景再接。
      return local;
    }
    final from = local ?? opening;
    final (:target, :jumps) = _targetOf(pulled, from, runtime);
    _openedAt = _OpenedAt(pulled, from: from, target: target, jumps: jumps);
    return jumps ? target : local;
  }

  /// 開書定位完成時呼叫。
  Future<void> bookOpened() async {
    _opened = true;
    final runtime = _runtime();
    if (runtime == null) return;
    final openedAt = _openedAt;
    _openedAt = null;
    if (openedAt != null) {
      await _settle(
        openedAt.pulled,
        runtime,
        previous: openedAt.from,
        target: openedAt.target,
        jumped: openedAt.jumps,
      );
      return;
    }
    final pull = _openPull;
    _openPull = null;
    if (pull == null) return;
    final settled = runtime.state.visibleLocation;
    await _jumpIfStill(await pull, settled);
  }

  void _onShow() => unawaited(_pullAfterResume());

  Future<void> _pullAfterResume() async {
    final runtime = _runtime();
    if (!_opened || _disposed || runtime == null) return;
    await runtime.flushProgress();
    final since = runtime.state.visibleLocation;
    await _jumpIfStill(await _sync.pullProgress(book.bookUrl), since);
  }

  void _onHide() => _upload(_runtime());

  void _upload(ReaderV2Runtime? runtime) {
    final flushing = runtime == null || runtime.disposed
        ? Future<void>.value()
        : runtime.flushProgress();
    unawaited(
      flushing
          .then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              AppLog.e('存進度失敗', error: error, stackTrace: stackTrace);
            },
          )
          .whenComplete(_sync.requestSync),
    );
  }

  /// 抓到比這台新的進度、而且從 [since] 之後沒翻過頁，就跳過去。翻過頁的話
  /// 這台的位置比較新，離開時照常上傳。
  Future<void> _jumpIfStill(
    PulledProgress? pulled,
    ReaderV2Location since,
  ) async {
    final runtime = _runtime();
    if (pulled == null || !_isReady(runtime)) return;
    final current = runtime!.state.visibleLocation;
    if (!_samePlace(current, since)) return;
    final (:target, :jumps) = _targetOf(pulled, current, runtime);
    if (jumps) await runtime.jumpToLocation(target);
    await _settle(
      pulled,
      runtime,
      previous: current,
      target: target,
      jumped: jumps,
    );
  }

  /// 停到另一台的位置（[jumped]）或確認兩台差不多之後：存好位置、提示，
  /// 記成和雲端那筆同步過。
  Future<void> _settle(
    PulledProgress pulled,
    ReaderV2Runtime runtime, {
    required ReaderV2Location previous,
    required ReaderV2Location target,
    required bool jumped,
  }) async {
    // 那一章取不到（要登入、載入失敗）或被別的操作取代時，畫面停在這台的
    // 位置：不提示、不記成已同步，下次開書或回到前景再試。
    if (!_isReady(runtime) ||
        (jumped &&
            runtime.state.visibleLocation.chapterIndex !=
                target.chapterIndex)) {
      return;
    }
    await runtime.flushProgress();
    if (_disposed) return;
    if (jumped) _onJumped(previous);
    // 進度控制器存好後，記憶體裡的書就是存下的那一筆。
    await pulled.commit(ProgressSync.recordOf(book));
  }

  bool _isReady(ReaderV2Runtime? runtime) =>
      !_disposed &&
      runtime != null &&
      !runtime.disposed &&
      runtime.state.lifecycle == ReaderV2Lifecycle.ready;

  /// 雲端進度在這台目錄裡的位置，和要不要從 [from] 過去。
  static ({ReaderV2Location target, bool jumps}) _targetOf(
    PulledProgress pulled,
    ReaderV2Location from,
    ReaderV2Runtime runtime,
  ) {
    final index = pulled.progress.chapterIndexIn([
      for (var i = 0; i < runtime.chapterCount; i++) runtime.titleFor(i),
    ]);
    final target = ReaderV2Location(
      chapterIndex: index,
      charOffset: pulled.progress.charOffset,
    );
    final jumps =
        index != from.chapterIndex ||
        (target.charOffset - from.charOffset).abs() > nearChars;
    return (target: target, jumps: jumps);
  }

  static bool _samePlace(ReaderV2Location a, ReaderV2Location b) =>
      a.chapterIndex == b.chapterIndex && a.charOffset == b.charOffset;

  /// [pull] 在 [limit] 內回來就傳回 `(true, 結果)`，否則 `(false, null)`。
  static Future<(bool, PulledProgress?)> _within(
    Future<PulledProgress?> pull,
    Duration limit,
  ) {
    final result = Completer<(bool, PulledProgress?)>();
    final timer = Timer(limit, () {
      if (!result.isCompleted) result.complete((false, null));
    });
    unawaited(
      pull.then((pulled) {
        timer.cancel();
        if (!result.isCompleted) result.complete((true, pulled));
      }),
    );
    return result.future;
  }

  /// 閱讀器關掉時（在 runtime 釋放之前）呼叫：存好最後的位置再上傳。
  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    _sync.closeBook(book);
    _upload(_runtime());
  }
}

/// 開書時照另一台的進度決定的位置。
class _OpenedAt {
  _OpenedAt(
    this.pulled, {
    required this.from,
    required this.target,
    required this.jumps,
  });

  final PulledProgress pulled;

  /// 這台原本要開的位置。
  final ReaderV2Location from;
  final ReaderV2Location target;

  /// 和 [from] 差得夠遠，開在 [target]；否則開在 [from]。
  final bool jumps;
}

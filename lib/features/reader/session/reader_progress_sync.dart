import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/reading_upload_pacer.dart';
import 'package:night_reader/core/sync/sync_service.dart';

import 'reader_location.dart';
import 'reader_open_target.dart';
import 'reader_operation_token.dart';
import 'reader_runtime.dart';
import 'reader_state.dart';

/// 閱讀器這一頭的進度同步（ADR 0039）：雲端那筆比較新、而且讀到的地方在
/// 這台後面，才接。
/// - 接著上次讀的地方開書時，點書當下就先抓這本書的雲端進度；換頁動畫播完
///   最多等 [openGrace]：等到了而且比這台新，就照它開。等不及先照這台的位置
///   開；正文出現前（紙還蓋著）才到的直接改開在那裡，正文已經在畫面上之後
///   才到的先問要不要跳過去，不自己跳。從目錄或詳情點了某一章開書不抓。
/// - 讀到一半回到前景時再抓一次，比這台新、而且抓的途中沒翻頁就問要不要跳
///   過去；沒按就不跳、不記成同步過。跳到雲端那一筆的準確位置（章＋字），
///   位置完全一樣才不動。
/// - 讀書途中畫面停住時上傳（[ReadingUploadPacer]）；退到背景、離開閱讀器
///   時把進度存好再上傳。
class ReaderProgressSync {
  ReaderProgressSync({
    required this.book,
    required this._runtime,
    required this._onProgressSuggestion,
    required this._bookDao,
    ReaderOpenTarget? openTarget,
    SyncService? sync,
  }) : _resumes =
           openTarget == null || openTarget.intent == ReaderOpenIntent.resume,
       _sync = sync ?? SyncService.instance;

  /// 換頁動畫播完時雲端進度還沒抓到，最多再等這麼久（期間畫面停在骨架）；
  /// 再晚就照這台的位置開。
  static const Duration openGrace = Duration(milliseconds: 500);

  final Book book;
  final ReaderRuntime? Function() _runtime;

  /// 正文已經在畫面上之後才抓到比這台新的進度：交給頁面問要不要跳過去，
  /// 按了才執行傳進去的動作（會再確認讀者沒動過、還是同一筆）。
  final void Function(Future<void> Function() jump) _onProgressSuggestion;
  final BookDao _bookDao;
  final SyncService _sync;

  /// 接著上次讀的地方開書（不是從目錄或詳情點了某一章）：只有這時才照
  /// 同步來的進度開。
  final bool _resumes;

  AppLifecycleListener? _lifecycle;
  Timer? _graceTimer;
  Completer<bool>? _grace;

  /// 點書當下就開始抓的那一次；換頁動畫播完的 [openLocation] 改用它。
  Future<PulledProgress?>? _openingPull;

  /// 開書時等不及的那次抓取：進度晚到時，書已經開在這台的位置了。
  Future<PulledProgress?>? _lateProgress;

  /// 問過幾次要不要跳：換下一則之後，前一個按鈕按了也不動。
  int _suggestions = 0;
  bool _marked = false;
  bool _opened = false;
  bool _disposed = false;
  bool _foreground = true;

  late final ReadingUploadPacer _pacer = ReadingUploadPacer(
    upload: () => _upload(_runtime()),
    busy: () {
      final runtime = _runtime();
      return runtime == null ||
          runtime.pendingLocation != null ||
          runtime.state.lifecycle != ReaderLifecycle.ready;
    },
  );

  /// 這本書要換目錄了（改編碼）：不再上傳進度，關掉時也不存；換好之後由
  /// 新閱讀器接手。呼叫前先 flushProgress。
  bool _retired = false;

  void retire() {
    _retired = true;
    _pacer.stop();
    _sync.uploadsOnHide(this, false);
    _graceTimer?.cancel();
    _graceTimer = null;
    final grace = _grace;
    if (grace != null && !grace.isCompleted) grace.complete(false);
  }

  /// 換目錄失敗、閱讀器照舊時恢復。
  void resume() {
    _retired = false;
    _sync.uploadsOnHide(this, true);
    if (_opened && _foreground) _pacer.start();
  }

  void start() {
    // 照點的章節開書不抓，馬上記成開著，背景同步就不改這本。
    if (!_resumes) {
      _markOpen();
    } else {
      // 點書當下就開始抓，換頁動畫播完時直接用這一次，多賺動畫的時間。
      _openingPull ??= _sync.pullProgress(book.bookUrl);
    }
    _lifecycle = AppLifecycleListener(onShow: _onShow, onHide: _onHide);
    _sync.uploadsOnHide(this, true);
  }

  /// 記成開著：之後的同步不在背景改這本書，由閱讀器自己跳。
  void _markOpen() {
    if (_marked || _disposed) return;
    _marked = true;
    _sync.openBook(book);
  }

  /// 換頁動畫播完、開書之前呼叫：要開在哪裡。null 就照原本要開的位置。
  ///
  /// 先記成開著（背景的同步不再改這本），再抓這本書的雲端進度：等得到而且
  /// 比這台新，先寫進這台的資料庫。之後讀這台資料庫裡的位置：書架或詳情頁
  /// 拿著的書可能是同步套用之前的舊位置。
  Future<ReaderLocation?> openLocation(ReaderRuntime runtime) async {
    final at = await _openAt(runtime);
    final late = _lateProgress;
    // 比 [bookOpened] 的 [_catchUp] 先登記：抓到時正文還沒出現，就由這裡
    // 直接開過去。
    if (late != null) {
      unawaited(
        _openAtLate(late, runtime, at ?? runtime.state.visibleLocation),
      );
    }
    return at;
  }

  Future<ReaderLocation?> _openAt(ReaderRuntime runtime) async {
    if (!_resumes) return null;
    _markOpen();
    final pulling = _openingPull ?? _sync.pullProgress(book.bookUrl);
    _openingPull = null;
    if (await _within(pulling, openGrace)) {
      if (_disposed || runtime.disposed) return null;
      try {
        await (await pulling)?.applyBeforeOpen();
      } catch (error, stackTrace) {
        AppLog.e('接上雲端進度失敗', error: error, stackTrace: stackTrace);
      }
    } else {
      _lateProgress = pulling;
    }
    if (_disposed || runtime.disposed) return null;
    final Book? stored;
    try {
      stored = await _bookDao.getByUrl(book.bookUrl);
    } catch (error, stackTrace) {
      AppLog.e('讀閱讀紀錄失敗', error: error, stackTrace: stackTrace);
      return null;
    }
    if (stored == null) return null;
    // 記憶體裡的書之後可能整筆寫回資料庫，位置移動的時間要跟著。
    book.progressTime = stored.progressTime;
    final at = ReaderOpenTarget.resume(stored).location;
    final current = runtime.state.visibleLocation;
    return at == current &&
            at.contentHash == current.contentHash &&
            at.contentLength == current.contentLength &&
            at.anchorBefore == current.anchorBefore &&
            at.anchorAfter == current.anchorAfter
        ? null
        : at;
  }

  /// 開書定位完成時呼叫。
  void bookOpened() {
    _opened = true;
    if (_retired) return;
    _markOpen();
    final runtime = _runtime();
    if (runtime != null && !runtime.disposed) {
      runtime.progressController
        ..onActivity = _pacer.activity
        ..onMoved = _pacer.moved;
    }
    if (_foreground) _pacer.start();
    final late = _lateProgress;
    _lateProgress = null;
    if (late != null) unawaited(_catchUp(late));
  }

  /// 開書等不及的那次抓取在正文出現前到了（紙還蓋著）：讀者沒跳章、沒改
  /// 排版，雲端那一筆又在要開的位置 [opening] 後面，就直接改開在那裡，不問。
  /// 通常是開書正在排，由這次跳轉接手；開書還沒開始時開書直接開在那裡。
  /// 正文已經出現、讀者動過、還沒有目錄可以換算，或那一章是付費章節時不動，
  /// 交給 [_catchUp]。
  Future<void> _openAtLate(
    Future<PulledProgress?> pulling,
    ReaderRuntime runtime,
    ReaderLocation opening,
  ) async {
    final PulledProgress? pulled;
    try {
      pulled = await pulling;
    } catch (_) {
      return;
    }
    if (pulled == null ||
        !pulled.isCurrent ||
        _disposed ||
        _retired ||
        runtime.disposed ||
        runtime.state.lifecycle != ReaderLifecycle.cold ||
        runtime.chapterCount <= 0) {
      return;
    }
    final operation = runtime.stateMachine.currentOperation;
    if (operation != null && operation.kind != ReaderOperationKind.open) {
      return;
    }
    if (!identical(_lateProgress, pulling)) return;
    final target = _targetOf(pulled, runtime);
    // 點書當下抓的，背景那輪同步可能在換頁動畫期間已經把這台推到更後面；
    // 付費章節照開書的規則改開最近的免費章，不自己跳過去。
    if (!_isAhead(target, opening) ||
        (runtime.chapterAt(target.chapterIndex)?.isLocked ?? false)) {
      return;
    }
    _lateProgress = null;
    // 那一章取不到時開書回到這台的位置：不記成同步過，下次回到前景再抓。
    if (!await _jumpTo(runtime, target)) return;
    await _recordSynced(pulled);
  }

  /// 開書時雲端進度還沒抓到、先照這台的位置開了：抓到時讀者還沒動就問
  /// 要不要跳過去。
  Future<void> _catchUp(Future<PulledProgress?> pulling) async {
    final since = _runtime()?.state.visibleLocation;
    if (since == null) return;
    await _offerCatchUp(await pulling, since);
  }

  void _onShow() {
    _foreground = true;
    if (_opened && !_retired && !_disposed) _pacer.start();
    unawaited(_pullAfterResume());
  }

  Future<void> _pullAfterResume() async {
    final runtime = _runtime();
    if (!_opened || _disposed || _retired || runtime == null) return;
    try {
      await runtime.flushProgress();
    } catch (error, stackTrace) {
      AppLog.e('存進度失敗', error: error, stackTrace: stackTrace);
    }
    final since = runtime.state.visibleLocation;
    await _offerCatchUp(await _sync.pullProgress(book.bookUrl), since);
  }

  void _onHide() {
    _foreground = false;
    _pacer.stop();
    if (_retired) return;
    _upload(_runtime());
  }

  void _upload(ReaderRuntime? runtime) {
    if (_retired) return;
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
          .whenComplete(_sync.requestSyncProgressFirst),
    );
  }

  /// 正文已經在畫面上才抓到比這台新的進度：位置一樣就照舊記成同步過；
  /// 不一樣就先問要不要跳過去，不自己跳。
  Future<void> _offerCatchUp(
    PulledProgress? pulled,
    ReaderLocation since,
  ) async {
    final runtime = _runtime();
    if (pulled == null || !pulled.isCurrent || !_isReady(runtime)) return;
    final current = runtime!.state.visibleLocation;
    if (!_samePlace(current, since)) return;
    final target = _targetOf(pulled, runtime);
    if (_samePlace(target, current)) {
      await _jumpIfStill(pulled, since);
      return;
    }
    // 抓的時候比的是當時存著的位置；在這台前面的不問，免得把人往回帶。
    if (!_isAhead(target, current)) return;
    final suggestion = ++_suggestions;
    _onProgressSuggestion(() async {
      // 換過一則提示（讀者又動了、回到前景又抓到）：前一個按鈕不再有用。
      if (suggestion != _suggestions) return;
      await _jumpIfStill(pulled, since);
    });
  }

  /// 按了「跳過去」：讀者從 [since] 之後沒翻過頁、還是同一筆、同一個同步
  /// 空間，就跳到它的準確位置，存好、記成同步過。
  Future<void> _jumpIfStill(
    PulledProgress? pulled,
    ReaderLocation since,
  ) async {
    final runtime = _runtime();
    if (pulled == null || !pulled.isCurrent || !_isReady(runtime)) return;
    final current = runtime!.state.visibleLocation;
    if (!_samePlace(current, since)) return;
    final target = _targetOf(pulled, runtime);
    if (!_samePlace(target, current) && !await _jumpTo(runtime, target)) {
      return;
    }
    await _recordSynced(pulled);
  }

  /// 跳到 [target]，傳回有沒有落在那裡、閱讀器也排好了。沒定位到目標（那
  /// 一章取不到、使用者自己捲動而作廢、被別的操作取代）時，跳轉照樣正常
  /// 結束、畫面留在原處：不記成已同步，下次回到前景再試。同一章內的跳轉也
  /// 一樣，不能只看章節序號。
  Future<bool> _jumpTo(ReaderRuntime runtime, ReaderLocation target) async {
    try {
      return await runtime.jumpToLocation(target) && _isReady(runtime);
    } catch (error, stackTrace) {
      // 跳過去存不成就不記成同步過，下次回到前景還會再抓到。
      AppLog.e('存進度失敗', error: error, stackTrace: stackTrace);
      return false;
    }
  }

  /// 雲端那一筆在這台目錄的位置（章＋字）。
  ReaderLocation _targetOf(PulledProgress pulled, ReaderRuntime runtime) =>
      ReaderLocation(
        chapterIndex: pulled.progress.chapterIndexIn([
          for (var i = 0; i < runtime.chapterCount; i++) runtime.titleFor(i),
        ], reversed: book.getReverseToc()),
        charOffset: pulled.progress.charOffset,
      );

  /// 已經落在雲端那一筆的位置：存好、記成同步過。
  Future<void> _recordSynced(PulledProgress pulled) async {
    final runtime = _runtime();
    if (!_isReady(runtime) || _retired) return;
    try {
      await runtime!.flushProgress();
      // 換目錄（改編碼）時存不進去，不能記成同步過。
      if (_disposed || _retired) return;
      // 跳轉存檔記的是這台的時間；記成不比雲端那一筆早，之後往前讀的才比
      // 另一台記的新（`BookDao.markProgressSynced`）。
      final time = await _bookDao.markProgressSynced(
        book.bookUrl,
        syncedTime: pulled.progress.time,
      );
      if (time == null || _disposed) return;
      book.progressTime = time;
    } catch (error, stackTrace) {
      // 存不成就不記成同步過，下次回到前景還會再抓到。
      AppLog.e('存進度失敗', error: error, stackTrace: stackTrace);
      return;
    }
    // 進度控制器存好後，記憶體裡的書就是存下的那一筆。
    await pulled.commit(ProgressSync.recordOf(book));
  }

  bool _isReady(ReaderRuntime? runtime) =>
      !_disposed &&
      runtime != null &&
      !runtime.disposed &&
      runtime.state.lifecycle == ReaderLifecycle.ready;

  static bool _samePlace(ReaderLocation a, ReaderLocation b) =>
      a.chapterIndex == b.chapterIndex && a.charOffset == b.charOffset;

  /// [a] 在 [b] 後面（閱讀順序）：章在後面，或同一章的字數更多；同
  /// `ProgressSync.isAhead`。
  static bool _isAhead(ReaderLocation a, ReaderLocation b) =>
      a.chapterIndex > b.chapterIndex ||
      (a.chapterIndex == b.chapterIndex && a.charOffset > b.charOffset);

  /// 等 [future]，最多 [limit]；傳回它有沒有在時限內完成。閱讀器關掉時馬上
  /// 結束（傳回 false）。
  Future<bool> _within(Future<Object?> future, Duration limit) {
    final grace = _grace = Completer<bool>();
    void finish(bool done) {
      _graceTimer?.cancel();
      _graceTimer = null;
      if (!grace.isCompleted) grace.complete(done);
    }

    _graceTimer = Timer(limit, () => finish(false));
    unawaited(
      future
          .then<void>((_) {}, onError: (_) {})
          .whenComplete(() => finish(true)),
    );
    return grace.future;
  }

  /// 閱讀器關掉時（在 runtime 釋放之前）呼叫：存好最後的位置再上傳。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pacer.dispose();
    _graceTimer?.cancel();
    _graceTimer = null;
    final grace = _grace;
    if (grace != null && !grace.isCompleted) grace.complete(false);
    _lifecycle?.dispose();
    final runtime = _runtime();
    if (runtime != null) {
      runtime.progressController
        ..onActivity = null
        ..onMoved = null;
    }
    _sync.uploadsOnHide(this, false);
    // 換目錄（改編碼）時是由新的閱讀器接手，舊的不能再把這本書記成關掉，
    // 否則新閱讀器開著、背景同步卻會改它。
    if (_marked && !_retired) _sync.closeBook(book);
    if (!_retired) _upload(_runtime());
  }
}

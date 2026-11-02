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

/// 閱讀器這一頭的進度同步（ADR 0039）。同步在開 App 與回到 App 時做，
/// 開書不連網：接著上次讀的地方開書時，那次同步的閱讀進度還沒做完就等它
/// （最多 [openGrace]），再照這台資料庫裡的位置開，書就在另一台讀到的地方。
/// 等不及的話先照這台的位置開，進度晚到時讀者還沒動就跳過去。
/// 讀書途中 App 回到前景時抓這本書的雲端進度，比這台新就跳過去。離開閱讀
/// 器、App 退到背景時把進度存好再上傳。
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

  /// 換頁動畫播完時同步的閱讀進度還沒做完，最多再等這麼久（期間畫面停在
  /// 骨架）；再晚就照這台的位置開。
  static const Duration openGrace = Duration(milliseconds: 500);

  final Book book;
  final ReaderV2Runtime? Function() _runtime;

  /// 跳到另一台的位置之後呼叫，[previous] 是跳之前的位置，給「回到原處」用。
  final void Function(ReaderV2Location previous) _onJumped;
  final BookDao _bookDao;
  final SyncService _sync;

  /// 接著上次讀的地方開書（不是從目錄或詳情點了某一章）：只有這時才照
  /// 同步來的進度開。
  final bool _resumes;

  AppLifecycleListener? _lifecycle;
  Timer? _graceTimer;
  Completer<bool>? _grace;

  /// 開書時等不及的那次同步：進度晚到時，書已經開在這台的舊位置了。
  Future<void>? _lateProgress;
  bool _marked = false;
  bool _opened = false;
  bool _disposed = false;

  void start() {
    // 照點的章節開書不等同步，馬上記成開著，背景同步就不改這本。
    if (!_resumes) _markOpen();
    _lifecycle = AppLifecycleListener(onShow: _onShow, onHide: _onHide);
  }

  /// 記成開著：之後的同步不在背景改這本書，由閱讀器自己跳。
  void _markOpen() {
    if (_marked || _disposed) return;
    _marked = true;
    _sync.openBook(book);
  }

  /// 換頁動畫播完、開書之前呼叫：要開在哪裡。null 就照原本要開的位置。
  ///
  /// 開 App 或回到 App 的同步還沒做完閱讀進度就等它，記成開著之後再讀這台
  /// 資料庫裡的位置：書架或詳情頁拿著的書可能是同步套用之前的舊位置。
  Future<ReaderV2Location?> openLocation(ReaderV2Runtime runtime) async {
    if (!_resumes) return null;
    final ready = _sync.progressReady;
    if (ready != null && !await _within(ready, openGrace)) {
      _lateProgress = ready;
    }
    if (_disposed || runtime.disposed) return null;
    _markOpen();
    final Book? stored;
    try {
      stored = await _bookDao.getByUrl(book.bookUrl);
    } catch (error, stackTrace) {
      AppLog.e('讀閱讀紀錄失敗', error: error, stackTrace: stackTrace);
      return null;
    }
    if (stored == null) return null;
    final at = ReaderV2OpenTarget.resume(stored).location;
    return _samePlace(at, runtime.state.visibleLocation) ? null : at;
  }

  /// 開書定位完成時呼叫。
  void bookOpened() {
    _opened = true;
    _markOpen();
    final late = _lateProgress;
    _lateProgress = null;
    if (late != null) unawaited(_catchUp(late));
  }

  /// 開書時進度還沒同步完、先照這台的位置開了：等那次同步做完，讀者還沒
  /// 動就跳到另一台的位置。這本書已經記成開著，背景同步不會改它，不接的話
  /// 要等下次回到前景才接得上；讀者已經翻頁或捲動的話，這台的位置比較新，
  /// 不蓋掉。
  Future<void> _catchUp(Future<void> syncing) async {
    final since = _runtime()?.state.visibleLocation;
    if (since == null) return;
    await syncing;
    final runtime = _runtime();
    if (!_isReady(runtime) ||
        !_samePlace(runtime!.state.visibleLocation, since)) {
      return;
    }
    await _jumpIfStill(await _sync.pullProgress(book.bookUrl), since);
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
          .whenComplete(_sync.requestSyncProgressFirst),
    );
  }

  /// 抓到比這台新的進度、而且從 [since] 之後沒翻過頁，就跳過去。翻過頁的話
  /// 這台的位置比較新，離開時照常上傳。
  Future<void> _jumpIfStill(
    PulledProgress? pulled,
    ReaderV2Location since,
  ) async {
    final runtime = _runtime();
    if (pulled == null || !pulled.isCurrent || !_isReady(runtime)) return;
    final current = runtime!.state.visibleLocation;
    if (!_samePlace(current, since)) return;
    final index = pulled.progress.chapterIndexIn([
      for (var i = 0; i < runtime.chapterCount; i++) runtime.titleFor(i),
    ]);
    final target = ReaderV2Location(
      chapterIndex: index,
      charOffset: pulled.progress.charOffset,
    );
    final jumps =
        index != current.chapterIndex ||
        (target.charOffset - current.charOffset).abs() > nearChars;
    if (jumps) {
      final reached = await runtime.jumpToLocation(target);
      // 沒定位到目標（那一章取不到、使用者自己捲動而作廢、被別的操作取代）
      // 時，跳轉照樣正常結束、畫面留在原處：不提示、不記成已同步，下次回到
      // 前景再試。同一章內的跳轉也一樣，不能只看章節序號。
      if (!reached || !_isReady(runtime)) return;
    }
    await runtime.flushProgress();
    if (_disposed) return;
    if (jumps) _onJumped(current);
    // 進度控制器存好後，記憶體裡的書就是存下的那一筆。
    await pulled.commit(ProgressSync.recordOf(book));
  }

  bool _isReady(ReaderV2Runtime? runtime) =>
      !_disposed &&
      runtime != null &&
      !runtime.disposed &&
      runtime.state.lifecycle == ReaderV2Lifecycle.ready;

  static bool _samePlace(ReaderV2Location a, ReaderV2Location b) =>
      a.chapterIndex == b.chapterIndex && a.charOffset == b.charOffset;

  /// 等 [future]，最多 [limit]；傳回它有沒有在時限內完成。閱讀器關掉時馬上
  /// 結束（傳回 false）。
  Future<bool> _within(Future<void> future, Duration limit) {
    final grace = _grace = Completer<bool>();
    void finish(bool done) {
      _graceTimer?.cancel();
      _graceTimer = null;
      if (!grace.isCompleted) grace.complete(done);
    }

    _graceTimer = Timer(limit, () => finish(false));
    unawaited(future.whenComplete(() => finish(true)));
    return grace.future;
  }

  /// 閱讀器關掉時（在 runtime 釋放之前）呼叫：存好最後的位置再上傳。
  void dispose() {
    _disposed = true;
    _graceTimer?.cancel();
    _graceTimer = null;
    final grace = _grace;
    if (grace != null && !grace.isCompleted) grace.complete(false);
    _lifecycle?.dispose();
    if (_marked) _sync.closeBook(book);
    _upload(_runtime());
  }
}

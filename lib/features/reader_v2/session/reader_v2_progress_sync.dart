import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_service.dart';

import 'reader_v2_location.dart';
import 'reader_v2_runtime.dart';
import 'reader_v2_state.dart';

/// 閱讀器這一頭的進度同步（ADR 0039）：開書時抓這本書的雲端進度，比這台新、
/// 而且還沒翻頁就直接跳過去；回到前景時再抓一次。離開閱讀器、App 退到背景
/// 時把進度存好再上傳。
class ReaderV2ProgressSync {
  ReaderV2ProgressSync({
    required this.book,
    required this._runtime,
    required this._onJumped,
    SyncService? sync,
  }) : _sync = sync ?? SyncService.instance;

  /// 同一章裡差這麼多字以內不跳：多半是另一台螢幕大小不同、存的是畫面頂端
  /// 的那個字，跳了只是畫面抖一下。
  static const int nearChars = 100;

  final Book book;
  final ReaderV2Runtime? Function() _runtime;

  /// 跳過去之後呼叫，[previous] 是跳之前的位置，給「回到原處」用。
  final void Function(ReaderV2Location previous) _onJumped;
  final SyncService _sync;

  Future<PulledProgress?>? _openPull;
  AppLifecycleListener? _lifecycle;
  bool _opened = false;
  bool _disposed = false;

  /// 閱讀器一建立就開始抓，和開書的換頁動畫、載入同時進行；比的是開書前
  /// 這台存的位置。
  void start() {
    _sync.openBook(book);
    _openPull = _sync.pullProgress(book.bookUrl);
    _lifecycle = AppLifecycleListener(onShow: _onShow, onHide: _onHide);
  }

  /// 開書定位完成時呼叫。
  Future<void> bookOpened() async {
    _opened = true;
    final pull = _openPull;
    _openPull = null;
    final runtime = _runtime();
    if (pull == null || runtime == null) return;
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
    if (pulled == null ||
        _disposed ||
        runtime == null ||
        runtime.disposed ||
        runtime.state.lifecycle != ReaderV2Lifecycle.ready) {
      return;
    }
    final current = runtime.state.visibleLocation;
    if (current.chapterIndex != since.chapterIndex ||
        current.charOffset != since.charOffset) {
      return;
    }
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
      await runtime.jumpToLocation(target);
      // 那一章取不到（要登入、載入失敗）或被別的操作取代時，跳轉照樣正常
      // 結束、畫面留在原處：不提示、不記成已同步，下次開書或回到前景再試。
      if (_disposed ||
          runtime.disposed ||
          runtime.state.lifecycle != ReaderV2Lifecycle.ready ||
          runtime.state.visibleLocation.chapterIndex != index) {
        return;
      }
    }
    await runtime.flushProgress();
    if (_disposed) return;
    if (jumps) _onJumped(current);
    // 進度控制器存好後，記憶體裡的書就是存下的那一筆。
    await pulled.commit(ProgressSync.recordOf(book));
  }

  /// 閱讀器關掉時（在 runtime 釋放之前）呼叫：存好最後的位置再上傳。
  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    _sync.closeBook(book);
    _upload(_runtime());
  }
}

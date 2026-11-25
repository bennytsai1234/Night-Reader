import 'dart:async';

import 'package:night_reader/core/diagnostics/app_log_service.dart';

/// 合併短時間內的進度變更，但持續移動時也定期存檔。
/// 同一個閱讀器的寫入依序完成。[saveImmediately] 與計時器只寫正在寫的那筆
/// 之後的最新一筆，寫入途中才排的位置交給計時器，不追著持續移動連寫；
/// [flush]（離開、退背景）一路寫到沒有待寫的位置為止。
class ProgressWriteQueue<T extends Object> {
  ProgressWriteQueue({
    required this.write,
    this.debounce = const Duration(milliseconds: 400),
    this.maxWait = const Duration(seconds: 2),
  });

  final Future<void> Function(T) write;
  final Duration debounce;
  final Duration maxWait;

  Timer? _idleTimer;
  Timer? _deadlineTimer;
  T? _pending;
  Future<void>? _active;
  int _discardGeneration = 0;

  void schedule(T value) {
    _pending = value;
    _idleTimer?.cancel();
    _idleTimer = Timer(debounce, _checkpoint);
    _deadlineTimer ??= Timer(maxWait, _checkpoint);
  }

  Future<void> saveImmediately(T value) {
    _pending = value;
    return _flush(drain: false);
  }

  Future<void> flush() => _flush(drain: true);

  void flushInBackground() {
    _observe(flush());
  }

  void _checkpoint() {
    _observe(_flush(drain: false));
  }

  void _observe(Future<void> future) {
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          AppLog.e('存進度失敗', error: error, stackTrace: stackTrace);
        },
      ),
    );
  }

  Future<void> _flush({required bool drain}) {
    _cancelTimers();
    final active = _active;
    if (active != null) {
      return active.then((_) => _flush(drain: drain));
    }
    final pending = _pending;
    if (pending == null) return Future<void>.value();
    _pending = null;
    final generation = _discardGeneration;
    final saving = _writeOne(pending, generation).whenComplete(() {
      _active = null;
    });
    _active = saving;
    return drain ? saving.then((_) => _flush(drain: true)) : saving;
  }

  Future<void> _writeOne(T value, int generation) async {
    try {
      await write(value);
    } catch (_) {
      // 有較新的位置時不讓失敗的舊位置蓋過它。
      if (generation == _discardGeneration) _pending ??= value;
      rethrow;
    }
  }

  void discardPending() {
    _discardGeneration++;
    _cancelTimers();
    _pending = null;
  }

  void _cancelTimers() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
  }
}

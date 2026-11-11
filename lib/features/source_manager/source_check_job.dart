import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/background_work/background_work.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/shared/navigation/root_navigator.dart';

import 'ai_repair/repair_runs.dart' show backgroundWorkStopping;
import 'source_manager_page.dart';

/// 從書源管理按下去的校驗（「校驗所有書源」「校驗選中」）：離開夜讀也繼續，
/// 通知欄顯示進度（ADR 0058）。登入完自動校驗一個、整批修復裡的重新校驗
/// 不經過這裡。
class SourceCheckJob implements BackgroundJob {
  SourceCheckJob({
    required this._changes,
    required this._done,
    required this._total,
    required this._cancel,
    BackgroundWork? work,
    NavigatorState? Function()? navigator,
  }) : _work = work ?? BackgroundWork.instance,
       _navigator = navigator ?? (() => rootNavigatorKey.currentState);

  /// 照 [CheckSourceService] 的進度。
  SourceCheckJob.of(CheckSourceService service)
    : this(
        changes: service,
        done: () => service.currentCount,
        total: () => service.totalCount,
        cancel: service.cancel,
      );

  final Listenable _changes;
  final int Function() _done;
  final int Function() _total;
  final VoidCallback _cancel;
  final BackgroundWork _work;
  final NavigatorState? Function() _navigator;
  bool _stopping = false;

  BackgroundWorkStatus get status {
    final total = _total();
    final done = _done();
    return BackgroundWorkStatus(
      title: '校驗書源',
      text: _stopping ? backgroundWorkStopping : '第 $done／$total 個',
      progress: total > 0 ? done / total : 0,
    );
  }

  /// 跑 [check]（裡面呼叫 [CheckSourceService.check]），跑的時候佔著背景
  /// 工作的位置、更新通知。
  Future<void> run(Future<void> Function() check) async {
    // 一次一件（ADR 0058）：入口已經擋住，這裡是最後一道。
    if (!_work.begin(this, status)) return;
    void update() => _work.update(this, status);
    _changes.addListener(update);
    try {
      await check();
    } finally {
      _changes.removeListener(update);
      _work.end(this);
    }
  }

  @override
  void stopFromSystem() {
    if (_stopping) return;
    _stopping = true;
    _work.update(this, status);
    _cancel();
  }

  /// 回到書源管理：校驗的結果在那裡（頁首下的狀態列與校驗標記）。
  @override
  void openFromNotification() {
    if (SourceManagerPage.isShowing) return;
    final navigator = _navigator();
    if (navigator == null) return;
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const SourceManagerPage()),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/ai_find/ai_find_session.dart';
import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/ai_find_record.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/background_work/background_work.dart';
import 'package:night_reader/features/source_manager/ai_repair/repair_runs.dart';

import 'ai_find_page.dart';

/// 正在跑、或做完還沒看過結果的那一次找書：搜尋頁的 ✦ 照它決定推回同一次
/// 還是開新的（docs/design/screens.md「AI 找書」）。和修書源分開放：找書的
/// 結果存成「過去的找書」，沒看過也不擋修書源；一次一件由背景工作的位置管
/// （ADR 0058）。
final RepairRuns aiFindRuns = RepairRuns();

/// 一次 AI 找書的背景工作（ADR 0058 的第四件）：頁面關了照跑，通知欄標題
/// 「AI 找書」、內文是最新一輪的副標，點了回那一頁。結束（含停止、沒找完）
/// 就存成「過去的找書」的一筆。
class AiFindRun extends RepairRun {
  AiFindRun(
    this.session, {
    Future<void> Function(AiFindRecord record)? save,
    super.work,
    super.navigator,
  }) : _save = save ?? ((record) => getIt<AiFindDao>().upsert(record)) {
    session.addListener(changed);
  }

  final AiFindSession session;

  /// 存成「過去的找書」；沒給時存進資料庫（測試換掉它）。
  final Future<void> Function(AiFindRecord record) _save;

  @override
  BackgroundWorkStatus get status {
    final round = session.rounds.lastOrNull;
    final detail = (round?.detail ?? '').trim();
    return BackgroundWorkStatus(
      title: 'AI 找書',
      text: session.isStopped
          ? backgroundWorkStopping
          : detail.isNotEmpty
          ? detail
          : round?.title ?? '準備中…',
    );
  }

  @override
  Future<void> run() async {
    await session.start();
    final record = session.record;
    if (record == null) return;
    try {
      await _save(record);
    } catch (error, stack) {
      // 存不進去只少一筆「過去的找書」，頁面上的結果照樣看得到。
      AppLog.e('存找書紀錄失敗', error: error, stackTrace: stack);
    }
  }

  @override
  void stop() => session.stop();

  @override
  Widget page() => AiFindPage(run: this);

  @override
  void disposeWork() {
    session.removeListener(changed);
    session.dispose();
  }
}

// 量捲動時存閱讀進度的成本：書籍表每更新一次記一筆，量幀時標出回覆落在
// 哪一幀，量完印出寫了幾次、那幾幀與其後兩幀有沒有超過上限。只聽資料庫的
// 更新通知，不碰閱讀器裡寫進度的類別，改前改後的程式都能用同一份量。

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/di/injection.dart';

import 'frame_budget.dart';

/// 標在寫進度那一幀的 [FrameCost.note]。
const kProgressWriteNote = '寫進度';

class ProgressWrites {
  ProgressWrites() {
    final db = getIt<AppDatabase>();
    _subscription = db
        .tableUpdates(TableUpdateQuery.onTable(db.books))
        .listen((_) => _count++);
  }

  late final StreamSubscription<void> _subscription;
  int _count = 0;
  int _taken = 0;

  /// 到目前為止書籍表更新了幾次。
  int get count => _count;

  /// 上次問過之後又寫了幾次（每一幀的 note 用）。
  int takeNew() {
    final fresh = _count - _taken;
    _taken = _count;
    return fresh;
  }

  Future<void> cancel() => _subscription.cancel();
}

/// 把 [ProgressWrites.takeNew] 有新寫入的幀標上 [kProgressWriteNote]。
String? withWriteNote(String? note, ProgressWrites writes) {
  final parts = [?note, if (writes.takeNew() > 0) kProgressWriteNote];
  return parts.isEmpty ? null : parts.join('、');
}

/// 寫進度的幀與其後兩幀：一共寫了幾次、其中畫面在動的幀最重多少、
/// 幾幀超過上限。
String describeWriteFrames(String label, List<FrameCost> costs) {
  final written = [
    for (final (i, cost) in costs.indexed)
      if (cost.note?.contains(kProgressWriteNote) ?? false) i,
  ];
  final around = {
    for (final i in written)
      for (var k = i; k <= i + 2 && k < costs.length; k++) k,
  };
  final moving = [
    for (final i in around)
      if (costs[i].moving) costs[i],
  ];
  final worst = moving.isEmpty
      ? 0
      : moving.map((c) => c.judged).reduce((a, b) => a > b ? a : b);
  final over = moving.where((c) => c.judged > frameLimit.inMicroseconds).length;
  return '$label：寫進度 ${written.length} 次（第 ${written.join('、')} 幀），'
      '那幾幀與其後兩幀畫面在動的 ${moving.length} 幀最重 '
      '${(worst / 1000).toStringAsFixed(1)}ms，超過上限 $over 幀';
}

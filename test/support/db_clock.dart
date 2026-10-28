// 測試的資料庫是記憶體資料庫，查詢在主執行緒上做；手機上資料庫在自己的
// isolate（ADR 0029 做法 6）。這裡記下每次查詢在主執行緒上花了多久，量動畫
// 時算進它落在的那一幀（`frame_budget.dart` 的 [FrameCost.dbMicros]），判斷
// 卡不卡時扣掉（ADR 0036）。
//
// 只算呼叫當下同步做完的部分：記憶體資料庫在呼叫時就把 SQL 跑完；要排隊等
// 交易鎖的那次，工作落在之後的 microtask，這裡記到的接近 0。所以只會少算、
// 不會多算，扣掉之後還超過的一定是 App 自己的工作。查詢結果轉成 Map、Drift
// 轉成資料物件的時間也不算在這裡，算是 App 的。
import 'dart:developer';

import 'package:drift/drift.dart';

/// 每次查詢的開始時間（[Timeline.now] 的時鐘）與在主執行緒上同步花的時間。
final List<({int start, int micros})> dbWork = [];

/// 包在測試的資料庫外面，記下每次查詢的時間（[dbWork]）。
class DbClock extends QueryInterceptor {
  T _time<T>(T Function() run) {
    final start = Timeline.now;
    try {
      return run();
    } finally {
      dbWork.add((start: start, micros: Timeline.now - start));
    }
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) => _time(() => executor.runBatched(statements));

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _time(() => executor.runCustom(statement, args));

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _time(() => executor.runInsert(statement, args));

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _time(() => executor.runDelete(statement, args));

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _time(() => executor.runUpdate(statement, args));

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) => _time(() => executor.runSelect(statement, args));
}

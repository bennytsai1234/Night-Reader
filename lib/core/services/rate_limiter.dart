import 'dart:async';
import 'package:reader/core/models/base_source.dart';

/// ConcurrentRecord - 並發記錄
class ConcurrentRecord {
  final bool isConcurrent; // 是否為 次數/毫秒 模式
  int time; // 開始訪問時間
  int frequency; // 正在訪問的個數或已訪問次數

  ConcurrentRecord(this.isConcurrent, this.time, this.frequency);
}

/// ConcurrentRateLimiter - 並發速率限制器
/// (原 Android help/ConcurrentRateLimiter.kt)
class ConcurrentRateLimiter {
  final BaseSource? source;

  static final Map<String, ConcurrentRecord> _concurrentRecordMap = {};

  ConcurrentRateLimiter(this.source);

  /// 獲取並發記錄，若處於限制狀態則等待
  Future<ConcurrentRecord?> getConcurrentRecord() async {
    while (true) {
      final waitTime = _checkFetchStart();
      if (waitTime <= 0) {
        return _concurrentRecordMap[source!.getKey()];
      }
      await Future.delayed(Duration(milliseconds: waitTime));
    }
  }

  int _checkFetchStart() {
    if (source == null) return 0;

    final concurrentRate = source!.concurrentRate;
    if (concurrentRate == null ||
        concurrentRate.isEmpty ||
        concurrentRate == '0') {
      return 0;
    }

    final key = source!.getKey();
    final rateIndex = concurrentRate.indexOf('/');

    _concurrentRecordMap[key] ??= ConcurrentRecord(
      rateIndex > 0,
      DateTime.now().millisecondsSinceEpoch,
      0,
    );

    final fetchRecord = _concurrentRecordMap[key]!;

    // 簡單的鎖模擬 (Dart 是單線程事件循環，通常不需要 synchronized)
    if (!fetchRecord.isConcurrent) {
      // 模式 A: 固定延遲 (例如 3000 代表兩次請求間隔 3s)
      if (fetchRecord.frequency > 0) {
        return int.tryParse(concurrentRate) ?? 0;
      }

      final nextTime = fetchRecord.time + (int.tryParse(concurrentRate) ?? 0);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now >= nextTime) {
        fetchRecord.time = now;
        fetchRecord.frequency = 1;
        return 0;
      }
      return nextTime - now;
    } else {
      // 模式 B: 次數/毫秒 (例如 10/1000 代表 1秒內最多10次)
      final sj = int.tryParse(concurrentRate.substring(rateIndex + 1)) ?? 1000;
      final cs = int.tryParse(concurrentRate.substring(0, rateIndex)) ?? 1;

      final now = DateTime.now().millisecondsSinceEpoch;
      final nextTime = fetchRecord.time + sj;

      if (now >= nextTime) {
        fetchRecord.time = now;
        fetchRecord.frequency = 1;
        return 0;
      }

      if (fetchRecord.frequency >= cs) {
        return nextTime - now;
      } else {
        fetchRecord.frequency += 1;
        return 0;
      }
    }
  }

  void fetchEnd(ConcurrentRecord? record) {
    if (record != null && !record.isConcurrent) {
      record.frequency = (record.frequency - 1).clamp(0, 999);
    }
  }

  /// 執行帶限制的區塊
  Future<T> withLimit<T>(Future<T> Function() block) async {
    if (source == null) return await block();

    final record = await getConcurrentRecord();
    try {
      return await block();
    } finally {
      fetchEnd(record);
    }
  }
}

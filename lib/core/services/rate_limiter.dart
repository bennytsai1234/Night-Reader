import 'dart:async';

import 'package:night_reader/core/models/base_source.dart';

/// ConcurrentRecord - 並發記錄
class ConcurrentRecord {
  final bool isConcurrent; // 是否為 次數/毫秒 模式
  int time; // 開始訪問時間
  int frequency; // 正在訪問的個數或已訪問次數

  ConcurrentRecord(this.isConcurrent, this.time, this.frequency);
}

/// 另一個 isolate 擁有的限流紀錄：[acquire] 等到可以發請求時回傳一張票，
/// 請求結束時 [release] 交回。
abstract interface class ConcurrentRateDelegate {
  Future<int> acquire(String key, String concurrentRate);
  void release(int ticket);
}

/// ConcurrentRateLimiter - 並發速率限制器
/// (原 Android help/ConcurrentRateLimiter.kt)
class ConcurrentRateLimiter {
  ConcurrentRateLimiter(BaseSource? source)
    : _key = source?.getKey(),
      _concurrentRate = source?.concurrentRate;

  final String? _key;
  final String? _concurrentRate;

  static final Map<String, ConcurrentRecord> _concurrentRecordMap = {};

  /// 設定後限流紀錄改由它管：書源 isolate 的請求和主 isolate 的請求打的是
  /// 同一批網站，限流紀錄只能有一份，放在主 isolate（ADR 0028）。
  static ConcurrentRateDelegate? delegate;

  /// 執行帶限制的區塊
  Future<T> withLimit<T>(Future<T> Function() block) async {
    final key = _key;
    final rate = _concurrentRate;
    if (key == null || !_limits(rate)) return await block();

    final delegate = ConcurrentRateLimiter.delegate;
    if (delegate != null) {
      final ticket = await delegate.acquire(key, rate!);
      try {
        return await block();
      } finally {
        delegate.release(ticket);
      }
    }

    final record = await acquire(key, rate!);
    try {
      return await block();
    } finally {
      release(record);
    }
  }

  static bool _limits(String? concurrentRate) =>
      concurrentRate != null &&
      concurrentRate.isNotEmpty &&
      concurrentRate != '0';

  /// 等到 [key] 這個書源可以再發一個請求，回傳要交給 [release] 的紀錄。
  static Future<ConcurrentRecord?> acquire(
    String key,
    String concurrentRate,
  ) async {
    while (true) {
      final waitTime = _checkFetchStart(key, concurrentRate);
      if (waitTime <= 0) {
        return _concurrentRecordMap[key];
      }
      await Future.delayed(Duration(milliseconds: waitTime));
    }
  }

  static int _checkFetchStart(String key, String concurrentRate) {
    if (!_limits(concurrentRate)) return 0;

    final rateIndex = concurrentRate.indexOf('/');
    final now = DateTime.now().millisecondsSinceEpoch;
    final isConcurrent = rateIndex > 0;
    final initialDelay = isConcurrent ? 0 : int.tryParse(concurrentRate) ?? 0;

    final existingRecord = _concurrentRecordMap[key];
    if (existingRecord == null || existingRecord.isConcurrent != isConcurrent) {
      _concurrentRecordMap[key] = ConcurrentRecord(
        isConcurrent,
        now - initialDelay,
        0,
      );
    }

    final fetchRecord = _concurrentRecordMap[key]!;

    // 簡單的鎖模擬 (Dart 是單線程事件循環，通常不需要 synchronized)
    if (!fetchRecord.isConcurrent) {
      // 模式 A: 固定延遲 (例如 3000 代表兩次請求間隔 3s)
      if (fetchRecord.frequency > 0) {
        return int.tryParse(concurrentRate) ?? 0;
      }

      final nextTime = fetchRecord.time + (int.tryParse(concurrentRate) ?? 0);
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

  static void release(ConcurrentRecord? record) {
    if (record != null && !record.isConcurrent) {
      record.frequency = (record.frequency - 1).clamp(0, 999);
    }
  }
}

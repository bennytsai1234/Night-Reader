import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/rate_limiter.dart';

/// 書源 isolate 向主 isolate 借名額：借到的時間由測試決定。
class _HeldDelegate implements ConcurrentRateDelegate {
  final pending = Completer<int>();
  final released = <int>[];

  @override
  Future<int> acquire(String key, String concurrentRate) => pending.future;

  @override
  void release(int ticket) => released.add(ticket);
}

/// 書源限流一次只放一個請求（固定間隔）：前一個請求卡住時，排隊等名額的
/// 下載被取消就不再等，也不佔著名額。
void main() {
  tearDown(() => ConcurrentRateLimiter.delegate = null);

  BookSource sourceWithRate(String key) => BookSource.fromJson({
    'bookSourceName': '限流',
    'bookSourceUrl': key,
    'concurrentRate': '50',
  });

  test('a cancelled wait for the slot stops and leaves it free', () async {
    final limiter = ConcurrentRateLimiter(
      sourceWithRate('https://rate-local.example'),
    );
    final stalled = Completer<void>();
    final first = limiter.withLimit(() => stalled.future);
    final cancelToken = CancelToken();

    final waiting = limiter.withLimit(
      () async => fail('取消後不該拿到名額'),
      cancelToken: cancelToken,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    cancelToken.cancel();

    await expectLater(
      waiting.timeout(const Duration(seconds: 1)),
      throwsA(isA<DioException>()),
    );
    stalled.complete();
    await first;
    // 取消的那一個沒有留下佔用：下一個照常拿到名額。
    expect(
      await limiter
          .withLimit(() async => '拿到了')
          .timeout(const Duration(seconds: 1)),
      '拿到了',
    );
  });

  test('a slot borrowed after the wait was cancelled is given back', () async {
    final delegate = _HeldDelegate();
    ConcurrentRateLimiter.delegate = delegate;
    final limiter = ConcurrentRateLimiter(
      sourceWithRate('https://rate-delegate.example'),
    );
    final cancelToken = CancelToken();

    final waiting = limiter.withLimit(
      () async => fail('取消後不該執行'),
      cancelToken: cancelToken,
    );
    cancelToken.cancel();
    await expectLater(
      waiting.timeout(const Duration(seconds: 1)),
      throwsA(isA<DioException>()),
    );

    delegate.pending.complete(7);
    await Future<void>.delayed(Duration.zero);
    expect(delegate.released, [7]);
  });
}

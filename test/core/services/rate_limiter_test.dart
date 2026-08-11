import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/rate_limiter.dart';

void main() {
  test('固定間隔模式的第一個請求不會先空等一個週期', () {
    fakeAsync((async) {
      var blockStarted = false;
      final limiter = ConcurrentRateLimiter(
        BookSource(
          bookSourceUrl: 'https://first-request.example',
          concurrentRate: '1000',
        ),
      );

      limiter.withLimit(() async {
        blockStarted = true;
      });
      async.flushMicrotasks();

      expect(blockStarted, isTrue);
    });
  });

  test('同一來源切換限制模式時重建相容的計數狀態', () async {
    final concurrentSource = BookSource(
      bookSourceUrl: 'https://mode-change.example',
      concurrentRate: '1/1000',
    );
    final delaySource = BookSource(
      bookSourceUrl: concurrentSource.bookSourceUrl,
      concurrentRate: '1000',
    );

    await ConcurrentRateLimiter(concurrentSource).withLimit(() async {});

    var fixedDelayBlockStarted = false;
    await ConcurrentRateLimiter(delaySource).withLimit(() async {
      fixedDelayBlockStarted = true;
    });

    expect(fixedDelayBlockStarted, isTrue);
  });
}

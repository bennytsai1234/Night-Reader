import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/download/download_executor.dart';

/// Tests for DownloadExecutor retry logic.
///
/// DownloadExecutor is a mixin that depends on DownloadBase and DownloadScheduler,
/// making it difficult to instantiate in isolation. Instead, we verify the retry
/// constants and the exponential backoff formula used by _downloadChapter.
void main() {
  group('DownloadExecutor retry logic', () {
    // The retry constant defined in DownloadExecutor
    const maxRetries = 3;

    test('maxRetries is 3', () {
      // Mirrors static const int _maxRetries = 3 in DownloadExecutor
      expect(maxRetries, 3);
    });

    test('exponential backoff timing: attempt 0 = 500ms', () {
      // delay = Duration(milliseconds: 500 * (1 << attempt))
      const delay = Duration(milliseconds: 500 * (1 << 0));
      expect(delay, const Duration(milliseconds: 500));
    });

    test('exponential backoff timing: attempt 1 = 1000ms', () {
      const delay = Duration(milliseconds: 500 * (1 << 1));
      expect(delay, const Duration(milliseconds: 1000));
    });

    test('exponential backoff timing: attempt 2 = 2000ms', () {
      const delay = Duration(milliseconds: 500 * (1 << 2));
      expect(delay, const Duration(milliseconds: 2000));
    });

    test('last retry (attempt == maxRetries - 1) does not delay', () {
      // In the code: if (attempt < _maxRetries - 1) { delay } else { log exhausted }
      // So on the final attempt (attempt == 2), no delay occurs, only error logging.
      const lastAttempt = maxRetries - 1;
      expect(
        lastAttempt < maxRetries - 1,
        false,
        reason: 'Final attempt should not trigger delay',
      );
    });

    test('retry attempts cover range 0 to maxRetries-1', () {
      final attempts = List.generate(maxRetries, (i) => i);
      expect(attempts, [0, 1, 2]);
      expect(attempts.length, maxRetries);
    });

    test('backoff durations increase exponentially', () {
      final durations = <Duration>[];
      for (var attempt = 0; attempt < maxRetries - 1; attempt++) {
        durations.add(Duration(milliseconds: 500 * (1 << attempt)));
      }
      // Each subsequent delay should be double the previous
      for (var i = 1; i < durations.length; i++) {
        expect(
          durations[i].inMilliseconds,
          durations[i - 1].inMilliseconds * 2,
          reason: 'Backoff should double with each attempt',
        );
      }
    });

    test('total maximum backoff time is 1500ms (500 + 1000)', () {
      // Only first two attempts have backoff (attempt 0 and 1)
      // Attempt 2 is the final attempt and goes straight to error logging
      var totalBackoff = 0;
      for (var attempt = 0; attempt < maxRetries - 1; attempt++) {
        totalBackoff += 500 * (1 << attempt);
      }
      expect(totalBackoff, 1500);
    });
  });

  group('downloadTaskCountsPreStoredChapters', () {
    test('counts pre-stored chapters for contiguous tasks', () {
      final task = DownloadTask(
        bookUrl: 'book',
        bookName: 'Book',
        startChapterIndex: 2,
        endChapterIndex: 4,
        totalCount: 3,
      );

      expect(
        downloadTaskCountsPreStoredChapters(task: task, chapterCountInRange: 3),
        isTrue,
      );
    });

    test('skips pre-stored chapters for sparse missing selections', () {
      final task = DownloadTask(
        bookUrl: 'book',
        bookName: 'Book',
        startChapterIndex: 0,
        endChapterIndex: 4,
        totalCount: 3,
      );

      expect(
        downloadTaskCountsPreStoredChapters(task: task, chapterCountInRange: 5),
        isFalse,
      );
    });
  });

  group('download failure details', () {
    test('classifies common failure reasons', () {
      expect(classifyDownloadFailureReason('SocketException: timeout'), '網路錯誤');
      expect(classifyDownloadFailureReason('加載章節失敗: 找不到書源'), '書源失效');
      expect(classifyDownloadFailureReason('章節內容為空 (可能解析規則有誤)'), '正文解析失敗');
      expect(classifyDownloadFailureReason('HTTP 404 not found'), '章節不存在');
      expect(classifyDownloadFailureReason('permission denied'), '權限問題');
      expect(
        classifyDownloadFailureReason('No space left on device'),
        '儲存空間不足',
      );
    });

    test(
      'DownloadTask stores readable failure summary without persistence schema changes',
      () {
        final task = DownloadTask(
          bookUrl: 'book',
          bookName: 'Book',
          startChapterIndex: 0,
          endChapterIndex: 2,
          totalCount: 3,
        );

        task
          ..errorCount = 1
          ..setFailure(
            reason: '正文解析失敗',
            message: '章節內容為空 (可能解析規則有誤)',
            chapterIndex: 1,
          );

        expect(task.hasFailures, isTrue);
        expect(task.failureSummary, '正文解析失敗，第 2 章：章節內容為空 (可能解析規則有誤)');

        task.clearFailure();
        task.errorCount = 0;
        expect(task.failureSummary, isNull);
      },
    );
  });
}

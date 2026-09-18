import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chapter_content_preparation_pipeline.dart';
import 'package:night_reader/core/services/download/download_executor.dart';

class _FakeBookSourceDao extends Fake implements BookSourceDao {}

class _RetryingBookSourceService extends BookSourceService {
  int calls = 0;

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    dynamic cancelToken,
  }) async {
    calls += 1;
    return calls < 3 ? '' : '可讀正文';
  }
}

void main() {
  group('chapter content retry behavior', () {
    test('uses the production pipeline until a later attempt returns readable content', () async {
      final service = _RetryingBookSourceService();
      final retryAttempts = <int>[];
      final pipeline = ChapterContentPreparationPipeline(
        book: Book(
          bookUrl: 'https://book.example/1',
          origin: 'https://source.example',
        ),
        contentStore: null,
        sourceDao: _FakeBookSourceDao(),
        service: service,
        retryDelay: (attempt) {
          retryAttempts.add(attempt);
          return Duration.zero;
        },
      );

      final result = await pipeline.prepare(
        chapterIndex: 0,
        chapter: BookChapter(url: 'chapter/1', index: 0),
        sourceOverride: BookSource(bookSourceUrl: 'https://source.example'),
        maxAttempts: 3,
      );

      expect(result.isReady, isTrue);
      expect(result.content, '可讀正文');
      expect(service.calls, 3);
      expect(retryAttempts, [0, 1]);
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

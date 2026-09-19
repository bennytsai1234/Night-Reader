import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chapter_content_preparation_pipeline.dart';

class _FakeBookSourceDao extends Fake implements BookSourceDao {}

class _ThrowingBookSourceService extends BookSourceService {
  _ThrowingBookSourceService(this.error);

  final Object error;

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    dynamic cancelToken,
  }) async {
    throw error;
  }
}

void main() {
  group('chapter content acquisition boundary', () {
    ChapterContentPreparationPipeline pipelineFor(Object error) {
      return ChapterContentPreparationPipeline(
        book: Book(
          bookUrl: 'https://book.example/1',
          origin: 'https://source.example',
        ),
        contentStore: null,
        sourceDao: _FakeBookSourceDao(),
        service: _ThrowingBookSourceService(error),
        retryDelay: (_) => Duration.zero,
      );
    }

    final chapter = BookChapter(url: 'chapter/1', index: 0);
    final source = BookSource(bookSourceUrl: 'https://source.example');

    test('known source-rule failure becomes content unavailable', () async {
      final result = await pipelineFor(
        SourceException('來源規則不可用', sourceUrl: source.bookSourceUrl),
      ).prepare(
        chapterIndex: 0,
        chapter: chapter,
        sourceOverride: source,
      );

      expect(result.isFailed, isTrue);
      expect(result.failureMessage, contains('來源規則不可用'));
    });

    test('network cancellation is not converted to unavailable', () async {
      final request = RequestOptions(path: 'https://source.example/chapter/1');
      final cancellation = DioException(
        requestOptions: request,
        type: DioExceptionType.cancel,
        message: 'superseded',
      );

      await expectLater(
        pipelineFor(cancellation).prepare(
          chapterIndex: 0,
          chapter: chapter,
          sourceOverride: source,
        ),
        throwsA(
          isA<DioException>().having(
            (error) => error.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
    });

    test('unknown internal failure keeps its original root cause', () async {
      final error = StateError('content engine invariant broke');

      await expectLater(
        pipelineFor(error).prepare(
          chapterIndex: 0,
          chapter: chapter,
          sourceOverride: source,
        ),
        throwsA(same(error)),
      );
    });
  });
}

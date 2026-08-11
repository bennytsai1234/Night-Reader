import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/reader_chapter_content.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chapter_content_preparation_pipeline.dart';
import 'package:night_reader/core/services/reader_chapter_content_storage.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';

class _FakeBookSourceDao extends Fake implements BookSourceDao {}

class _ControlledBookSourceService extends BookSourceService {
  final Map<String, Completer<String>> requests = <String, Completer<String>>{};

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) {
    final request = Completer<String>();
    requests[source.bookSourceUrl] = request;
    return request.future;
  }
}

class _SequencedBookSourceService extends BookSourceService {
  final List<Completer<String>> requests = <Completer<String>>[];

  @override
  Future<String> getContent(
    BookSource source,
    Book book,
    BookChapter chapter, {
    String? nextChapterUrl,
    int? pageConcurrency,
    CancelToken? cancelToken,
  }) {
    final request = Completer<String>();
    requests.add(request);
    return request.future;
  }
}

class _EmptyContentStore extends Fake implements ReaderChapterContentStore {
  @override
  Future<ReaderChapterContentEntry?> getContentEntry({
    required Book book,
    required BookChapter chapter,
  }) async {
    return null;
  }
}

void main() {
  final book = Book(
    bookUrl: 'https://book.example/1',
    origin: 'https://source-a.example',
  );
  final chapter = BookChapter(url: 'chapter/1', index: 0);
  final sourceA = BookSource(bookSourceUrl: 'https://source-a.example');
  final sourceB = BookSource(bookSourceUrl: 'https://source-b.example');

  test('pipeline 不會把不同 sourceOverride 的同章請求合併', () async {
    final sourceService = _ControlledBookSourceService();
    final pipeline = ChapterContentPreparationPipeline(
      book: book,
      contentStore: null,
      sourceDao: _FakeBookSourceDao(),
      service: sourceService,
    );

    final first = pipeline.prepare(
      chapterIndex: 0,
      chapter: chapter,
      sourceOverride: sourceA,
    );
    final second = pipeline.prepare(
      chapterIndex: 0,
      chapter: chapter,
      sourceOverride: sourceB,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      sourceService.requests.keys,
      containsAll(<String>[sourceA.bookSourceUrl, sourceB.bookSourceUrl]),
    );
    sourceService.requests[sourceA.bookSourceUrl]!.complete('來源 A 正文');
    sourceService.requests[sourceB.bookSourceUrl]!.complete('來源 B 正文');

    expect((await first).content, '來源 A 正文');
    expect((await second).content, '來源 B 正文');
  });

  test('storage 不會在 materializer 前合併不同來源的請求', () async {
    final requests = <String, Completer<ChapterContentPreparationResult>>{};
    final storage = ReaderChapterContentStorage(
      book: book,
      contentStore: _EmptyContentStore(),
      materialize: ({
        required chapterIndex,
        required chapter,
        sourceOverride,
        required forceRefresh,
        required saveChapterMetadata,
        required maxAttempts,
      }) {
        final request = Completer<ChapterContentPreparationResult>();
        requests[sourceOverride!.bookSourceUrl] = request;
        return request.future;
      },
    );

    final first = storage.read(
      chapterIndex: 0,
      chapter: chapter,
      sourceOverride: sourceA,
    );
    final second = storage.read(
      chapterIndex: 0,
      chapter: chapter,
      sourceOverride: sourceB,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      requests.keys,
      containsAll(<String>[sourceA.bookSourceUrl, sourceB.bookSourceUrl]),
    );
    requests[sourceA.bookSourceUrl]!.complete(
      ChapterContentPreparationResult.ready('來源 A 正文'),
    );
    requests[sourceB.bookSourceUrl]!.complete(
      ChapterContentPreparationResult.ready('來源 B 正文'),
    );

    expect((await first).content, '來源 A 正文');
    expect((await second).content, '來源 B 正文');
  });

  test('reset 前的舊請求完成時不會移除較新的同鍵請求', () async {
    final sourceService = _SequencedBookSourceService();
    final pipeline = ChapterContentPreparationPipeline(
      book: book,
      contentStore: null,
      sourceDao: _FakeBookSourceDao(),
      service: sourceService,
    );

    final first = pipeline.prepare(
      chapterIndex: 0,
      chapter: chapter,
      sourceOverride: sourceA,
    );
    pipeline.reset();
    final second = pipeline.prepare(
      chapterIndex: 0,
      chapter: chapter,
      sourceOverride: sourceA,
    );
    sourceService.requests[0].complete('舊請求');
    await first;

    final third = pipeline.prepare(
      chapterIndex: 0,
      chapter: chapter,
      sourceOverride: sourceA,
    );
    await Future<void>.delayed(Duration.zero);

    expect(sourceService.requests, hasLength(2));
    sourceService.requests[1].complete('新請求');
    expect((await second).content, '新請求');
    expect((await third).content, '新請求');
  });
}

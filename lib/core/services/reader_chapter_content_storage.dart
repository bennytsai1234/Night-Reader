import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chapter_content_preparation_pipeline.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';

typedef ChapterContentMaterializer =
    Future<ChapterContentPreparationResult> Function({
      required int chapterIndex,
      required BookChapter chapter,
      BookSource? sourceOverride,
      required bool forceRefresh,
      required bool saveChapterMetadata,
      required int maxAttempts,
    });

class ReaderChapterContentStorage {
  ReaderChapterContentStorage({
    required this.book,
    required this.contentStore,
    required ChapterContentMaterializer materialize,
    void Function()? resetMaterializer,
  }) : _materialize = materialize,
       _resetMaterializer = resetMaterializer;

  factory ReaderChapterContentStorage.withMaterializer({
    required Book book,
    required ReaderChapterContentStore contentStore,
    required BookSourceDao sourceDao,
    required BookSourceService service,
    BookSource? Function()? getSource,
    void Function(BookSource source)? setSource,
    String? Function(int chapterIndex)? resolveNextChapterUrl,
  }) {
    final pipeline = ChapterContentPreparationPipeline(
      book: book,
      contentStore: contentStore,
      sourceDao: sourceDao,
      service: service,
      getSource: getSource,
      setSource: setSource,
      resolveNextChapterUrl: resolveNextChapterUrl,
    );
    return ReaderChapterContentStorage(
      book: book,
      contentStore: contentStore,
      materialize:
          ({
            required chapterIndex,
            required chapter,
            sourceOverride,
            required forceRefresh,
            required saveChapterMetadata,
            required maxAttempts,
          }) => pipeline.prepare(
            chapterIndex: chapterIndex,
            chapter: chapter,
            sourceOverride: sourceOverride,
            forceRefresh: forceRefresh,
            saveChapterMetadata: saveChapterMetadata,
            maxAttempts: maxAttempts,
          ),
      resetMaterializer: pipeline.reset,
    );
  }

  final Book book;
  final ReaderChapterContentStore contentStore;
  final ChapterContentMaterializer _materialize;
  final void Function()? _resetMaterializer;

  static final Map<String, Future<ChapterContentPreparationResult>> _inFlight =
      <String, Future<ChapterContentPreparationResult>>{};

  Future<ChapterContentPreparationResult> read({
    required int chapterIndex,
    required BookChapter chapter,
    BookSource? sourceOverride,
    bool forceRefresh = false,
    bool saveChapterMetadata = true,
    int maxAttempts = 1,
  }) async {
    if (!forceRefresh) {
      final stored = await _readStored(chapter);
      if (stored != null) return stored;
    }

    final key = ReaderChapterContentStore.contentKeyFor(
      book: book,
      chapter: chapter,
    );
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final request = _materializeAndRead(
      chapterIndex: chapterIndex,
      chapter: chapter,
      sourceOverride: sourceOverride,
      forceRefresh: forceRefresh,
      saveChapterMetadata: saveChapterMetadata,
      maxAttempts: maxAttempts,
    );
    _inFlight[key] = request;
    return request.whenComplete(() {
      if (identical(_inFlight[key], request)) {
        _inFlight.remove(key);
      }
    });
  }

  void reset() {
    _resetMaterializer?.call();
  }

  Future<ChapterContentPreparationResult> _materializeAndRead({
    required int chapterIndex,
    required BookChapter chapter,
    required BookSource? sourceOverride,
    required bool forceRefresh,
    required bool saveChapterMetadata,
    required int maxAttempts,
  }) async {
    final materialized = await _materialize(
      chapterIndex: chapterIndex,
      chapter: chapter,
      sourceOverride: sourceOverride,
      forceRefresh: forceRefresh,
      saveChapterMetadata: saveChapterMetadata,
      maxAttempts: maxAttempts,
    );
    return await _readStored(chapter) ?? materialized;
  }

  Future<ChapterContentPreparationResult?> _readStored(
    BookChapter chapter,
  ) async {
    final entry = await contentStore.getContentEntry(
      book: book,
      chapter: chapter,
    );
    if (entry == null || !entry.hasDisplayContent) return null;
    if (entry.isFailed) {
      return ChapterContentPreparationResult.failed(
        entry.failureMessage ?? entry.content!,
      );
    }
    return ChapterContentPreparationResult.ready(entry.content!);
  }
}

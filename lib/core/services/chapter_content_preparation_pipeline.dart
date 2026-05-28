import 'dart:async';

import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/reader_chapter_content.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/local_book_service.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';

class ChapterContentPreparationResult {
  const ChapterContentPreparationResult({
    required this.content,
    required this.status,
    this.failureMessage,
  });

  final String content;
  final ReaderChapterContentStatus status;
  final String? failureMessage;

  bool get isReady => status == ReaderChapterContentStatus.ready;
  bool get isFailed => status == ReaderChapterContentStatus.failed;

  factory ChapterContentPreparationResult.ready(String content) {
    return ChapterContentPreparationResult(
      content: content,
      status: ReaderChapterContentStatus.ready,
    );
  }

  factory ChapterContentPreparationResult.failed(String message) {
    return ChapterContentPreparationResult(
      content: message,
      status: ReaderChapterContentStatus.failed,
      failureMessage: message,
    );
  }
}

class ChapterContentPreparationPipeline {
  ChapterContentPreparationPipeline({
    required this.book,
    required this.contentStore,
    required this.sourceDao,
    required this.service,
    this.getSource,
    this.setSource,
    this.resolveNextChapterUrl,
    this.retryDelay = _defaultRetryDelay,
  });

  final Book book;
  final ReaderChapterContentStore? contentStore;
  final BookSourceDao sourceDao;
  final BookSourceService service;
  final BookSource? Function()? getSource;
  final void Function(BookSource source)? setSource;
  final String? Function(int chapterIndex)? resolveNextChapterUrl;
  final Duration Function(int attempt) retryDelay;

  final Map<String, Future<ChapterContentPreparationResult>> _inFlight =
      <String, Future<ChapterContentPreparationResult>>{};

  static Duration _defaultRetryDelay(int attempt) {
    return Duration(milliseconds: 500 * (1 << attempt));
  }

  Future<ChapterContentPreparationResult> prepare({
    required int chapterIndex,
    required BookChapter chapter,
    BookSource? sourceOverride,
    bool forceRefresh = false,
    bool saveChapterMetadata = true,
    int maxAttempts = 1,
  }) async {
    final store = contentStore;
    if (!forceRefresh && store != null) {
      final entry = await store.getContentEntry(book: book, chapter: chapter);
      if (entry != null && entry.hasDisplayContent) {
        if (entry.isFailed) {
          return ChapterContentPreparationResult.failed(
            entry.failureMessage ?? entry.content!,
          );
        }
        return ChapterContentPreparationResult.ready(entry.content!);
      }
    }

    final key = _inFlightKey(chapter);
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final fetch = _fetchAndStore(
      chapterIndex: chapterIndex,
      chapter: chapter,
      sourceOverride: sourceOverride,
      saveChapterMetadata: saveChapterMetadata,
      maxAttempts: maxAttempts,
    );
    _inFlight[key] = fetch;
    return fetch.whenComplete(() => _inFlight.remove(key));
  }

  void reset() {
    _inFlight.clear();
  }

  String _inFlightKey(BookChapter chapter) {
    final store = contentStore;
    if (store == null) {
      return '${book.origin}\n${book.bookUrl}\n${chapter.url}';
    }
    return ReaderChapterContentStore.contentKeyFor(
      book: book,
      chapter: chapter,
    );
  }

  Future<ChapterContentPreparationResult> _fetchAndStore({
    required int chapterIndex,
    required BookChapter chapter,
    required BookSource? sourceOverride,
    required bool saveChapterMetadata,
    required int maxAttempts,
  }) async {
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final result = await _fetchOnce(
        chapterIndex: chapterIndex,
        chapter: chapter,
        sourceOverride: sourceOverride,
      );
      if (result.isReady || attempt == attempts - 1) {
        await _storeResult(
          chapter: chapter,
          result: result,
          saveChapterMetadata: saveChapterMetadata,
        );
        return result;
      }
      await Future<void>.delayed(retryDelay(attempt));
    }

    final result = ChapterContentPreparationResult.failed('加載正文失敗');
    await _storeResult(
      chapter: chapter,
      result: result,
      saveChapterMetadata: saveChapterMetadata,
    );
    return result;
  }

  Future<ChapterContentPreparationResult> _fetchOnce({
    required int chapterIndex,
    required BookChapter chapter,
    required BookSource? sourceOverride,
  }) async {
    try {
      if (book.origin == 'local') {
        final raw = await LocalBookService().getContent(book, chapter);
        if (raw.isNotEmpty && !_looksLikeLocalFailureMessage(raw)) {
          return ChapterContentPreparationResult.ready(raw);
        }
        return ChapterContentPreparationResult.failed(
          raw.isEmpty ? '章節內容為空 (可能解析規則有誤)' : raw,
        );
      }

      var source = sourceOverride ?? getSource?.call();
      source ??= await sourceDao.getByUrl(book.origin);
      if (source != null) {
        setSource?.call(source);
      }
      if (source == null) {
        return ChapterContentPreparationResult.failed('加載章節失敗: 找不到書源');
      }

      final nextChapterUrl = resolveNextChapterUrl?.call(chapterIndex);
      final resolvedSource = source;
      final raw = await service.getContent(
        resolvedSource,
        book,
        chapter,
        nextChapterUrl: nextChapterUrl,
      );
      if (raw.isNotEmpty) {
        return ChapterContentPreparationResult.ready(raw);
      }
      return ChapterContentPreparationResult.failed('章節內容為空 (可能解析規則有誤)');
    } catch (e) {
      return ChapterContentPreparationResult.failed('加載章節失敗: $e');
    }
  }

  Future<void> _storeResult({
    required BookChapter chapter,
    required ChapterContentPreparationResult result,
    required bool saveChapterMetadata,
  }) async {
    final store = contentStore;
    if (store == null || result.content.isEmpty) return;
    if (result.isReady) {
      await store.saveRawContent(
        book: book,
        chapter: chapter,
        content: result.content,
        saveChapterMetadata: saveChapterMetadata,
      );
      return;
    }
    await store.saveFailure(
      book: book,
      chapter: chapter,
      message: result.failureMessage ?? result.content,
      saveChapterMetadata: saveChapterMetadata,
    );
  }

  bool _looksLikeLocalFailureMessage(String content) {
    final trimmed = content.trim();
    return trimmed.startsWith('讀取本地書籍失敗') ||
        trimmed.startsWith('本地書籍檔案不存在') ||
        trimmed.startsWith('無法讀取本地書籍內容') ||
        trimmed.startsWith('檔案不存在:') ||
        trimmed.startsWith('本地 TXT 索引缺失') ||
        trimmed.startsWith('本地 UMD 章節索引缺失') ||
        trimmed.startsWith('不支援的本地格式:');
  }
}

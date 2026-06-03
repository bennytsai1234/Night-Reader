import 'dart:async';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:pool/pool.dart';

import 'book_source_service.dart';

class SourceSwitchResolution {
  final SearchBook searchBook;
  final BookSource source;
  final Book migratedBook;
  final List<BookChapter> chapters;
  final int targetChapterIndex;
  final String? validatedContent;

  const SourceSwitchResolution({
    required this.searchBook,
    required this.source,
    required this.migratedBook,
    required this.chapters,
    required this.targetChapterIndex,
    this.validatedContent,
  });
}

class SourceSwitchService {
  SourceSwitchService({BookSourceService? service, BookSourceDao? sourceDao})
    : _service = service ?? BookSourceService(),
      _sourceDao = sourceDao ?? getIt<BookSourceDao>();

  static const int _maxConcurrentSearches = 6;

  final BookSourceService _service;
  final BookSourceDao _sourceDao;

  Future<List<SearchBook>> searchAlternatives(
    Book book, {
    bool checkAuthor = true,
  }) async {
    final enabledSources =
        (await _sourceDao.getEnabled())
            .where(
              (source) =>
                  source.isSearchEnabledByRuntime &&
                  source.bookSourceUrl != book.origin,
            )
            .toList();
    if (enabledSources.isEmpty) {
      return const <SearchBook>[];
    }

    final searchPool = Pool(_maxConcurrentSearches);
    try {
      final tasks =
          enabledSources.map((source) {
            return searchPool.withResource(() async {
              try {
                return await _service.preciseSearch(
                  source,
                  book.name,
                  checkAuthor ? book.author : '',
                );
              } catch (_) {
                return const <SearchBook>[];
              }
            });
          }).toList();
      final results = await Future.wait(tasks);
      final merged = results.expand((items) => items).toList();
      merged.removeWhere((item) => item.origin == book.origin);
      merged.sort((a, b) {
        final orderCompare = a.originOrder.compareTo(b.originOrder);
        if (orderCompare != 0) {
          return orderCompare;
        }
        final chapterCompare = (b.latestChapterTitle?.length ?? 0).compareTo(
          a.latestChapterTitle?.length ?? 0,
        );
        if (chapterCompare != 0) {
          return chapterCompare;
        }
        return a.name.compareTo(b.name);
      });
      return merged;
    } finally {
      await searchPool.close();
    }
  }

  Future<SourceSwitchResolution?> autoResolveSwitch(
    Book currentBook, {
    bool checkAuthor = true,
    int? targetChapterIndex,
    String? targetChapterTitle,
  }) async {
    final candidates = await searchAlternatives(
      currentBook,
      checkAuthor: checkAuthor,
    );
    for (final candidate in candidates) {
      try {
        return await resolveSwitch(
          currentBook,
          candidate,
          targetChapterIndex: targetChapterIndex,
          targetChapterTitle: targetChapterTitle,
          validateTargetContent: true,
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<SourceSwitchResolution> resolveSwitch(
    Book currentBook,
    SearchBook candidate, {
    int? targetChapterIndex,
    String? targetChapterTitle,
    bool validateTargetContent = false,
  }) async {
    final source = await _sourceDao.getByUrl(candidate.origin);
    if (source == null) {
      throw StateError('找不到對應書源');
    }

    final alignmentBook = currentBook.copyWith(
      chapterIndex: targetChapterIndex ?? currentBook.chapterIndex,
      durChapterTitle: targetChapterTitle ?? currentBook.durChapterTitle,
    );
    final hydratedBook = await _service.getBookInfo(source, candidate.toBook());
    final chapters = await _service.getChapterList(source, hydratedBook);
    if (chapters.isEmpty) {
      throw StateError('新來源沒有可用目錄');
    }

    final migratedBook = alignmentBook.migrateTo(hydratedBook, chapters);
    final resolvedTargetIndex = migratedBook.chapterIndex.clamp(
      0,
      chapters.length - 1,
    );

    String? validatedContent;
    if (validateTargetContent) {
      final chapter = chapters[resolvedTargetIndex];
      validatedContent = await _service.getContent(
        source,
        migratedBook,
        chapter,
        nextChapterUrl: _nextReadableChapterUrl(chapters, resolvedTargetIndex),
      );
      if (!_looksReadable(validatedContent)) {
        throw StateError('目標章節內容不可讀');
      }
    }

    return SourceSwitchResolution(
      searchBook: candidate,
      source: source,
      migratedBook: migratedBook,
      chapters: chapters,
      targetChapterIndex: resolvedTargetIndex,
      validatedContent: validatedContent,
    );
  }

  /// 持久化換源結果：把書遷移到新來源。
  ///
  /// 若新書的 bookUrl 與舊書不同（遷移到不同來源 URL），先刪除舊書 row 與舊
  /// 章節，避免書架出現重複項；接著以新章節列表覆蓋新書並 upsert。
  /// 書架「每源獨立」儲存模型不變：一本書始終只有一個當前來源。
  Future<void> persistSwitch(
    Book oldBook,
    SourceSwitchResolution resolution, {
    BookDao? bookDao,
    ChapterDao? chapterDao,
  }) async {
    final books = bookDao ?? getIt<BookDao>();
    final chaptersDao = chapterDao ?? getIt<ChapterDao>();
    final migratedBook = resolution.migratedBook;

    if (migratedBook.bookUrl != oldBook.bookUrl) {
      await chaptersDao.deleteByBook(oldBook.bookUrl);
      await books.deleteByUrl(oldBook.bookUrl);
    }
    await chaptersDao.deleteByBook(migratedBook.bookUrl);
    await books.upsert(migratedBook);
    await chaptersDao.insertChapters(resolution.chapters);
  }

  String? _nextReadableChapterUrl(
    List<BookChapter> chapters,
    int currentIndex,
  ) {
    for (var i = currentIndex + 1; i < chapters.length; i++) {
      final chapter = chapters[i];
      if (!chapter.isVolume && chapter.url.isNotEmpty) {
        return chapter.url;
      }
    }
    return null;
  }

  bool _looksReadable(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('加載章節失敗')) return false;
    if (trimmed.startsWith('章節內容為空')) return false;
    return trimmed.runes.length >= 20;
  }
}

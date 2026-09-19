import 'dart:async';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:pool/pool.dart';

import 'book_source_service.dart';

bool _looksReadableSourceSwitchContent(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.startsWith('加載章節失敗')) return false;
  if (trimmed.startsWith('章節內容為空')) return false;
  return trimmed.runes.length >= 20;
}

class PreparedSourceSwitch {
  final SearchBook searchBook;
  final BookSource source;
  final Book migratedBook;
  final List<BookChapter> chapters;
  final int targetChapterIndex;
  final BookChapter targetChapter;
  final String validatedContent;

  PreparedSourceSwitch({
    required this.searchBook,
    required this.source,
    required this.migratedBook,
    required this.chapters,
    required this.targetChapterIndex,
    required this.validatedContent,
  }) : targetChapter = chapters[targetChapterIndex] {
    if (!_looksReadableSourceSwitchContent(validatedContent)) {
      throw ArgumentError.value(
        validatedContent,
        'validatedContent',
        'Prepared source switch requires readable validated target content',
      );
    }
    if (chapters.any((chapter) => chapter.bookUrl != migratedBook.bookUrl)) {
      throw ArgumentError(
        'Prepared source switch chapters do not belong to migrated book',
      );
    }
  }
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
                final author = book.author.trim();
                if (checkAuthor && author.isNotEmpty) {
                  return await _service.preciseSearch(
                    source,
                    book.name,
                    author,
                  );
                }
                return await _service.searchBooks(
                  source,
                  book.name,
                  filter: (name, _) => name == book.name,
                  shouldBreak: (size) => size >= 1,
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

  Future<PreparedSourceSwitch?> autoPrepareSwitch(
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
        return await prepareSwitch(
          currentBook,
          candidate,
          targetChapterIndex: targetChapterIndex,
          targetChapterTitle: targetChapterTitle,
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<PreparedSourceSwitch> prepareSwitch(
    Book currentBook,
    SearchBook candidate, {
    int? targetChapterIndex,
    String? targetChapterTitle,
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

    final targetChapter = chapters[resolvedTargetIndex];
    final validatedContent = await _service.getContent(
      source,
      migratedBook,
      targetChapter,
      nextChapterUrl: _nextReadableChapterUrl(chapters, resolvedTargetIndex),
    );
    if (!_looksReadableSourceSwitchContent(validatedContent)) {
      throw StateError('目標章節內容不可讀');
    }

    return PreparedSourceSwitch(
      searchBook: candidate,
      source: source,
      migratedBook: migratedBook,
      chapters: chapters,
      targetChapterIndex: resolvedTargetIndex,
      validatedContent: validatedContent,
    );
  }

  /// Commit a fully prepared source switch and hand the validated target
  /// content to the new reader world in the same database transaction.
  ///
  /// Only a [PreparedSourceSwitch] can cross this boundary: target content
  /// validation has already succeeded, so commit publishes book metadata,
  /// chapters and that exact target body as one authoritative world. Obsolete
  /// data owned by the old source identity is retired in the same transaction;
  /// any failure rolls the whole handoff back to the old world.
  Future<void> commitSwitch(
    Book oldBook,
    PreparedSourceSwitch prepared, {
    BookDao? bookDao,
    ChapterDao? chapterDao,
  }) async {
    final books = bookDao ?? getIt<BookDao>();
    final db = books.appDatabase;
    final chaptersDao = chapterDao ?? ChapterDao(db);
    final contentDao = ReaderChapterContentDao(db);
    final migratedBook = prepared.migratedBook;

    await db.transaction(() async {
      await chaptersDao.deleteByBook(migratedBook.bookUrl);
      await books.upsert(migratedBook);
      await chaptersDao.insertChapters(prepared.chapters);

      final targetChapter = prepared.targetChapter;
      await contentDao.saveContent(
        contentKey: ReaderChapterContentDao.contentKey(
          origin: migratedBook.origin,
          bookUrl: migratedBook.bookUrl,
          chapterUrl: targetChapter.url,
        ),
        origin: migratedBook.origin,
        bookUrl: migratedBook.bookUrl,
        chapterUrl: targetChapter.url,
        chapterIndex: targetChapter.index,
        content: prepared.validatedContent,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      final sourceIdentityChanged =
          oldBook.origin != migratedBook.origin ||
          oldBook.bookUrl != migratedBook.bookUrl;
      if (sourceIdentityChanged) {
        await contentDao.deleteByBook(oldBook.origin, oldBook.bookUrl);
      }

      if (migratedBook.bookUrl != oldBook.bookUrl) {
        await chaptersDao.deleteByBook(oldBook.bookUrl);
        await books.deleteByUrl(oldBook.bookUrl);
      }
    });
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

}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book/chapter_alignment.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_illustration_storage.dart';
import 'package:pool/pool.dart';

import 'app_log_service.dart';
import 'book_source_service.dart';
import 'chapter_content_kind.dart';
import 'source_switch_handoff.dart';

bool isSourceSwitchUnavailable(Object error) {
  if (error is DioException) return error.type != DioExceptionType.cancel;
  return error is AppException || error is TimeoutException;
}

/// 自動換源（ADR 0069）能換過去的書源：啟用、和書同一類（聚合源不算，ADR
/// 0056 照 Legado 只用同一類）、沒有校驗的狀態標記（含付費、需要登入、需要
/// 驗證：背景不等人，ADR 0038）與「AI 修不好」。
bool autoSwitchCandidateSource(BookSource source, BookSourceKind kind) =>
    source.isSearchableFor(kind) &&
    !source.groupTags.any(
      (tag) =>
          sourceRuntimeStatusTags.contains(tag) ||
          tag == aiUnfixableSourceGroupTag,
    );

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
    if (!chapterContentUsable(migratedBook.bookKind, validatedContent)) {
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

/// 換源對好目錄、還沒確認正文的那一半（[SourceSwitchService._align]）。
class _AlignedSwitch {
  _AlignedSwitch({
    required this.searchBook,
    required this.source,
    required this.migratedBook,
    required this.chapters,
    required this.targetIndex,
  }) : targetChapter = chapters[targetIndex];

  final SearchBook searchBook;
  final BookSource source;
  final Book migratedBook;
  final List<BookChapter> chapters;
  final int targetIndex;
  final BookChapter targetChapter;
}

class SourceSwitchService {
  SourceSwitchService({
    BookSourceService? service,
    BookSourceDao? sourceDao,
    this._operationQuiescer,
    this._assetRetirer,
  }) : _service = service ?? BookSourceService(),
       _sourceDao = sourceDao ?? getIt<BookSourceDao>();

  static const int _maxConcurrentSearches = 6;

  final BookSourceService _service;
  final BookSourceDao _sourceDao;
  final SourceSwitchOperationQuiescer? _operationQuiescer;
  final SourceSwitchAssetRetirer? _assetRetirer;

  /// 自動換源（ADR 0069）：在書源被刪掉的 [book] 之外，從啟用、同一類、
  /// 沒有狀態標記與「AI 修不好」的書源（[autoSwitchCandidateSource]）裡找
  /// 書名與作者都一樣的這本書。讀到的那一章 [chapterTitle] 在新目錄裡對得上
  /// （[sameChapterTitle]）、那一章抓得到的才算；幾個都算時挑目錄章數最多
  /// 的，一樣多照書源排序。沒有一個算是 null。
  ///
  /// 某個書源搜不到、抓不到（[isSourceSwitchUnavailable]）只跳過那一個；
  /// [cancelToken] 取消時傳回 null。
  Future<PreparedSourceSwitch?> prepareAutomaticSwitch(
    Book book, {
    required String chapterTitle,
    CancelToken? cancelToken,
  }) async {
    final sources =
        (await _sourceDao.getEnabled())
            .where(
              (source) =>
                  source.bookSourceUrl != book.origin &&
                  autoSwitchCandidateSource(source, book.bookKind),
            )
            .toList()
          ..sort((a, b) {
            final byOrder = a.customOrder.compareTo(b.customOrder);
            if (byOrder != 0) return byOrder;
            return a.bookSourceUrl.compareTo(b.bookSourceUrl);
          });
    if (sources.isEmpty) return null;
    // 搜尋結果的 originOrder 沒有填，照書源本身的排序。
    final rank = {
      for (final (i, source) in sources.indexed) source.bookSourceUrl: i,
    };
    final pool = Pool(_maxConcurrentSearches);
    try {
      Future<T?> skipUnavailable<T>(Future<T> Function() work) =>
          pool.withResource(() async {
            if (cancelToken?.isCancelled ?? false) return null;
            try {
              return await work();
            } catch (error) {
              if (!_skippable(error, cancelToken)) rethrow;
              return null;
            }
          });

      final hits = [
        for (final found in await Future.wait([
          for (final source in sources)
            skipUnavailable(
              () => _service.preciseSearch(
                source,
                book.name,
                book.author,
                cancelToken: cancelToken,
              ),
            ),
        ]))
          ...?found,
      ];

      final aligned = [
        for (final candidate in await Future.wait([
          for (final hit in hits)
            skipUnavailable(
              () => _align(
                book,
                hit,
                targetChapterTitle: chapterTitle,
                cancelToken: cancelToken,
              ),
            ),
        ]))
          if (candidate != null &&
              sameChapterTitle(candidate.targetChapter.title, chapterTitle))
            candidate,
      ];
      aligned.sort((a, b) {
        final byChapters = b.chapters.length.compareTo(a.chapters.length);
        if (byChapters != 0) return byChapters;
        return rank[a.source.bookSourceUrl]!.compareTo(
          rank[b.source.bookSourceUrl]!,
        );
      });
      for (final candidate in aligned) {
        if (cancelToken?.isCancelled ?? false) return null;
        try {
          return await _validate(candidate, cancelToken: cancelToken);
        } catch (error) {
          if (!_skippable(error, cancelToken)) rethrow;
        }
      }
      return null;
    } finally {
      await pool.close();
    }
  }

  /// 自動換源跳過這個候選就好的錯誤：書源搜不到、抓不到，或整件被取消。
  static bool _skippable(Object error, CancelToken? cancelToken) =>
      isSourceSwitchUnavailable(error) || (cancelToken?.isCancelled ?? false);

  Future<PreparedSourceSwitch> prepareSwitch(
    Book currentBook,
    SearchBook candidate, {
    int? targetChapterIndex,
    String? targetChapterTitle,
  }) async => _validate(
    await _align(
      currentBook,
      candidate,
      targetChapterIndex: targetChapterIndex,
      targetChapterTitle: targetChapterTitle,
    ),
  );

  /// 換源的前一半：新書源的詳情與目錄，進度照章名對到新目錄
  /// （[Book.migrateTo]）。
  Future<_AlignedSwitch> _align(
    Book currentBook,
    SearchBook candidate, {
    int? targetChapterIndex,
    String? targetChapterTitle,
    CancelToken? cancelToken,
  }) async {
    final source = await _sourceDao.getByUrl(candidate.origin);
    if (source == null) {
      throw SourceException('找不到對應書源', sourceUrl: candidate.origin);
    }

    final alignmentBook = currentBook.copyWith(
      chapterIndex: targetChapterIndex ?? currentBook.chapterIndex,
      durChapterTitle: targetChapterTitle ?? currentBook.durChapterTitle,
    );
    final hydratedBook = await _service.getBookInfo(
      source,
      candidate.toBook(),
      cancelToken: cancelToken,
    );
    final chapters = await _service.getChapterList(
      source,
      hydratedBook,
      cancelToken: cancelToken,
    );
    if (chapters.isEmpty) {
      throw SourceException('新來源沒有可用目錄', sourceUrl: candidate.origin);
    }

    final migratedBook = alignmentBook.migrateTo(hydratedBook, chapters);
    final targetIndex = migratedBook.chapterIndex.clamp(0, chapters.length - 1);
    // 有聲書對到同一集就接著聽到的那一秒（charOffset 存毫秒，ADR 0055），
    // 文字書的位置規則不適用。
    if (migratedBook.bookKind == BookSourceKind.audio &&
        chapters[targetIndex].title == alignmentBook.durChapterTitle) {
      migratedBook.charOffset = alignmentBook.charOffset;
    }
    return _AlignedSwitch(
      searchBook: candidate,
      source: source,
      migratedBook: migratedBook,
      chapters: chapters,
      targetIndex: targetIndex,
    );
  }

  /// 換源的後一半：新書源讀到的那一章抓得到才算。
  Future<PreparedSourceSwitch> _validate(
    _AlignedSwitch aligned, {
    CancelToken? cancelToken,
  }) async {
    final _AlignedSwitch(
      :source,
      :migratedBook,
      :chapters,
      :targetIndex,
      :targetChapter,
    ) = aligned;
    // 有聲書照播放時同一個入口拿音訊網址（正文規則空著時章節網址就是音訊），
    // 不跑文字正文。
    final validatedContent = migratedBook.bookKind == BookSourceKind.audio
        ? (await _service.getAudioRequest(
            source,
            migratedBook,
            targetChapter,
            cancelToken: cancelToken,
          )).url
        : await _service.getContent(
            source,
            migratedBook,
            targetChapter,
            nextChapterUrl: _nextReadableChapterUrl(chapters, targetIndex),
            cancelToken: cancelToken,
          );
    if (!chapterContentUsable(migratedBook.bookKind, validatedContent)) {
      throw SourceException('目標章節內容不可讀', sourceUrl: source.bookSourceUrl);
    }
    // 漫畫的圖由漫畫閱讀器照書源抓（ADR 0052），不當插圖存。
    if (migratedBook.bookKind == BookSourceKind.novel &&
        validatedContent.contains('<img')) {
      await _service.fetchIllustrations(
        source,
        migratedBook,
        validatedContent,
        dir: await BookIllustrationStorage.dirFor(migratedBook),
      );
    }

    return PreparedSourceSwitch(
      searchBook: aligned.searchBook,
      source: source,
      migratedBook: migratedBook,
      chapters: chapters,
      targetChapterIndex: targetIndex,
      validatedContent: validatedContent,
    );
  }

  /// Commit a fully prepared source switch and hand the validated target
  /// content to the new reader world in the same database transaction.
  ///
  /// Only a [PreparedSourceSwitch] can cross this boundary: target content
  /// validation has already succeeded, so commit publishes book metadata,
  /// chapters and that exact target body as one authoritative world, while
  /// obsolete source-owned content is retired and the book's bookmarks and
  /// highlights are realigned to the new chapter list in the same
  /// transaction; any failure rolls the whole handoff back to the old world.
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
    final sourceIdentityChanged =
        oldBook.origin != migratedBook.origin ||
        oldBook.bookUrl != migratedBook.bookUrl;
    final operationLease = sourceIdentityChanged
        ? await _operationQuiescer?.call(oldBook)
        : null;

    try {
      await db.transaction(() async {
        await operationLease?.retireInTransaction(db);

        await chaptersDao.deleteByBook(migratedBook.bookUrl);
        await books.upsert(migratedBook);
        await chaptersDao.insertChapters(prepared.chapters);
        await BookmarkDao(db).moveToSource(
          fromName: oldBook.recordName,
          fromAuthor: oldBook.author,
          toName: migratedBook.recordName,
          toAuthor: migratedBook.author,
          oldTotalCount: oldBook.totalChapterNum,
          chapters: prepared.chapters,
        );
        await HighlightDao(db).moveToSource(
          fromName: oldBook.recordName,
          fromAuthor: oldBook.author,
          toName: migratedBook.recordName,
          toAuthor: migratedBook.author,
          oldTotalCount: oldBook.totalChapterNum,
          chapters: prepared.chapters,
        );

        final targetChapter = prepared.targetChapter;
        // 漫畫的章節存成 CBZ（ADR 0052），不進正文快取。
        if (migratedBook.bookKind != BookSourceKind.comic) {
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
        }

        if (sourceIdentityChanged) {
          await contentDao.deleteByBook(oldBook.origin, oldBook.bookUrl);
        }

        if (migratedBook.bookUrl != oldBook.bookUrl) {
          await chaptersDao.deleteByBook(oldBook.bookUrl);
          await books.deleteByUrl(oldBook.bookUrl);
        }
      });
    } catch (_) {
      operationLease?.rolledBack();
      rethrow;
    }

    operationLease?.committed();

    // Cover files are derived storage, not part of database-world validity.
    // Retire them only after the authoritative handoff has committed.
    final retireAssets = _assetRetirer;
    if (sourceIdentityChanged && retireAssets != null) {
      try {
        await retireAssets(oldBook, migratedBook);
        await books.upsert(migratedBook);
      } catch (error, stackTrace) {
        AppLog.e(
          'Source switch committed but old source assets could not be retired: '
          '$error',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    // 從別頁開的閱讀器換源時，那一頁手上還是舊的書（例如書籍詳情）。
    AppEventBus().fire(
      AppEventBus.bookSwitched,
      data: BookSwitchedEvent(
        fromBookUrl: oldBook.bookUrl,
        toBookUrl: migratedBook.bookUrl,
      ),
    );
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

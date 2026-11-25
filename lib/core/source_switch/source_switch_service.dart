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
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/chapter_alignment.dart';
import 'package:night_reader/core/storage/book_toc_reverser.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';
import 'package:pool/pool.dart';

import '../diagnostics/app_log_service.dart';
import '../source/book_source_service.dart';
import '../source/chapter_content_kind.dart';
import 'same_book.dart';
import 'source_switch_operation_lease.dart';

bool isSourceSwitchUnavailable(Object error) {
  if (error is DioException) return error.type != DioExceptionType.cancel;
  return error is AppException || error is TimeoutException;
}

/// 自動換源（ADR 0069）能換過去的書源：啟用、和書同一類（聚合源不算，ADR
/// 0056 照 Legado 只用同一類）、沒有校驗的狀態標記（含付費、需要登入、需要
/// 驗證：背景不等人，ADR 0038）與「AI 修不好」。
bool autoSwitchCandidateSource(BookSource source, BookSourceKind kind) =>
    source.isSearchableFor(kind) &&
    !source.isAggregateSource &&
    !source.groupTags.any(
      (tag) =>
          sourceRuntimeStatusTags.contains(tag) ||
          tag == aiUnfixableSourceGroupTag,
    );

/// 新書源上這本書的詳情與目錄（[loadSourceToc]）：換源清單抓來寫章數，
/// 選它換源時交給 [SourceSwitchService.prepareSwitch]，不用再抓一次。
class SourceToc {
  const SourceToc(this.book, this.chapters);

  /// 照詳情頁補好的書。
  final Book book;

  /// 目錄，不是空的。
  final List<BookChapter> chapters;
}

/// 抓 [candidate] 在書源 [source] 上的詳情與目錄；目錄是空的時丟出
/// [SourceException]（換不過去）。[requireComplete] 時目錄哪一頁抓不到就
/// 整份失敗（[BookSourceService.getChapterList]），不給少了幾頁的目錄。
Future<SourceToc> loadSourceToc(
  BookSourceService service,
  BookSource source,
  SearchBook candidate, {
  bool requireComplete = false,
  CancelToken? cancelToken,
}) async {
  final book = await service.getBookInfo(
    source,
    candidate.toBook(),
    cancelToken: cancelToken,
  );
  final chapters = await service.getChapterList(
    source,
    book,
    requireComplete: requireComplete,
    cancelToken: cancelToken,
  );
  if (chapters.isEmpty) {
    throw SourceException('新來源沒有可用目錄', sourceUrl: candidate.origin);
  }
  return SourceToc(book, chapters);
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
  /// 書名與作者都一樣的這本書（[isSameBook]，同手動換源）。讀到的那一章 [chapterTitle] 在新目錄裡對得上
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
    // 章數一樣時照書源管理的排序（上面排好的順序）。
    final rank = {
      for (final (i, source) in sources.indexed) source.bookSourceUrl: i,
    };
    final pool = Pool(_maxConcurrentSearches);
    try {
      // 背景沒人看：一個書源出了任何錯都只跳過它，不讓整本書放棄；
      // 沒預期的錯記下來。
      Future<T?> skipFailed<T>(String origin, Future<T> Function() work) =>
          pool.withResource(() async {
            if (cancelToken?.isCancelled ?? false) return null;
            try {
              return await work();
            } catch (error, stack) {
              _logUnexpected(origin, error, stack, cancelToken);
              return null;
            }
          });

      // 搜法同手動換源：繁簡兩種書名都搜，書名、作者照 [isSameBook] 比。
      final names = searchKeyVariants(book.name);
      final found = await Future.wait([
        for (final source in sources)
          for (final name in names)
            skipFailed(
              source.bookSourceUrl,
              () => _service.searchBooks(
                source,
                name,
                filter: sameBookFilter(
                  book.name,
                  book.author,
                  checkAuthor: true,
                ),
                shouldBreak: stopAtFirstSearchResult,
                cancelToken: cancelToken,
              ),
            ),
      ]);
      final seen = <String>{};
      final hits = [
        for (final results in found)
          for (final hit in results ?? const <SearchBook>[])
            if (seen.add('${hit.origin}\u0000${hit.bookUrl}')) hit,
      ];

      final aligned = [
        for (final candidate in await Future.wait([
          for (final hit in hits)
            skipFailed(
              hit.origin,
              () => _align(
                book,
                hit,
                targetChapterTitle: chapterTitle,
                cancelToken: cancelToken,
              ),
            ),
        ]))
          // 書的類別由書源的規則寫：換過去類別要一樣（ADR 0053）。
          if (candidate != null &&
              candidate.migratedBook.bookKind == book.bookKind &&
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
        } catch (error, stack) {
          _logUnexpected(
            candidate.source.bookSourceUrl,
            error,
            stack,
            cancelToken,
          );
        }
      }
      return null;
    } finally {
      await pool.close();
    }
  }

  /// 自動換源跳過的候選出的錯：書源搜不到、抓不到、整件被取消是平常的事，
  /// 其他的記下來。
  static void _logUnexpected(
    String origin,
    Object error,
    StackTrace stack,
    CancelToken? cancelToken,
  ) {
    if (isSourceSwitchUnavailable(error) ||
        (cancelToken?.isCancelled ?? false)) {
      return;
    }
    AppLog.e('自動換源：書源 $origin 出錯，跳過', error: error, stackTrace: stack);
  }

  /// [prepared] 改照 [latest] 寫回：準備時用的那份書之後被改過（分組、排序、
  /// 封面、閱讀設定、閱讀時間這類）時，寫回的要是最新的。讀到的那一章
  /// [targetChapterTitle]（沒給照書記的）對到的不是準備好的那一章、或那一章
  /// 的章名不一樣（照比例估到同一個位置）時是 null，要重新準備。
  PreparedSourceSwitch? rebase(
    PreparedSourceSwitch prepared,
    Book latest, {
    String? targetChapterTitle,
  }) {
    final title = targetChapterTitle ?? latest.durChapterTitle;
    if (title == null) return null;
    final alignment = latest.copyWith(durChapterTitle: title);
    final migrated = _migrate(
      alignment,
      prepared.migratedBook,
      prepared.chapters,
    );
    if (migrated.index != prepared.targetChapterIndex ||
        !sameChapterTitle(prepared.chapters[migrated.index].title, title)) {
      return null;
    }
    return PreparedSourceSwitch(
      searchBook: prepared.searchBook,
      source: prepared.source,
      migratedBook: migrated.book,
      chapters: prepared.chapters,
      targetChapterIndex: migrated.index,
      validatedContent: prepared.validatedContent,
    );
  }

  /// [from] 的閱讀進度與書架上的設定搬到新書源的 [to]（[Book.migrateTo]）；
  /// [index] 是讀到的那一章在 [chapters] 的位置。
  static ({Book book, int index}) _migrate(
    Book from,
    Book to,
    List<BookChapter> chapters,
  ) {
    final book = from.migrateTo(to, chapters);
    final index = book.chapterIndex.clamp(0, chapters.length - 1);
    // 有聲書對到同一集就接著聽到的那一秒（charOffset 存毫秒，ADR 0055），
    // 文字書的位置規則不適用。
    if (book.bookKind == BookSourceKind.audio &&
        chapters[index].title == from.durChapterTitle) {
      book.charOffset = from.charOffset;
    }
    return (book: book, index: index);
  }

  /// 換到 [candidate]。[toc] 是換源清單已經抓好的它的詳情與目錄，給了就
  /// 不再抓一次。
  Future<PreparedSourceSwitch> prepareSwitch(
    Book currentBook,
    SearchBook candidate, {
    int? targetChapterIndex,
    String? targetChapterTitle,
    SourceToc? toc,
  }) async => _validate(
    await _align(
      currentBook,
      candidate,
      targetChapterIndex: targetChapterIndex,
      targetChapterTitle: targetChapterTitle,
      toc: toc,
    ),
  );

  /// 換源的前一半：新書源的詳情與目錄，進度照章名對到新目錄
  /// （[Book.migrateTo]）。
  Future<_AlignedSwitch> _align(
    Book currentBook,
    SearchBook candidate, {
    int? targetChapterIndex,
    String? targetChapterTitle,
    SourceToc? toc,
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
    final SourceToc(book: hydratedBook, chapters: fetched) = toc == null
        ? await loadSourceToc(
            _service,
            source,
            candidate,
            cancelToken: cancelToken,
          )
        // 清單留著的那份不改：抓正文時規則會改章節的欄位，換不成再點一次
        // 要用原本的。
        : SourceToc(toc.book, [
            for (final chapter in toc.chapters) chapter.copyWith(),
          ]);
    // 換過去的書帶著這本書的閱讀設定（[Book.migrateTo]，同 Legado），存著的
    // 目錄要照它的反轉目錄排（[BookTocReverser]）；新書源的目錄是照抓的那
    // 一份的設定抓的。
    final chapters =
        (hydratedBook.readConfig?.reverseToc ?? false) ==
            (currentBook.readConfig?.reverseToc ?? false)
        ? fetched
        : reversedToc(fetched);

    final migrated = _migrate(alignmentBook, hydratedBook, chapters);
    return _AlignedSwitch(
      searchBook: candidate,
      source: source,
      migratedBook: migrated.book,
      chapters: chapters,
      targetIndex: migrated.index,
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
      // 暫時連不上的圖留記號，書架自動下載之後再補（同閱讀器抓正文）。
      final pending = await _service.fetchIllustrations(
        source,
        migratedBook,
        validatedContent,
        dir: await BookIllustrationStorage.dirFor(migratedBook),
        cancelToken: cancelToken,
      );
      if (pending > 0) {
        await BookIllustrationStorage.markUnfetched(migratedBook);
      }
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
  ///
  /// [refresh] 在等完舊書源的工作收尾（下載，可能等很久）、動手改書與刪
  /// 舊資料之前呼叫，傳回要換的那本現在的樣子與照它重新對好的結果，換源
  /// 照這一份寫；傳回 null 就放回原狀、不換，傳回 false。自動換源用：等的
  /// 這段時間讀者可能打開過這本、讀了幾頁，或現在還開著。換成了傳回 true。
  Future<bool> commitSwitch(
    Book oldBook,
    PreparedSourceSwitch prepared, {
    BookDao? bookDao,
    ChapterDao? chapterDao,
    Future<({Book book, PreparedSourceSwitch prepared})?> Function()? refresh,
  }) async {
    final books = bookDao ?? getIt<BookDao>();
    final db = books.appDatabase;
    final chaptersDao = chapterDao ?? ChapterDao(db);
    final contentDao = ReaderChapterContentDao(db);
    final sourceIdentityChanged =
        oldBook.origin != prepared.migratedBook.origin ||
        oldBook.bookUrl != prepared.migratedBook.bookUrl;
    final operationLease = sourceIdentityChanged
        ? await _operationQuiescer?.call(oldBook)
        : null;
    if (refresh != null) {
      final ({Book book, PreparedSourceSwitch prepared})? current;
      try {
        current = await refresh();
      } catch (_) {
        operationLease?.rolledBack();
        rethrow;
      }
      // 等的是這本書、這個新書源的工作，換了別本就不算數。
      if (current == null ||
          current.book.bookUrl != oldBook.bookUrl ||
          current.book.origin != oldBook.origin ||
          current.prepared.migratedBook.bookUrl !=
              prepared.migratedBook.bookUrl ||
          current.prepared.migratedBook.origin !=
              prepared.migratedBook.origin) {
        operationLease?.rolledBack();
        return false;
      }
      (oldBook, prepared) = (current.book, current.prepared);
    }
    final migratedBook = prepared.migratedBook;

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
    return true;
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

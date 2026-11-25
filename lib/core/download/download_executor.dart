import 'dart:async';

import 'package:dio/dio.dart';

import 'download_base.dart';
import 'download_scheduler.dart';

import 'package:night_reader/core/comic/comic_chapter_download.dart';
import 'package:night_reader/core/download/audio_chapter_download.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/download/download_failure.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/storage/book_chapter_files.dart';
import 'package:night_reader/core/storage/book_illustration_storage.dart';
import 'package:night_reader/core/source/book_source_service.dart';
import 'package:night_reader/core/storage/chapter_content_preparation_pipeline.dart';
import 'package:night_reader/core/storage/reader_chapter_content_store.dart';

/// 還原備份後（插圖不在備份裡），這本網路書已存的正文裡還有插圖沒試過的
/// 章節網址：只在還原留下記號時才掃，都試過了就把記號刪掉（ADR 0050）。
Future<Set<String>> chaptersWithUntriedIllustrations(Book book) async {
  if (book.isLocal || !await BookIllustrationStorage.isUnfetched(book)) {
    return const {};
  }
  final contents = await getIt<ReaderChapterContentDao>()
      .getStoredContentsWithIllustrations(
        origin: book.origin,
        bookUrl: book.bookUrl,
      );
  final dir = await BookIllustrationStorage.dirFor(book);
  final untried = {
    for (final MapEntry(key: url, value: content) in contents.entries)
      if ((await BookIllustrationStorage.untriedSources(
        dir,
        content,
      )).isNotEmpty)
        url,
  };
  if (untried.isEmpty) await BookIllustrationStorage.clearUnfetched(book);
  return untried;
}

/// [task] 的範圍在目前的目錄 [chapters]（依序號排好）裡要下載的章節；分卷
/// 標題沒有正文、付費還沒買的只會抓到付費提示，都不算。起點或終點那一章
/// 已經不在目錄裡時回傳 null。
List<BookChapter>? chaptersInDownloadScope(
  List<BookChapter> chapters,
  DownloadTask task,
) {
  int find(String url) => chapters.indexWhere((c) => c.url == url);
  final startUrl = task.startChapterUrl;
  final endUrl = task.endChapterUrl;
  final start = startUrl == null ? 0 : find(startUrl);
  final end = endUrl == null ? chapters.length - 1 : find(endUrl);
  if (start < 0 || end < 0) return null;
  return [
    for (var i = start; i <= end; i++)
      if (chapterIsDownloadable(chapters[i])) chapters[i],
  ];
}

/// 抓一章的結果：失敗時帶著給讀者看的說法（[DownloadFailure]，只有字串，
/// 送得回主 isolate）。
class DownloadChapterResult {
  const DownloadChapterResult._(this.failure);

  const DownloadChapterResult.ready() : this._(null);

  const DownloadChapterResult.failed(DownloadFailure failure) : this._(failure);

  final DownloadFailure? failure;

  bool get success => failure == null;
}

/// 一個任務這次要抓的章節：照目前的目錄換算範圍，扣掉已經有正文的。
class DownloadPlan {
  const DownloadPlan({
    required this.run,
    required this.total,
    required this.ready,
    required this.missing,
  });

  /// 這一輪下載在書源 isolate 的編號：逐章抓取共用同一份書與章節，跑完
  /// 交給 [finishDownloadRunInSourceIsolate] 放掉。只在規劃它的那一條書源
  /// isolate 有效，之後的呼叫都帶同一本書的網址，送到同一條。
  final int run;

  /// 範圍裡要下載的章數（已下載的也算）。
  final int total;

  /// 其中已經有正文的章數。
  final int ready;

  /// 還沒有正文、這次要抓的章節，照目錄順序。
  final List<({int index, String url, String title})> missing;
}

/// 下載的目錄比對與抓取寫入在書源 isolate 做（ADR 0028）：上千章的目錄、
/// 每章的正文都不複製回主 isolate，主 isolate 只收章節的序號與網址、每章
/// 成功或失敗。原本在主 isolate 逐章查「下載過沒有」、更新進度，幾千章的
/// 書一開跑就連續佔住主執行緒，疊到換場與骨架上（ADR 0018）。工作會送進
/// 書源 isolate，所以在頂層函式裡建立，只捕捉任務與字串。
Future<DownloadPlan> planDownloadInSourceIsolate(
  DownloadTask task, {
  CancelToken? cancelToken,
}) => SourceIsolate.run(
  (cancelToken) => _planDownload(task, cancelToken),
  affinity: task.bookUrl,
  cancelToken: cancelToken,
);

/// 抓 [bookUrl] 第 [run] 輪的一章正文寫進資料庫；已經有正文就不抓。
/// [cancelToken] 取消時請求與重試跟著停，什麼都不寫。
Future<DownloadChapterResult> downloadChapterInSourceIsolate({
  required String bookUrl,
  required int run,
  required String chapterUrl,
  required int maxAttempts,
  CancelToken? cancelToken,
}) => SourceIsolate.run(
  (cancelToken) => _downloadChapter(run, chapterUrl, maxAttempts, cancelToken),
  affinity: bookUrl,
  cancelToken: cancelToken,
);

/// [bookUrl] 第 [run] 輪下載結束（跑完、失敗、暫停或退役），放掉它的書與
/// 章節。
Future<void> finishDownloadRunInSourceIsolate(String bookUrl, int run) =>
    SourceIsolate.run(
      (_) async => _downloadRuns.remove(run),
      affinity: bookUrl,
    );

/// 書源 isolate 裡進行中的每一輪下載：整輪共用同一份書、書源與章節，和
/// 原本在主 isolate 時一樣。規則在抓目錄或某一章時寫進書與章節的變數
/// （`book.putVariable`），後面的章節要讀得到；每章重新從資料庫讀會丟掉
/// 它們。頂層變數每個 isolate 各一份，這份在書源 isolate。
final Map<
  int,
  ({Book book, BookSource? source, Map<String, BookChapter> chapters})
>
_downloadRuns = {};
int _nextDownloadRun = 0;

Future<DownloadPlan> _planDownload(
  DownloadTask task,
  CancelToken cancelToken,
) async {
  final book = await getIt<BookDao>().getByUrl(task.bookUrl);
  if (book == null) throw DownloadFailure.bookRemoved;
  final source = book.isLocal
      ? null
      : await getIt<BookSourceDao>().getByUrl(book.origin);
  if (!book.isLocal && source == null) throw DownloadFailure.sourceDeleted;
  final chapterDao = getIt<ChapterDao>();
  var chapters = await chapterDao.getByBook(task.bookUrl);
  if (chapters.isEmpty) {
    // 本地書的目錄在加入時就建好，沒有就是檔案讀不出章節。
    if (source == null) throw DownloadFailure.sourceBroken(DownloadPart.toc);
    try {
      chapters = await BookSourceService().getChapterList(
        source,
        book,
        cancelToken: cancelToken,
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) rethrow;
      throw DownloadFailure.of(error, part: DownloadPart.toc);
    } on Exception catch (error) {
      throw DownloadFailure.of(error, part: DownloadPart.toc);
    }
    // 抓不到目錄就記為失敗，書架自動下載照重試規則隔一天再試，不會
    // 每次開 App 都打一次書源（ADR 0008）。
    if (chapters.isEmpty) throw DownloadFailure.sourceBroken(DownloadPart.toc);
    await chapterDao.insertChapters(chapters);
  }
  // 範圍用章節網址記，這時才對照目前的目錄換算（ADR 0008），排隊或
  // 暫停期間書源插章、刪章都不會選到別章。
  final scope = chaptersInDownloadScope(chapters, task);
  if (scope == null) throw DownloadFailure.rangeGone;
  final List<({int index, String url, String title})> missing;
  if (book.bookKind == BookSourceKind.audio) {
    // 有聲書一集一個音訊檔（ADR 0055）。
    final downloaded = await BookChapterFiles.downloaded(book);
    missing = [
      for (final chapter in scope)
        if (!downloaded.containsKey(BookChapterFiles.baseNameFor(chapter)))
          (index: chapter.index, url: chapter.url, title: chapter.title),
    ];
  } else if (book.bookKind == BookSourceKind.comic) {
    // 漫畫一話一個 CBZ（ADR 0052），不看資料庫裡的正文。
    final downloaded = await downloadedComicChapterUrls(book, scope);
    final pending = [
      for (final chapter in scope)
        if (!downloaded.contains(chapter.url))
          (index: chapter.index, url: chapter.url, title: chapter.title),
    ];
    // 從讀到的那話往後先抓，再補前面的（ADR 0052）：還原備份後整本都缺時，
    // 正在讀的地方不用等前面幾百話。
    final reading = book.chapterIndex;
    missing = [
      ...pending.where((chapter) => chapter.index >= reading),
      ...pending.where((chapter) => chapter.index < reading),
    ];
  } else {
    final stored = await getIt<ReaderChapterContentDao>().getStoredChapterUrls(
      origin: book.origin,
      bookUrl: book.bookUrl,
    );
    final unfetched = await chaptersWithUntriedIllustrations(book);
    missing = [
      for (final chapter in scope)
        if (!stored.contains(chapter.url) || unfetched.contains(chapter.url))
          (index: chapter.index, url: chapter.url, title: chapter.title),
    ];
  }
  final run = _nextDownloadRun++;
  _downloadRuns[run] = (
    book: book,
    source: source,
    chapters: {for (final chapter in scope) chapter.url: chapter},
  );
  return DownloadPlan(
    run: run,
    total: scope.length,
    ready: scope.length - missing.length,
    missing: missing,
  );
}

/// 抓一章；失敗在這裡照錯誤種類換成給讀者看的說法（錯誤還保有型別），
/// 只有取消照樣丟出。
Future<DownloadChapterResult> _downloadChapter(
  int run,
  String chapterUrl,
  int maxAttempts,
  CancelToken cancelToken,
) async {
  final state = _downloadRuns[run];
  // 這一輪已經放掉：只有結束或退役時會這樣，主 isolate 那邊也已取消。
  if (state == null) {
    return const DownloadChapterResult.failed(DownloadFailure.appError);
  }
  final book = state.book;
  final part = switch (book.bookKind) {
    BookSourceKind.comic => DownloadPart.images,
    BookSourceKind.audio => DownloadPart.audio,
    _ => DownloadPart.content,
  };
  try {
    return await _downloadChapterOf(
      state,
      chapterUrl,
      maxAttempts,
      cancelToken,
    );
  } on DioException catch (error) {
    if (error.type == DioExceptionType.cancel) rethrow;
    return DownloadChapterResult.failed(DownloadFailure.of(error, part: part));
  } catch (error, stackTrace) {
    if (cancelToken.cancelError case final cancelled?) throw cancelled;
    final failure = DownloadFailure.of(error, part: part);
    // 原始錯誤只進 App 日誌；認不得的連堆疊一起記，回報時查得到。
    if (identical(failure, DownloadFailure.appError)) {
      AppLog.e(
        '下載 ${book.name} 的一章失敗: $error',
        error: error,
        stackTrace: stackTrace,
      );
    } else {
      AppLog.w('下載 ${book.name} 的一章失敗: $error');
    }
    return DownloadChapterResult.failed(failure);
  }
}

Future<DownloadChapterResult> _downloadChapterOf(
  ({Book book, BookSource? source, Map<String, BookChapter> chapters}) state,
  String chapterUrl,
  int maxAttempts,
  CancelToken cancelToken,
) async {
  final book = state.book;
  final source = state.source;
  final chapter = state.chapters[chapterUrl];
  if (chapter == null) {
    return const DownloadChapterResult.failed(DownloadFailure.rangeGone);
  }
  if (!book.isLocal && source == null) {
    return const DownloadChapterResult.failed(DownloadFailure.sourceDeleted);
  }
  if (book.bookKind == BookSourceKind.comic) {
    await ComicChapterDownload.download(
      source!,
      book,
      chapter,
      cancelToken: cancelToken,
    );
    return const DownloadChapterResult.ready();
  }
  if (book.bookKind == BookSourceKind.audio) {
    await AudioChapterDownload.download(
      source!,
      book,
      chapter,
      cancelToken: cancelToken,
    );
    return const DownloadChapterResult.ready();
  }
  final chapterDao = getIt<ChapterDao>();
  final store = ReaderChapterContentStore(
    chapterDao: chapterDao,
    contentDao: getIt<ReaderChapterContentDao>(),
  );
  final pipeline = ChapterContentPreparationPipeline(
    book: book,
    contentStore: store,
    sourceDao: getIt<BookSourceDao>(),
    service: BookSourceService(),
    getSource: () => source,
  );
  // 排進來之後閱讀器可能已經抓好這一章；還原備份帶回的正文則只補抓插圖，
  // 不換掉正文（ADR 0008、0050）。
  final stored = await store.getContentEntry(book: book, chapter: chapter);
  if (stored != null && stored.isReady && stored.hasDisplayContent) {
    final complete = await pipeline.fetchStoredIllustrations(
      stored.content!,
      sourceOverride: source,
      cancelToken: cancelToken,
    );
    return complete
        ? const DownloadChapterResult.ready()
        : const DownloadChapterResult.failed(
            DownloadFailure.illustrationsMissing,
          );
  }
  // 下載是自動補抓：抓的期間使用者借來或重新取得這一章時，晚到的這份不蓋
  // 掉它（ADR 0080）。
  final result = await pipeline.prepare(
    chapterIndex: chapter.index,
    chapter: chapter,
    sourceOverride: source,
    maxAttempts: maxAttempts,
    cancelToken: cancelToken,
  );
  if (!result.isReady) {
    AppLog.w(
      '下載 ${book.name} 的「${chapter.title}」失敗: '
      '${result.failureCause ?? result.failureMessage}',
    );
    return DownloadChapterResult.failed(
      DownloadFailure.of(
        result.failureCause ?? DownloadFailure.appError,
        part: DownloadPart.content,
      ),
    );
  }
  // 正文存好了，但有圖連不上：這章照下載失敗的重試規則再補圖（ADR 0050）。
  return await pipeline.illustrationsSettled(result.content)
      ? const DownloadChapterResult.ready()
      : const DownloadChapterResult.failed(
          DownloadFailure.illustrationsMissing,
        );
}

/// [chapters] 裡已經下載好（CBZ 在）的漫畫章節網址。
Future<Set<String>> downloadedComicChapterUrls(
  Book book,
  List<BookChapter> chapters,
) async {
  final files = await BookChapterFiles.downloaded(book);
  return {
    for (final chapter in chapters)
      if (files[BookChapterFiles.baseNameFor(chapter)]?.path.endsWith(
            ComicChapterDownload.cbzExtension,
          ) ??
          false)
        chapter.url,
  };
}

/// DownloadService 的任務執行邏輯擴展
mixin DownloadExecutor on DownloadBase, DownloadScheduler {
  @override
  Future<void> processTask(DownloadTask task) async {
    if (isTaskRetiring(task.bookUrl)) return;
    beginTaskActivity(task.bookUrl);
    final cancelToken = beginRun(task.bookUrl);
    activeTaskUrls.add(task.bookUrl);
    task.status = DownloadTask.statusDownloading;
    task.successCount = 0;
    task.errorCount = 0;
    task.clearFailure();
    await downloadDao.updateProgress(
      task.bookUrl,
      status: DownloadTask.statusDownloading,
      successCount: 0,
      errorCount: 0,
      failureOf: task,
    );
    update();

    var stoppedEarly = false;
    int? run;
    try {
      final plan = await planDownloadInSourceIsolate(
        task,
        cancelToken: cancelToken,
      );
      run = plan.run;
      // 這一輪被停下（退役、書源改網址）的話，規劃好的結果不寫進任務；
      // 照取消收尾（下面的 catch 不把取消記成失敗）。
      if (cancelToken.cancelError case final cancelled?) throw cancelled;
      // 進度是範圍裡每一章各算一次：已經有正文的直接算完成。總數照這次
      // 換算的範圍：排進來時可能還沒有目錄，排隊期間目錄也可能多了章節。
      // 只改還在的那一列：這一輪抓目錄時被讀者從佇列刪掉的，不寫回來。
      if (plan.total != task.totalCount) {
        task.totalCount = plan.total;
        await downloadDao.updateProgress(
          task.bookUrl,
          totalCount: task.totalCount,
        );
      }
      if (plan.ready > 0) {
        task.successCount = plan.ready;
        task.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
        await downloadDao.updateProgress(
          task.bookUrl,
          successCount: task.successCount,
          errorCount: task.errorCount,
        );
        update();
      }
      var poolCount = 0;
      var consecutiveFailures = 0;
      // 有一章結束時叫醒等名額或等收尾的地方。
      Completer<void>? chapterEnded;
      void endChapter() {
        poolCount--;
        chapterEnded?.complete();
        chapterEnded = null;
      }

      Future<void> nextChapterEnd() =>
          (chapterEnded ??= Completer<void>()).future;
      for (final chapter in plan.missing) {
        // 連續好幾章都失敗多半是書源壞了：整個任務先記為失敗，不把剩下的
        // 章節一章章打完（書架自動下載何時再試見 ADR 0008）。
        if (consecutiveFailures >= _maxConsecutiveFailures) break;
        if (!await _mayContinue(task, cancelToken)) {
          stoppedEarly = true;
          break;
        }

        while (poolCount >= maxChapterConcurrent && !cancelToken.isCancelled) {
          await Future.any<Object?>([nextChapterEnd(), cancelToken.whenCancel]);
        }
        // 等名額期間可能被暫停或退役，開抓前再看一次。
        if (!await _mayContinue(task, cancelToken)) {
          stoppedEarly = true;
          break;
        }

        poolCount++;
        unawaited(() async {
          // 每章不論怎麼結束都只放掉一次名額：名額提早歸零的話，退役會在
          // 這章還沒結束時就刪資料，這章之後又把正文寫回去。
          try {
            DownloadChapterResult result;
            try {
              result = await downloadChapterInSourceIsolate(
                bookUrl: task.bookUrl,
                run: plan.run,
                chapterUrl: chapter.url,
                maxAttempts: _maxRetries,
                cancelToken: cancelToken,
              );
            } catch (error) {
              // 退役取消的不是失敗：不記錯誤、不寫進度。
              if (cancelToken.isCancelled) return;
              // 書源 isolate 自己接不住的（例如它掛了），只剩這裡判斷得到。
              AppLog.w('Download chapter failed ${chapter.title}: $error');
              result = DownloadChapterResult.failed(
                DownloadFailure.of(error, part: DownloadPart.content),
              );
            }
            // 結果回來前這一輪已被停下：放行後整輪重來，這章不算成功也不算
            // 失敗（正文若已存好，下一輪規劃時會算成已下載）。
            if (cancelToken.isCancelled) return;
            if (result.failure case final failure?) {
              task.errorCount++;
              consecutiveFailures++;
              task.setFailure(
                reason: failure.reason,
                message: failure.message,
                chapterIndex: chapter.index,
              );
            } else {
              task.successCount++;
              consecutiveFailures = 0;
            }
            task.currentChapterIndex = chapter.index;
            task.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
            unawaited(
              downloadDao.updateProgress(
                task.bookUrl,
                currentChapterIndex: chapter.index,
                successCount: task.successCount,
                errorCount: task.errorCount,
                failureOf: result.success ? null : task,
              ),
            );
            update();
          } finally {
            endChapter();
          }
        }());
      }

      while (poolCount > 0) {
        await nextChapterEnd();
      }

      // 被停下的一輪（最後一批章節已送出、迴圈照常走完時也一樣）不結算：
      // 狀態留給停下它的那一方（退役刪掉任務、書源改網址放行後排回去）。
      if (!stoppedEarly &&
          !cancelToken.isCancelled &&
          task.status != DownloadTask.statusPaused) {
        task.status = task.errorCount > 0
            ? DownloadTask.statusFailed
            : DownloadTask.statusCompleted;
        task.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
        await downloadDao.updateProgress(task.bookUrl, status: task.status);
        AppEventBus().fire(AppEventBus.upBookshelf, data: task.bookUrl);
      }
    } catch (e, stack) {
      // 退役取消的不是失敗：不記錯誤、不改狀態，交給退役的那一方處理。
      if (!cancelToken.isCancelled) {
        AppLog.e(
          'Download task failed for ${task.bookName}: $e',
          error: e,
          stackTrace: stack,
        );
      }
      if (!cancelToken.isCancelled &&
          task.status != DownloadTask.statusPaused) {
        // 規劃時（找書、找書源、抓目錄）的失敗在書源 isolate 已經判斷好。
        final failure = DownloadFailure.of(e, part: DownloadPart.toc);
        task.setFailure(reason: failure.reason, message: failure.message);
        task.status = DownloadTask.statusFailed;
        task.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
        await downloadDao.updateProgress(
          task.bookUrl,
          status: DownloadTask.statusFailed,
          failureOf: task,
        );
      }
    } finally {
      // 已經開抓的章節在開始時就拿到了書與章節，放掉不影響它們跑完。
      if (run != null) {
        unawaited(
          finishDownloadRunInSourceIsolate(task.bookUrl, run).catchError((
            Object error,
          ) {
            AppLog.w('下載結束時放掉書源 isolate 的狀態失敗: $error');
          }),
        );
      }
      activeTaskUrls.remove(task.bookUrl);
      endRun(task.bookUrl, cancelToken);
      completeTaskActivity(task.bookUrl);
    }
    update();
    onTaskFinished(task);
  }

  static const int _maxRetries = 3;

  /// 連續失敗幾章就停下整個任務：同時最多抓 [maxChapterConcurrent]（5）章，
  /// 10 章是連續兩輪全部失敗（每章已各自重試 [_maxRetries] 次）。
  static const int _maxConsecutiveFailures = 10;

  /// 整個下載沒停、這本沒暫停也沒退役、這一輪沒被停下；全域暫停時等到
  /// 繼續。
  Future<bool> _mayContinue(DownloadTask task, CancelToken cancelToken) async {
    if (!isDownloading ||
        task.status == DownloadTask.statusPaused ||
        isTaskRetiring(task.bookUrl)) {
      return false;
    }
    return waitUntilTaskRunnable(task.bookUrl, cancelToken: cancelToken);
  }
}

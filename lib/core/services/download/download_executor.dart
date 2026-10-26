import 'dart:async';

import 'package:dio/dio.dart';

import 'download_base.dart';
import 'download_scheduler.dart';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/exception/user_error.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chapter_content_preparation_pipeline.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';

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

class DownloadChapterResult {
  const DownloadChapterResult._({required this.success, this.failureMessage});

  final bool success;
  final String? failureMessage;

  factory DownloadChapterResult.ready() {
    return const DownloadChapterResult._(success: true);
  }

  factory DownloadChapterResult.failed(String message) {
    return DownloadChapterResult._(
      success: false,
      failureMessage: message.isEmpty ? '下載失敗' : message,
    );
  }
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
  if (book == null) {
    throw Exception('書籍不存在');
  }
  final source = book.origin == 'local'
      ? null
      : await getIt<BookSourceDao>().getByUrl(book.origin);
  if (book.origin != 'local' && source == null) {
    throw Exception('書源不存在');
  }
  final chapterDao = getIt<ChapterDao>();
  var chapters = await chapterDao.getByBook(task.bookUrl);
  if (chapters.isEmpty) {
    if (source == null) {
      throw Exception('章節目錄不存在');
    }
    chapters = await BookSourceService().getChapterList(
      source,
      book,
      cancelToken: cancelToken,
    );
    // 抓不到目錄就記為失敗，書架自動下載照重試規則隔一天再試，不會
    // 每次開 App 都打一次書源（ADR 0008）。
    if (chapters.isEmpty) {
      throw Exception('章節目錄為空');
    }
    await chapterDao.insertChapters(chapters);
  }
  // 範圍用章節網址記，這時才對照目前的目錄換算（ADR 0008），排隊或
  // 暫停期間書源插章、刪章都不會選到別章。
  final scope = chaptersInDownloadScope(chapters, task);
  if (scope == null) {
    throw Exception('選的章節已不在目錄裡，請重新選擇範圍');
  }
  final stored = await getIt<ReaderChapterContentDao>().getStoredChapterUrls(
    origin: book.origin,
    bookUrl: book.bookUrl,
  );
  final missing = [
    for (final chapter in scope)
      if (!stored.contains(chapter.url))
        (index: chapter.index, url: chapter.url, title: chapter.title),
  ];
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

Future<DownloadChapterResult> _downloadChapter(
  int run,
  String chapterUrl,
  int maxAttempts,
  CancelToken cancelToken,
) async {
  final state = _downloadRuns[run];
  if (state == null) return DownloadChapterResult.failed('下載已結束');
  final book = state.book;
  final source = state.source;
  final chapter = state.chapters[chapterUrl];
  if (chapter == null) return DownloadChapterResult.failed('章節不存在');
  final chapterDao = getIt<ChapterDao>();
  final store = ReaderChapterContentStore(
    chapterDao: chapterDao,
    contentDao: getIt<ReaderChapterContentDao>(),
  );
  // 排進來之後閱讀器可能已經抓好這一章。
  if (await store.hasReadyContent(book: book, chapter: chapter)) {
    return DownloadChapterResult.ready();
  }
  final result =
      await ChapterContentPreparationPipeline(
        book: book,
        contentStore: store,
        sourceDao: getIt<BookSourceDao>(),
        service: BookSourceService(),
        getSource: () => source,
      ).prepare(
        chapterIndex: chapter.index,
        chapter: chapter,
        sourceOverride: source,
        forceRefresh: true,
        maxAttempts: maxAttempts,
        cancelToken: cancelToken,
      );
  if (result.isReady) return DownloadChapterResult.ready();
  return DownloadChapterResult.failed(result.failureMessage ?? result.content);
}

String classifyDownloadFailureReason(String message) {
  final text = message.toLowerCase();
  if (text.contains('permission') ||
      text.contains('denied') ||
      message.contains('權限')) {
    return '權限問題';
  }
  if (text.contains('no space') ||
      text.contains('disk full') ||
      message.contains('儲存空間不足') ||
      message.contains('空間不足')) {
    return '儲存空間不足';
  }
  if (message.contains('找不到書源') ||
      message.contains('書源不存在') ||
      message.contains('書源失效')) {
    return '書源失效';
  }
  if (message.contains('內容為空') ||
      message.contains('解析規則') ||
      message.contains('正文解析')) {
    return '正文解析失敗';
  }
  if (text.contains('404') ||
      text.contains('not found') ||
      message.contains('章節不存在')) {
    return '章節不存在';
  }
  if (text.contains('socketexception') ||
      text.contains('timeoutexception') ||
      text.contains('timeout') ||
      text.contains('connection') ||
      text.contains('dioexception') ||
      message.contains('網路')) {
    return '網路錯誤';
  }
  return '下載失敗';
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
      // 進度是範圍裡每一章各算一次：已經有正文的直接算完成。總數照這次
      // 換算的範圍：排進來時可能還沒有目錄，排隊期間目錄也可能多了章節。
      if (plan.total != task.totalCount) {
        task.totalCount = plan.total;
        await downloadDao.upsert(task);
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
        if (!await _mayContinue(task)) {
          stoppedEarly = true;
          break;
        }

        while (poolCount >= maxChapterConcurrent && !cancelToken.isCancelled) {
          await Future.any<Object?>([nextChapterEnd(), cancelToken.whenCancel]);
        }
        // 等名額期間可能被暫停或退役，開抓前再看一次。
        if (!await _mayContinue(task)) {
          stoppedEarly = true;
          break;
        }

        poolCount++;
        unawaited(() async {
          // 每章不論怎麼結束都只放掉一次名額：名額提早歸零的話，退役會在
          // 這章還沒結束時就刪資料，這章之後又把正文寫回去。
          try {
            DownloadChapterResult result;
            // 分類看原文（英文例外名稱也算數），畫面上的原因用白話。
            String rawFailure;
            try {
              result = await downloadChapterInSourceIsolate(
                bookUrl: task.bookUrl,
                run: plan.run,
                chapterUrl: chapter.url,
                maxAttempts: _maxRetries,
                cancelToken: cancelToken,
              );
              rawFailure = result.failureMessage ?? '';
            } catch (error) {
              // 退役取消的不是失敗：不記錯誤、不寫進度。
              if (cancelToken.isCancelled) return;
              AppLog.w('Download chapter failed ${chapter.title}: $error');
              result = DownloadChapterResult.failed(userErrorReason(error));
              rawFailure = error.toString();
            }
            if (result.success) {
              task.successCount++;
              consecutiveFailures = 0;
            } else {
              task.errorCount++;
              consecutiveFailures++;
              task.setFailure(
                reason: classifyDownloadFailureReason(rawFailure),
                message: result.failureMessage!,
                chapterIndex: chapter.index,
              );
            }
            task.currentChapterIndex = chapter.index;
            task.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
            unawaited(
              downloadDao.updateProgress(
                task.bookUrl,
                currentChapterIndex: chapter.index,
                successCount: task.successCount,
                errorCount: task.errorCount,
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

      if (!stoppedEarly && task.status != DownloadTask.statusPaused) {
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
        task.setFailure(
          reason: classifyDownloadFailureReason(e.toString()),
          message: userErrorReason(e),
        );
        task.status = DownloadTask.statusFailed;
        task.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
        await downloadDao.updateProgress(
          task.bookUrl,
          status: DownloadTask.statusFailed,
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

  /// 整個下載沒停、這本沒暫停也沒退役；全域暫停時等到繼續。
  Future<bool> _mayContinue(DownloadTask task) async {
    if (!isDownloading ||
        task.status == DownloadTask.statusPaused ||
        isTaskRetiring(task.bookUrl)) {
      return false;
    }
    return waitUntilTaskRunnable(task.bookUrl);
  }
}

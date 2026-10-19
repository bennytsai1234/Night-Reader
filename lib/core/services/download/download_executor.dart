import 'dart:async';

import 'download_base.dart';
import 'download_scheduler.dart';

import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/exception/user_error.dart';
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
    required this.total,
    required this.ready,
    required this.missing,
  });

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
Future<DownloadPlan> planDownloadInSourceIsolate(DownloadTask task) =>
    SourceIsolate.run((_) => _planDownload(task));

/// 抓一章正文寫進資料庫；已經有正文就不抓。
Future<DownloadChapterResult> downloadChapterInSourceIsolate({
  required String bookUrl,
  required String chapterUrl,
  required int maxAttempts,
}) => SourceIsolate.run(
  (_) => _downloadChapter(bookUrl, chapterUrl, maxAttempts),
);

Future<DownloadPlan> _planDownload(DownloadTask task) async {
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
    chapters = await BookSourceService().getChapterList(source, book);
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
  return DownloadPlan(
    total: scope.length,
    ready: scope.length - missing.length,
    missing: missing,
  );
}

Future<DownloadChapterResult> _downloadChapter(
  String bookUrl,
  String chapterUrl,
  int maxAttempts,
) async {
  final book = await getIt<BookDao>().getByUrl(bookUrl);
  if (book == null) return DownloadChapterResult.failed('書籍不存在');
  final chapterDao = getIt<ChapterDao>();
  final chapter = await chapterDao.getByUrl(chapterUrl);
  if (chapter == null) return DownloadChapterResult.failed('章節不存在');
  final store = ReaderChapterContentStore(
    chapterDao: chapterDao,
    contentDao: getIt<ReaderChapterContentDao>(),
  );
  // 排進來之後閱讀器可能已經抓好這一章。
  if (await store.hasReadyContent(book: book, chapter: chapter)) {
    return DownloadChapterResult.ready();
  }
  final sourceDao = getIt<BookSourceDao>();
  final source = book.origin == 'local'
      ? null
      : await sourceDao.getByUrl(book.origin);
  final result =
      await ChapterContentPreparationPipeline(
        book: book,
        contentStore: store,
        sourceDao: sourceDao,
        service: BookSourceService(),
        getSource: () => source,
      ).prepare(
        chapterIndex: chapter.index,
        chapter: chapter,
        sourceOverride: source,
        forceRefresh: true,
        maxAttempts: maxAttempts,
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
    try {
      final plan = await planDownloadInSourceIsolate(task);
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
      for (final chapter in plan.missing) {
        // 連續好幾章都失敗多半是書源壞了：整個任務先記為失敗，不把剩下的
        // 章節一章章打完（書架自動下載何時再試見 ADR 0008）。
        if (consecutiveFailures >= _maxConsecutiveFailures) break;
        if (!await _mayContinue(task)) {
          stoppedEarly = true;
          break;
        }

        while (poolCount >= maxChapterConcurrent &&
            !isTaskRetiring(task.bookUrl)) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
        // 等名額期間可能被暫停或退役，開抓前再看一次。
        if (!await _mayContinue(task)) {
          stoppedEarly = true;
          break;
        }

        poolCount++;
        unawaited(
          downloadChapterInSourceIsolate(
                bookUrl: task.bookUrl,
                chapterUrl: chapter.url,
                maxAttempts: _maxRetries,
              )
              .then((result) {
                if (result.success) {
                  task.successCount++;
                  consecutiveFailures = 0;
                } else {
                  task.errorCount++;
                  consecutiveFailures++;
                  final message = result.failureMessage ?? '下載失敗';
                  task.setFailure(
                    reason: classifyDownloadFailureReason(message),
                    message: message,
                    chapterIndex: chapter.index,
                  );
                }
                poolCount--;
                task.currentChapterIndex = chapter.index;
                task.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
                downloadDao.updateProgress(
                  task.bookUrl,
                  currentChapterIndex: chapter.index,
                  successCount: task.successCount,
                  errorCount: task.errorCount,
                );
                update();
              })
              .catchError((Object error, StackTrace stack) {
                AppLog.w('Download chapter failed ${chapter.title}: $error');
                task.errorCount++;
                consecutiveFailures++;
                // 分類看原文（英文例外名稱也算數），畫面上的原因用白話。
                task.setFailure(
                  reason: classifyDownloadFailureReason(error.toString()),
                  message: userErrorReason(error),
                  chapterIndex: chapter.index,
                );
                poolCount--;
                task.currentChapterIndex = chapter.index;
                task.lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
                downloadDao.updateProgress(
                  task.bookUrl,
                  currentChapterIndex: chapter.index,
                  successCount: task.successCount,
                  errorCount: task.errorCount,
                );
                update();
              }),
        );
      }

      while (poolCount > 0) {
        await Future.delayed(const Duration(seconds: 1));
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
      AppLog.e(
        'Download task failed for ${task.bookName}: $e',
        error: e,
        stackTrace: stack,
      );
      if (task.status != DownloadTask.statusPaused) {
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
      activeTaskUrls.remove(task.bookUrl);
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

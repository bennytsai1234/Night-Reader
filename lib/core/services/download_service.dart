import 'dart:async';

import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/core/services/source_switch_handoff.dart';

import 'download/download_base.dart';
import 'download/download_scheduler.dart';
import 'download/download_executor.dart';

export 'download/download_base.dart';
export 'download/download_scheduler.dart';
export 'download/download_executor.dart';

/// 失敗的書架自動下載，要隔多久才在開 App 時自動再試（ADR 0008）。
const Duration shelfDownloadRetryInterval = Duration(hours: 24);

enum ShelfDownloadDecision {
  /// 排進佇列。
  queue,

  /// 這本書的任務正在跑，等這輪結束再排。
  afterCurrentRun,

  /// 不動：使用者暫停的，或剛失敗、還沒到重試時間的。
  leave,
}

/// 書架自動下載對一本還有章節沒下載的書該怎麼做（ADR 0008）。
ShelfDownloadDecision decideShelfDownload({
  required DownloadTask? task,
  required bool running,
  required bool hasNewChapters,
  required int now,
}) {
  if (running || task != null && (task.isWaiting || task.isDownloading)) {
    return ShelfDownloadDecision.afterCurrentRun;
  }
  if (task == null || task.isCompleted) return ShelfDownloadDecision.queue;
  if (task.isPaused) return ShelfDownloadDecision.leave;
  // 失敗過：剛抓到新章節（書源此刻能用）就再試；否則至少隔一段時間。
  final waited = now - task.lastUpdateTime;
  return hasNewChapters || waited >= shelfDownloadRetryInterval.inMilliseconds
      ? ShelfDownloadDecision.queue
      : ShelfDownloadDecision.leave;
}

/// DownloadService - 書籍章節背景下載服務
class DownloadService extends DownloadBase
    with DownloadScheduler, DownloadExecutor {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;

  late final Future<void> _initialization;

  double get progress => totalProgress;

  DownloadService._internal() {
    _initialization = _loadTasks();
  }

  Future<SourceSwitchOperationLease> quiesceForSourceSwitch(
    Book oldBook,
  ) async {
    await _initialization;
    final bookUrl = oldBook.bookUrl;
    markTaskRetiring(bookUrl);

    final task = tasks.cast<DownloadTask?>().firstWhere(
      (candidate) => candidate?.bookUrl == bookUrl,
      orElse: () => null,
    );
    final previousStatus = task?.status;
    if (task != null) {
      task.status = DownloadTask.statusPaused;
      update();
    }

    await waitForTaskIdle(bookUrl);
    return _DownloadSourceSwitchLease(
      owner: this,
      bookUrl: bookUrl,
      task: task,
      previousStatus: previousStatus,
    );
  }

  void _commitSourceSwitchRetirement(String bookUrl) {
    tasks.removeWhere((task) => task.bookUrl == bookUrl);
    clearTaskRetiring(bookUrl);
    update();
  }

  void _rollbackSourceSwitchRetirement(
    String bookUrl,
    DownloadTask? task,
    int? previousStatus,
  ) {
    if (task != null && previousStatus != null) {
      task.status = previousStatus == DownloadTask.statusDownloading
          ? DownloadTask.statusWaiting
          : previousStatus;
      if (!tasks.contains(task)) {
        tasks.add(task);
      }
    }
    clearTaskRetiring(bookUrl);
    update();
    if (task != null && task.isWaiting && !isDownloading) {
      startDownloads();
    }
  }

  /// 從資料庫恢復任務
  Future<void> _loadTasks() async {
    final storedTasks = await downloadDao.getAll();
    for (final task in storedTasks.where((task) => task.isDownloading)) {
      task.status = DownloadTask.statusWaiting;
      await downloadDao.updateProgress(
        task.bookUrl,
        status: DownloadTask.statusWaiting,
      );
    }
    tasks.clear();
    tasks.addAll(storedTasks);
    update();
    if (tasks.any((t) => t.isWaiting || t.isDownloading) && !isDownloading) {
      unawaited(startDownloads());
    }
  }

  void pauseTask(String bookUrl) {
    final task = tasks.cast<DownloadTask?>().firstWhere(
      (t) => t?.bookUrl == bookUrl,
      orElse: () => null,
    );
    if (task != null) {
      task.status = DownloadTask.statusPaused;
      downloadDao.updateProgress(bookUrl, status: DownloadTask.statusPaused);
      update();
    }
  }

  void resumeTask(String bookUrl) {
    final task = tasks.cast<DownloadTask?>().firstWhere(
      (t) => t?.bookUrl == bookUrl,
      orElse: () => null,
    );
    if (task == null) return;

    // 只恢復這一本；「暫停全部」仍生效時它排隊等待，要等恢復全部才會開始。
    task.status = DownloadTask.statusWaiting;
    downloadDao.updateProgress(bookUrl, status: DownloadTask.statusWaiting);
    update();
    if (!isDownloading) {
      startDownloads();
    }
  }

  void retryTask(String bookUrl) {
    final task = tasks.cast<DownloadTask?>().firstWhere(
      (t) => t?.bookUrl == bookUrl,
      orElse: () => null,
    );
    // 下載中或排隊中的任務不能重試：那一輪還在跑，歸零計數會把失敗章節當成完成。
    if (task == null || task.isDownloading || task.isWaiting) return;

    task
      ..status = DownloadTask.statusWaiting
      ..currentChapterIndex = task.startChapterIndex
      ..successCount = 0
      ..errorCount = 0
      ..clearFailure();
    downloadDao.updateProgress(
      bookUrl,
      status: DownloadTask.statusWaiting,
      currentChapterIndex: task.startChapterIndex,
      successCount: 0,
      errorCount: 0,
    );
    update();
    if (!isDownloading) {
      startDownloads();
    }
  }

  void removeTask(String bookUrl) {
    for (final task in tasks.where((t) => t.bookUrl == bookUrl)) {
      task.status = DownloadTask.statusPaused;
    }
    tasks.removeWhere((t) => t.bookUrl == bookUrl);
    downloadDao.deleteByUrl(bookUrl);
    update();
  }

  /// 跑完後要再補一次的書：排進來時這本書的任務正在跑，任務的章節範圍
  /// 在加入時就固定了，新章節要等這輪結束再排。值是這段期間有沒有從書源
  /// 抓到新章節，結束後照樣交給重試規則判斷。
  final Map<String, bool> _keepAfterRun = <String, bool>{};

  /// 書架上的網路書整本下載好（ADR 0008）：把目錄裡還沒有正文的章節排進
  /// 背景下載。[hasNewChapters] 表示剛從書源抓到新章節，書源此刻是好的，
  /// 失敗過的任務可以馬上再試。
  Future<void> keepShelfBookDownloaded(
    String bookUrl, {
    bool hasNewChapters = false,
  }) async {
    try {
      await _initialization;
      final book = await bookDao.getByUrl(bookUrl);
      if (book == null || book.isLocal || !book.isInBookshelf) return;
      final source = await sourceDao.getByUrl(book.origin);
      if (source == null || !source.isReadingEnabledByRuntime) return;
      final chapters = await chapterDao.getByBook(bookUrl);
      // 還沒有目錄（例如匯入時沒附）也要排：任務開跑時先抓目錄，抓不到就
      // 記為失敗，照重試規則再試。
      final List<BookChapter> missing;
      if (chapters.isEmpty) {
        missing = const <BookChapter>[];
      } else {
        final stored = await chapterContentDao.getStoredChapterUrls(
          origin: book.origin,
          bookUrl: bookUrl,
        );
        missing = chaptersMissingContent(chapters, stored);
        if (missing.isEmpty) return;
      }

      final task = tasks.cast<DownloadTask?>().firstWhere(
        (candidate) => candidate?.bookUrl == bookUrl,
        orElse: () => null,
      );
      final decision = decideShelfDownload(
        task: task,
        running: activeTaskUrls.contains(bookUrl),
        hasNewChapters: hasNewChapters,
        now: DateTime.now().millisecondsSinceEpoch,
      );
      switch (decision) {
        case ShelfDownloadDecision.queue:
          await queueShelfDownload(book, missing);
        case ShelfDownloadDecision.afterCurrentRun:
          _keepAfterRun[bookUrl] =
              (_keepAfterRun[bookUrl] ?? false) || hasNewChapters;
        case ShelfDownloadDecision.leave:
          break;
      }
    } catch (error, stackTrace) {
      AppLog.e(
        '書架自動下載排程失敗 $bookUrl: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void onTaskFinished(DownloadTask task) {
    final hasNewChapters = _keepAfterRun.remove(task.bookUrl);
    if (hasNewChapters == null) return;
    // 完成了就補這輪之後的新章節；失敗了照重試規則，期間抓到新章節就馬上
    // 再試。被暫停或中途停下的不接著排。
    if (task.isCompleted || task.isFailed) {
      unawaited(
        keepShelfBookDownloaded(task.bookUrl, hasNewChapters: hasNewChapters),
      );
    }
  }

  Future<void> retireBook(String bookUrl) async {
    await _initialization;
    markTaskRetiring(bookUrl);
    try {
      for (final task in tasks.where((task) => task.bookUrl == bookUrl)) {
        task.status = DownloadTask.statusPaused;
      }
      update();
      await waitForTaskIdle(bookUrl);
      await downloadDao.deleteByUrl(bookUrl);
      tasks.removeWhere((task) => task.bookUrl == bookUrl);
    } finally {
      clearTaskRetiring(bookUrl);
      update();
    }
  }

  void moveTask(String bookUrl, int delta) {
    final current = tasks.indexWhere((t) => t.bookUrl == bookUrl);
    if (current < 0) return;
    final next = current + delta;
    if (next < 0 || next >= tasks.length) return;
    final task = tasks.removeAt(current);
    tasks.insert(next, task);
    // 順序寫回資料庫，重開 App 後照使用者排的先後下載。
    for (var i = 0; i < tasks.length; i++) {
      tasks[i].sortOrder = i;
    }
    unawaited(downloadDao.saveOrder([for (final t in tasks) t.bookUrl]));
    update();
  }
}

class _DownloadSourceSwitchLease implements SourceSwitchOperationLease {
  _DownloadSourceSwitchLease({
    required this.owner,
    required this.bookUrl,
    required this.task,
    required this.previousStatus,
  });

  final DownloadService owner;
  final String bookUrl;
  final DownloadTask? task;
  final int? previousStatus;
  bool _finalized = false;

  @override
  Future<void> retireInTransaction(AppDatabase db) {
    return DownloadDao(db).deleteByUrl(bookUrl);
  }

  @override
  void committed() {
    if (_finalized) return;
    _finalized = true;
    owner._commitSourceSwitchRetirement(bookUrl);
  }

  @override
  void rolledBack() {
    if (_finalized) return;
    _finalized = true;
    owner._rollbackSourceSwitchRetirement(bookUrl, task, previousStatus);
  }
}

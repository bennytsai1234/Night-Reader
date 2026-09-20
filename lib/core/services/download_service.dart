import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/source_switch_handoff.dart';
import 'download/download_base.dart';
import 'download/download_scheduler.dart';
import 'download/download_executor.dart';

export 'download/download_base.dart';
export 'download/download_scheduler.dart';
export 'download/download_executor.dart';

/// DownloadService - 書籍章節背景下載服務
class DownloadService extends DownloadBase
    with DownloadScheduler, DownloadExecutor {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;

  late final Future<void> _initialization;

  double get progress => totalProgress;

  DownloadService._internal() {
    listenEvents();
    _initialization = _loadTasks();
  }

  Future<SourceSwitchOperationLease> quiesceForSourceSwitch(Book oldBook) async {
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
      startDownloads();
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

    if (isPaused) {
      isPaused = false;
      pauseCompleter?.complete();
      pauseCompleter = null;
    }
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
    if (task == null) return;

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

  Future<int> queueMissingForLibraryReading(
    Book book,
    List<BookChapter> chapters,
  ) async {
    if (book.isLocal || !book.isInBookshelf || chapters.isEmpty) return 0;
    final stored = await chapterContentDao.getStoredChapterIndices(
      origin: book.origin,
      bookUrl: book.bookUrl,
    );
    final missing = chapters
        .where((chapter) => !stored.contains(chapter.index))
        .toList();
    if (missing.isEmpty) return 0;
    await addDownloadTask(book, missing);
    return missing.length;
  }

  Future<void> retireBook(String bookUrl) async {
    await _initialization;
    markTaskRetiring(bookUrl);
    for (final task in tasks.where((task) => task.bookUrl == bookUrl)) {
      task.status = DownloadTask.statusPaused;
    }
    update();
    await waitForTaskIdle(bookUrl);
    tasks.removeWhere((task) => task.bookUrl == bookUrl);
    await downloadDao.deleteByUrl(bookUrl);
    clearTaskRetiring(bookUrl);
    update();
  }

  void moveTask(String bookUrl, int delta) {
    final current = tasks.indexWhere((t) => t.bookUrl == bookUrl);
    if (current < 0) return;
    final next = current + delta;
    if (next < 0 || next >= tasks.length) return;
    final task = tasks.removeAt(current);
    tasks.insert(next, task);
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

import 'dart:async';

import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
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

/// 書架上一本書要整本下載時排隊顯示的書名與總章數。
typedef ShelfDownloadNeed = ({String bookName, int totalCount});

/// 書架上這本書還有章節沒下載時回傳 [ShelfDownloadNeed]；不在書架、本地
/// 書、書源不能讀，或都下載好了時回傳 null。讀整本目錄比對已存的正文，所以
/// 在書源 isolate 做，只傳回摘要（ADR 0028）；開 App 時書架上每本書都會
/// 比對一次。
Future<ShelfDownloadNeed?> _shelfDownloadNeedInSourceIsolate(String bookUrl) =>
    SourceIsolate.run((_) => _shelfDownloadNeed(bookUrl));

Future<ShelfDownloadNeed?> _shelfDownloadNeed(String bookUrl) async {
  final book = await getIt<BookDao>().getByUrl(bookUrl);
  if (book == null || book.isLocal || !book.isInBookshelf) return null;
  final source = await getIt<BookSourceDao>().getByUrl(book.origin);
  if (source == null || !source.isReadingEnabledByRuntime) return null;
  final chapters = await getIt<ChapterDao>().getByBook(bookUrl);
  // 還沒有目錄（例如匯入時沒附）也要排：任務開跑時先抓目錄，抓不到就
  // 記為失敗，照重試規則再試。有目錄而且都下載好了就不排。
  if (chapters.isNotEmpty) {
    final stored = await getIt<ReaderChapterContentDao>().getStoredChapterUrls(
      origin: book.origin,
      bookUrl: bookUrl,
    );
    if (chaptersMissingContent(chapters, stored).isEmpty) return null;
  }
  return (
    bookName: book.name,
    totalCount: chapters.where(chapterIsDownloadable).length,
  );
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
    final (:bookUrl, :task, :previousStatus) = await _hold(oldBook.bookUrl);
    return _DownloadSourceSwitchLease(
      owner: this,
      bookUrl: bookUrl,
      task: task,
      previousStatus: previousStatus,
    );
  }

  /// 書的來源身分在別處改變時（書源改了網址），先停下 [bookUrls] 進行中的
  /// 下載並等它們停住，改的途中也不排新的；改完呼叫回傳的函式，照原本的
  /// 狀態接著下載。接著下載的那一輪重新從資料庫讀書，用的是新的書源網址。
  Future<void Function()> holdBooks(Iterable<String> bookUrls) async {
    final holds = [for (final bookUrl in bookUrls) await _hold(bookUrl)];
    return () {
      for (final (:bookUrl, :task, :previousStatus) in holds) {
        _releaseHold(bookUrl, task, previousStatus);
      }
    };
  }

  /// 停下 [bookUrl] 的下載並等它停住；之後由 [_releaseHold] 恢復，或換源
  /// 成功時由 [_commitSourceSwitchRetirement] 移除。
  Future<({String bookUrl, DownloadTask? task, int? previousStatus})> _hold(
    String bookUrl,
  ) async {
    await _initialization;
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
    return (bookUrl: bookUrl, task: task, previousStatus: previousStatus);
  }

  void _commitSourceSwitchRetirement(String bookUrl) {
    tasks.removeWhere((task) => task.bookUrl == bookUrl);
    clearTaskRetiring(bookUrl);
    update();
  }

  void _releaseHold(String bookUrl, DownloadTask? task, int? previousStatus) {
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

  /// 從資料庫恢復任務：上次關 App 時還在下載的改回排隊，先不開跑
  /// （[resumeRestoredDownloads]）。
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
  }

  /// 接著下載上次沒下載完的書。服務在開 App 建書架時就建立，建立時就開跑
  /// 的話，抓目錄、收正文、寫入與每秒一次的排程都落在開 App 的進場動畫裡；
  /// 改由主頁面等進場播完才呼叫（ADR 0018）。
  Future<void> resumeRestoredDownloads() async {
    await _initialization;
    if (tasks.any((t) => t.isWaiting) && !isDownloading) {
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
      ..currentChapterIndex = 0
      ..successCount = 0
      ..errorCount = 0
      ..clearFailure();
    downloadDao.updateProgress(
      bookUrl,
      status: DownloadTask.statusWaiting,
      currentChapterIndex: 0,
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

  /// 跑完後要再補一次的書：排進來時這本書的任務正在跑，這一輪要下載的
  /// 章節在開跑時就定了，新章節要等這輪結束再排。值是這段期間有沒有從書源
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
      final need = await _shelfDownloadNeedInSourceIsolate(bookUrl);
      if (need == null) return;

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
          await queueShelfDownload(
            bookUrl: bookUrl,
            bookName: need.bookName,
            totalCount: need.totalCount,
          );
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
    owner._releaseHold(bookUrl, task, previousStatus);
  }
}

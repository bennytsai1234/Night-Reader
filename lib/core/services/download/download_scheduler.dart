import 'dart:async';

import 'download_base.dart';

import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';

/// DownloadService 的調度與任務管理邏輯擴展
mixin DownloadScheduler on DownloadBase {
  final Set<String> _addingTaskUrls = <String>{};

  Future<bool> waitUntilTaskRunnable(String bookUrl) async {
    final retireSignal = retirementSignal(bookUrl);
    if (isTaskRetiring(bookUrl)) return false;

    if (isPaused) {
      pauseCompleter ??= Completer<void>();
      await Future.any<void>(<Future<void>>[
        pauseCompleter!.future,
        retireSignal,
      ]);
    }
    return !isTaskRetiring(bookUrl);
  }

  void togglePause() {
    isPaused = !isPaused;
    if (!isPaused) {
      pauseCompleter?.complete();
      pauseCompleter = null;
    } else {
      pauseCompleter = Completer<void>();
    }
    update();
  }

  /// 使用者明確要下載的章節。[chapters] 是範圍裡的章節（已下載的也算），
  /// 決定排隊時顯示的總數，開跑時照當下的目錄重算；[from]／[to] 是範圍的
  /// 起訖章節，不給表示從第一章／到目錄最後一章，整本與「缺少的」兩端都
  /// 不給。
  Future<void> addDownloadTask(
    Book book,
    List<BookChapter> chapters, {
    BookChapter? from,
    BookChapter? to,
  }) async {
    await _admitDownloadTask(
      book,
      chapters,
      from: from,
      to: to,
      intent: _DownloadTaskAdmissionIntent.userRequested,
    );
  }

  /// 書架自動下載（ADR 0008）加入的整本任務：不會把使用者暫停的任務排
  /// 回去；失敗的任務要不要再試由呼叫端依重試規則決定。[chapters] 是目前
  /// 的目錄，空的表示這本書還沒有目錄（例如匯入時沒附），任務開跑時先抓
  /// 目錄。
  ///
  /// Returns true only when a new waiting task was actually admitted.
  Future<bool> queueShelfDownload(Book book, List<BookChapter> chapters) {
    return _admitDownloadTask(
      book,
      chapters,
      intent: _DownloadTaskAdmissionIntent.shelfAuto,
    );
  }

  Future<bool> _admitDownloadTask(
    Book book,
    List<BookChapter> chapters, {
    BookChapter? from,
    BookChapter? to,
    required _DownloadTaskAdmissionIntent intent,
  }) async {
    if (chapters.isEmpty &&
            intent == _DownloadTaskAdmissionIntent.userRequested ||
        isTaskRetiring(book.bookUrl) ||
        !_addingTaskUrls.add(book.bookUrl)) {
      return false;
    }
    beginTaskActivity(book.bookUrl);
    try {
      if (activeTaskUrls.contains(book.bookUrl)) return false;

      var existingIndex = tasks.indexWhere((t) => t.bookUrl == book.bookUrl);
      if (existingIndex != -1) {
        final existing = tasks[existingIndex];
        if (existing.isWaiting || existing.isDownloading) {
          return false;
        }
        if (intent == _DownloadTaskAdmissionIntent.shelfAuto &&
            existing.isPaused) {
          return false;
        }
      }

      // 重新加入的任務保留原本的位置；新任務排在佇列最後。
      final sortOrder = existingIndex != -1
          ? tasks[existingIndex].sortOrder
          : tasks.fold<int>(-1, (m, t) => t.sortOrder > m ? t.sortOrder : m) +
                1;
      final task = DownloadTask(
        bookUrl: book.bookUrl,
        bookName: book.name,
        startChapterUrl: from?.url,
        endChapterUrl: to?.url,
        totalCount: chapters.where(chapterIsDownloadable).length,
        status: DownloadTask.statusWaiting,
        lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
        sortOrder: sortOrder,
      );
      await downloadDao.upsert(task);

      existingIndex = tasks.indexWhere((t) => t.bookUrl == book.bookUrl);
      if (existingIndex != -1) {
        tasks[existingIndex] = task;
      } else {
        tasks.add(task);
      }
      update();
      if (!isTaskRetiring(book.bookUrl) && !isDownloading) {
        unawaited(startDownloads());
      }
      return true;
    } finally {
      _addingTaskUrls.remove(book.bookUrl);
      completeTaskActivity(book.bookUrl);
    }
  }

  Future<void> startDownloads() async {
    if (isScheduling || isDownloading) {
      return;
    }
    isScheduling = true;
    try {
      isDownloading = true;
      update();
      while (tasks.any((t) => t.isWaiting || t.isDownloading)) {
        final activeTasks = tasks
            .where((t) => t.isDownloading || activeTaskUrls.contains(t.bookUrl))
            .toList();
        if (activeTasks.length < maxConcurrent) {
          final nextTask = tasks.cast<DownloadTask?>().firstWhere((t) {
            if (t == null || !t.isWaiting) return false;
            return !activeTaskUrls.contains(t.bookUrl) &&
                !isTaskRetiring(t.bookUrl);
          }, orElse: () => null);
          if (nextTask != null) {
            unawaited(processTask(nextTask));
          } else if (activeTasks.isEmpty) {
            break;
          }
        }
        await Future.delayed(const Duration(seconds: 1));
      }
      isDownloading = false;
      update();
    } finally {
      isScheduling = false;
    }
  }
}

enum _DownloadTaskAdmissionIntent { userRequested, shelfAuto }

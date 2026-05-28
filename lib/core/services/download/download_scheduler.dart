import 'dart:async';
import 'download_base.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';

/// DownloadService 的調度與任務管理邏輯擴展
mixin DownloadScheduler on DownloadBase {
  StreamSubscription? _refreshStartSub;
  StreamSubscription? _refreshEndSub;

  void listenEvents() {
    _refreshStartSub?.cancel();
    _refreshEndSub?.cancel();
    _refreshStartSub = AppEventBus()
        .onName(AppEventBus.bookshelfRefreshStart)
        .listen((_) {
          isBookshelfRefreshing = true;
          update();
        });
    _refreshEndSub = AppEventBus()
        .onName(AppEventBus.bookshelfRefreshEnd)
        .listen((_) {
          isBookshelfRefreshing = false;
          update();
        });
  }

  Future<void> checkPriority() async {
    while (isBookshelfRefreshing) {
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> checkPause() async {
    await checkPriority();
    if (isPaused) {
      pauseCompleter ??= Completer<void>();
      await pauseCompleter!.future;
    }
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

  Future<void> addDownloadTask(Book book, List<BookChapter> chapters) async {
    if (chapters.isEmpty) {
      return;
    }
    final task = DownloadTask(
      bookUrl: book.bookUrl,
      bookName: book.name,
      startChapterIndex: chapters.first.index,
      endChapterIndex: chapters.last.index,
      totalCount: chapters.length,
      status: DownloadTask.statusWaiting,
      lastUpdateTime: DateTime.now().millisecondsSinceEpoch,
    );
    await downloadDao.upsert(task);
    final existingIndex = tasks.indexWhere((t) => t.bookUrl == book.bookUrl);
    if (existingIndex != -1) {
      tasks[existingIndex] = task;
    } else {
      tasks.add(task);
    }
    update();
    if (!isDownloading) {
      startDownloads();
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
        final activeTasks =
            tasks
                .where(
                  (t) => t.isDownloading || activeTaskUrls.contains(t.bookUrl),
                )
                .toList();
        if (activeTasks.length < maxConcurrent) {
          final nextTask = tasks.cast<DownloadTask?>().firstWhere((t) {
            if (t == null || !t.isWaiting) return false;
            return !activeTaskUrls.contains(t.bookUrl);
          }, orElse: () => null);
          if (nextTask != null) {
            processTask(nextTask);
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

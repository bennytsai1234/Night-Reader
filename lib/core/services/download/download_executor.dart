import 'dart:async';
import 'download_base.dart';
import 'download_scheduler.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/reader_chapter_content_store.dart';
import 'package:night_reader/core/services/reader_chapter_content_storage.dart';

bool downloadTaskCountsPreStoredChapters({
  required DownloadTask task,
  required int chapterCountInRange,
}) {
  return task.totalCount >= chapterCountInRange;
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
      final book = await bookDao.getByUrl(task.bookUrl);
      if (book == null) {
        throw Exception('書籍不存在');
      }
      final source =
          book.origin == 'local' ? null : await sourceDao.getByUrl(book.origin);
      if (book.origin != 'local' && source == null) {
        throw Exception('書源不存在');
      }

      var chapters = await chapterDao.getByBook(task.bookUrl);
      if (chapters.isEmpty) {
        if (source == null) {
          throw Exception('章節目錄不存在');
        }
        chapters = await sourceService.getChapterList(source, book);
        await chapterDao.insertChapters(chapters);
        // 更新任務實例
        final newTask = task.copyWith(
          totalCount: chapters.length,
          endChapterIndex: chapters.isNotEmpty ? chapters.last.index : 0,
        );
        final idx = tasks.indexOf(task);
        if (idx != -1) {
          tasks[idx] = newTask;
        }
        task = newTask;
      }

      final toDownload =
          chapters
              .where(
                (c) =>
                    c.index >= task.startChapterIndex &&
                    c.index <= task.endChapterIndex,
              )
              .toList();
      final countsPreStoredChapters = downloadTaskCountsPreStoredChapters(
        task: task,
        chapterCountInRange: toDownload.length,
      );
      final contentStore = ReaderChapterContentStore(
        chapterDao: chapterDao,
        contentDao: chapterContentDao,
      );
      final contentStorage = ReaderChapterContentStorage.withMaterializer(
        book: book,
        contentStore: contentStore,
        sourceDao: sourceDao,
        service: sourceService,
        getSource: () => source,
      );
      var poolCount = 0;
      for (var chapter in toDownload) {
        if (!isDownloading || task.status == DownloadTask.statusPaused) {
          stoppedEarly = true;
          break;
        }
        await checkPause();

        if (await contentStore.hasReadyContent(book: book, chapter: chapter)) {
          if (countsPreStoredChapters) {
            task.successCount++;
          }
          task.currentChapterIndex = chapter.index;
          await downloadDao.updateProgress(
            task.bookUrl,
            currentChapterIndex: chapter.index,
            successCount: task.successCount,
            errorCount: task.errorCount,
          );
          update();
          continue;
        }

        while (poolCount >= maxChapterConcurrent) {
          await Future.delayed(const Duration(milliseconds: 500));
        }

        poolCount++;
        _downloadChapter(
              contentStorage: contentStorage,
              source: source,
              chapter: chapter,
            )
            .then((result) {
              if (result.success) {
                task.successCount++;
              } else {
                task.errorCount++;
                final message = result.failureMessage ?? '下載失敗';
                task.setFailure(
                  reason: classifyDownloadFailureReason(message),
                  message: message,
                  chapterIndex: chapter.index,
                );
              }
              poolCount--;
              task.currentChapterIndex = chapter.index;
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
              final message = error.toString();
              task.setFailure(
                reason: classifyDownloadFailureReason(message),
                message: message,
                chapterIndex: chapter.index,
              );
              poolCount--;
              task.currentChapterIndex = chapter.index;
              downloadDao.updateProgress(
                task.bookUrl,
                currentChapterIndex: chapter.index,
                successCount: task.successCount,
                errorCount: task.errorCount,
              );
              update();
            });
      }

      while (poolCount > 0) {
        await Future.delayed(const Duration(seconds: 1));
      }

      if (!stoppedEarly && task.status != DownloadTask.statusPaused) {
        task.status =
            task.errorCount > 0
                ? DownloadTask.statusFailed
                : DownloadTask.statusCompleted;
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
        final message = e.toString();
        task.setFailure(
          reason: classifyDownloadFailureReason(message),
          message: message,
        );
        task.status = DownloadTask.statusFailed;
        await downloadDao.updateProgress(
          task.bookUrl,
          status: DownloadTask.statusFailed,
        );
      }
    } finally {
      activeTaskUrls.remove(task.bookUrl);
    }
    update();
  }

  static const int _maxRetries = 3;

  Future<DownloadChapterResult> _downloadChapter({
    required ReaderChapterContentStorage contentStorage,
    required BookSource? source,
    required BookChapter chapter,
  }) async {
    final result = await contentStorage.read(
      chapterIndex: chapter.index,
      chapter: chapter,
      sourceOverride: source,
      forceRefresh: true,
      maxAttempts: _maxRetries,
    );
    if (result.isReady) {
      return DownloadChapterResult.ready();
    }
    return DownloadChapterResult.failed(
      result.failureMessage ?? result.content,
    );
  }
}

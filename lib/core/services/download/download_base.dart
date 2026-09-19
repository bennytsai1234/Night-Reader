import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:night_reader/core/database/dao/download_dao.dart';
import '../book_source_service.dart';
import 'package:night_reader/core/di/injection.dart';

/// DownloadService 的基礎狀態與 DAO 定義
abstract class DownloadBase extends ChangeNotifier {
  final BookDao bookDao = getIt<BookDao>();
  final BookSourceDao sourceDao = getIt<BookSourceDao>();
  final ChapterDao chapterDao = getIt<ChapterDao>();
  final ReaderChapterContentDao chapterContentDao =
      getIt<ReaderChapterContentDao>();
  final DownloadDao downloadDao = getIt<DownloadDao>();
  final BookSourceService sourceService = BookSourceService();

  final List<DownloadTask> tasks = [];
  bool isDownloading = false;
  bool isPaused = false;
  Completer<void>? pauseCompleter;
  bool isScheduling = false;
  bool isBookshelfRefreshing = false;
  final Set<String> activeTaskUrls = <String>{};
  final Set<String> retiringTaskUrls = <String>{};
  final Map<String, int> _taskActivityCounts = <String, int>{};
  final Map<String, Completer<void>> _taskIdleSignals =
      <String, Completer<void>>{};
  final Map<String, Completer<void>> _retirementSignals =
      <String, Completer<void>>{};


  final int maxConcurrent = 3;
  final int maxChapterConcurrent = 5;

  double get totalProgress {
    if (tasks.isEmpty) return 0.0;
    var total = 0;
    var success = 0;
    for (var task in tasks) {
      total += task.totalCount;
      success += task.successCount;
    }
    return total == 0 ? 0.0 : success / total;
  }

  void update() => notifyListeners();

  bool isTaskRetiring(String bookUrl) => retiringTaskUrls.contains(bookUrl);

  Future<void> retirementSignal(String bookUrl) =>
      _retirementSignals
          .putIfAbsent(bookUrl, () => Completer<void>())
          .future;

  void markTaskRetiring(String bookUrl) {
    retiringTaskUrls.add(bookUrl);
    final signal = _retirementSignals.putIfAbsent(
      bookUrl,
      () => Completer<void>(),
    );
    if (!signal.isCompleted) {
      signal.complete();
    }
  }

  void clearTaskRetiring(String bookUrl) {
    retiringTaskUrls.remove(bookUrl);
    _retirementSignals.remove(bookUrl);
  }

  void beginTaskActivity(String bookUrl) {
    final count = _taskActivityCounts[bookUrl] ?? 0;
    if (count == 0) {
      _taskIdleSignals[bookUrl] = Completer<void>();
    }
    _taskActivityCounts[bookUrl] = count + 1;
  }

  void completeTaskActivity(String bookUrl) {
    final count = _taskActivityCounts[bookUrl] ?? 0;
    if (count <= 1) {
      _taskActivityCounts.remove(bookUrl);
      final signal = _taskIdleSignals.remove(bookUrl);
      if (signal != null && !signal.isCompleted) {
        signal.complete();
      }
      return;
    }
    _taskActivityCounts[bookUrl] = count - 1;
  }

  Future<void> waitForTaskIdle(String bookUrl) async {
    final signal = _taskIdleSignals[bookUrl];
    if (signal != null) {
      await signal.future;
    }
  }

  Future<void> processTask(DownloadTask task);
}

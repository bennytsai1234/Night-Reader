import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/download_task.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
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

  /// 每個任務的書是哪一類，照書網址記；下載管理照它寫章、話、集。任務存在
  /// 資料庫裡，類別不另存一欄：載入與加入任務時查一次書（[rememberKind]）。
  final Map<String, BookSourceKind> _taskKinds = <String, BookSourceKind>{};

  /// [bookUrl] 這個任務的書的類別；沒查到書的算小說。
  BookSourceKind kindOf(String bookUrl) =>
      _taskKinds[bookUrl] ?? BookSourceKind.novel;

  Future<void> rememberKind(String bookUrl) async {
    final book = await bookDao.getByUrl(bookUrl);
    _taskKinds[bookUrl] = book?.bookKind ?? BookSourceKind.novel;
  }

  bool isDownloading = false;
  bool isPaused = false;
  Completer<void>? pauseCompleter;
  bool isScheduling = false;
  final Set<String> activeTaskUrls = <String>{};
  final Set<String> retiringTaskUrls = <String>{};
  final Map<String, int> _taskActivityCounts = <String, int>{};
  final Map<String, Completer<void>> _taskIdleSignals =
      <String, Completer<void>>{};
  final Map<String, Completer<void>> _retirementSignals =
      <String, Completer<void>>{};

  /// 每本書正在跑的那一輪下載的取消訊號：退役時取消，已經送出的請求與
  /// 還沒開始的重試跟著停下，移出書架與換源不必等它們自己結束。
  final Map<String, CancelToken> _runCancelTokens = <String, CancelToken>{};

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
      _retirementSignals.putIfAbsent(bookUrl, () => Completer<void>()).future;

  void markTaskRetiring(String bookUrl) {
    retiringTaskUrls.add(bookUrl);
    final signal = _retirementSignals.putIfAbsent(
      bookUrl,
      () => Completer<void>(),
    );
    if (!signal.isCompleted) {
      signal.complete();
    }
    _runCancelTokens[bookUrl]?.cancel('這本書的下載已停止');
  }

  /// 開始一輪下載，拿到這一輪的取消訊號；跑完交給 [endRun]。
  CancelToken beginRun(String bookUrl) =>
      _runCancelTokens[bookUrl] = CancelToken();

  void endRun(String bookUrl, CancelToken cancelToken) {
    if (identical(_runCancelTokens[bookUrl], cancelToken)) {
      _runCancelTokens.remove(bookUrl);
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

  /// 一個任務跑完（完成、失敗或中途停下）後呼叫。
  void onTaskFinished(DownloadTask task) {}
}

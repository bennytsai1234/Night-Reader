import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:reader/core/models/download_task.dart';
import 'package:reader/core/database/dao/book_dao.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/database/dao/chapter_dao.dart';
import 'package:reader/core/database/dao/reader_chapter_content_dao.dart';
import 'package:reader/core/database/dao/download_dao.dart';
import '../book_source_service.dart';
import 'package:reader/core/di/injection.dart';

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

  Future<void> processTask(DownloadTask task);
}

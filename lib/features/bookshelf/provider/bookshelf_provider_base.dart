import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/book_update_service.dart';
import 'package:night_reader/core/services/download_service.dart';
import 'package:night_reader/core/di/injection.dart';

enum BookshelfSortMode {
  custom,
  recentRead,
  addedTime,
  updateTime,
  bookName,
  author,
}

extension BookshelfSortModeLabel on BookshelfSortMode {
  String get label {
    return switch (this) {
      BookshelfSortMode.custom => '自訂排序',
      BookshelfSortMode.recentRead => '最近閱讀',
      BookshelfSortMode.addedTime => '加入時間',
      BookshelfSortMode.updateTime => '更新時間',
      BookshelfSortMode.bookName => '書名',
      BookshelfSortMode.author => '作者',
    };
  }
}

/// 書架骨架照著畫的一本書：原始的書名與作者，畫的時候再轉成目前的中文
/// 顯示方式。
typedef ShelfSkeletonTitle = ({String name, String author});

Future<void> _keepWithDownloadService(
  String bookUrl, {
  bool hasNewChapters = false,
}) => DownloadService().keepShelfBookDownloaded(
  bookUrl,
  hasNewChapters: hasNewChapters,
);

/// BookshelfProvider 的基礎狀態與 DAO 定義
abstract class BookshelfProviderBase extends ChangeNotifier {
  Future<void> loadBooks();

  final BookDao bookDao = getIt<BookDao>();
  final BookSourceDao sourceDao = getIt<BookSourceDao>();
  final BookSourceService service = BookSourceService();
  final ChapterDao chapterDao = getIt<ChapterDao>();

  List<Book> books = [];
  bool isLoading = false;
  String? loadErrorMessage;

  /// 上次書架讀完時的本數，初次載入的骨架畫一樣多本；從沒讀過時為 null。
  int? lastBookCount;

  /// 上次書架前面幾本的書名與作者（依當時的排序），初次載入的骨架照它們
  /// 的長度畫。
  List<ShelfSkeletonTitle> lastShelfTitles = const [];

  bool isGridView = true;
  bool showLastUpdate = false;
  BookshelfSortMode sortMode = BookshelfSortMode.recentRead;
  int updatingCount = 0;

  /// 書架自動下載，預設交給 [DownloadService]。
  final ShelfBookDownloader keepBookDownloaded;

  /// 抓書源上的詳情與目錄寫回書，與書籍詳情的「檢查更新」共用進行中的檢查。
  late final BookUpdateService updates = BookUpdateService(
    keepDownloaded: keepBookDownloaded,
    bookDao: bookDao,
    chapterDao: chapterDao,
    sourceDao: sourceDao,
    sourceService: service,
  );

  /// 排定書卡角標消失的計時，預設 [Timer.new]。
  final Timer Function(Duration duration, void Function() callback) startTimer;

  BookshelfProviderBase({
    ShelfBookDownloader? keepBookDownloaded,
    Timer Function(Duration duration, void Function() callback)? startTimer,
  }) : keepBookDownloaded = keepBookDownloaded ?? _keepWithDownloadService,
       startTimer = startTimer ?? Timer.new;

  bool _disposed = false;

  /// 背景檢查、載入等非同步工作可能在 provider 釋放後才結束，結束時的通知
  /// 不再送出。
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

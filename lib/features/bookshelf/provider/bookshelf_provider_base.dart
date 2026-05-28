import 'package:flutter/foundation.dart';
import 'package:reader/core/database/dao/book_dao.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/database/dao/chapter_dao.dart';
import 'package:reader/core/models/book.dart';
import 'package:reader/core/services/book_source_service.dart';
import 'package:reader/core/di/injection.dart';

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

/// BookshelfProvider 的基礎狀態與 DAO 定義
abstract class BookshelfProviderBase extends ChangeNotifier {
  Future<void> loadBooks();

  final BookDao bookDao = getIt<BookDao>();
  final BookSourceDao sourceDao = getIt<BookSourceDao>();
  final BookSourceService service = BookSourceService();
  final ChapterDao chapterDao = getIt<ChapterDao>();

  List<Book> books = [];
  bool isLoading = false;

  bool isGridView = true;
  bool showLastUpdate = false;
  BookshelfSortMode sortMode = BookshelfSortMode.recentRead;
  int updatingCount = 0;

  BookshelfProviderBase();
}

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/bookshelf_state_tracker.dart';
import 'package:night_reader/core/engine/web_book/web_book_service.dart';

typedef ExploreBookLoader =
    Future<List<SearchBook>> Function(
      BookSource source,
      String exploreUrl, {
      int? page,
      CancelToken? cancelToken,
    });

/// ExploreShowProvider - 探索結果列表的狀態管理
/// (對標 Android ExploreShowViewModel)
///
/// 管理單個分類的書籍列表、分頁載入、書架狀態。
class ExploreShowProvider extends ChangeNotifier {
  final String sourceUrl;
  final String exploreUrl;
  final String exploreName;

  final BookSourceDao _sourceDao = getIt<BookSourceDao>();
  final BookshelfStateTracker _bookshelfTracker;
  final ExploreBookLoader _exploreLoader;
  CancelToken? _cancelToken;

  BookSource? _bookSource;
  List<SearchBook> _books = [];
  int _page = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _errorMessage;
  int _requestSerial = 0;
  bool _isDisposed = false;

  // --- Getters ---
  List<SearchBook> get books => _books;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => _books.isEmpty && !_isLoading;

  ExploreShowProvider({
    required this.sourceUrl,
    required this.exploreUrl,
    required this.exploreName,
    BookshelfStateTracker? bookshelfTracker,
    ExploreBookLoader? exploreLoader,
  }) : _bookshelfTracker = bookshelfTracker ?? BookshelfStateTracker(),
       _exploreLoader = exploreLoader ?? WebBook.exploreBookAwait {
    _init();
  }

  Future<void> _init() async {
    _bookSource = await _sourceDao.getByUrl(sourceUrl);
    if (_bookSource == null) {
      _errorMessage = '找不到書源';
      notifyListeners();
      return;
    }
    await _bookshelfTracker.initialize(onChanged: notifyListeners);
    await _loadData();
  }

  /// 判斷書籍是否在書架中 (對標 Android isInBookShelf)
  bool isInBookshelf(SearchBook book) =>
      _bookshelfTracker.containsSearchBook(book);

  /// 載入數據
  Future<void> _loadData() async {
    if (_bookSource == null) return;
    final requestId = ++_requestSerial;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    _cancelToken = CancelToken();

    try {
      final results = await _exploreLoader(
        _bookSource!,
        exploreUrl,
        page: _page,
        cancelToken: _cancelToken,
      );

      if (_isDisposed ||
          requestId != _requestSerial ||
          (_cancelToken?.isCancelled ?? false)) {
        return;
      }

      if (results.isEmpty) {
        _hasMore = false;
      } else {
        _books.addAll(results);
        _page++;
      }
    } on DioException catch (e) {
      if (_isDisposed || requestId != _requestSerial) return;
      if (e.type == DioExceptionType.cancel) return;
      AppLog.e('探索載入失敗', error: e);
      _errorMessage = e.message ?? '載入失敗';
      _hasMore = false;
    } catch (e) {
      if (_isDisposed || requestId != _requestSerial) return;
      AppLog.e('探索載入失敗', error: e);
      _errorMessage = e.toString();
      _hasMore = false;
    } finally {
      final shouldFinalize = !_isDisposed && requestId == _requestSerial;
      if (shouldFinalize) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// 載入更多 (對標 Android scrollToBottom)
  Future<void> loadMore() async {
    if (!_hasMore || _isLoading) return;
    await _loadData();
  }

  /// 重新載入
  Future<void> refresh() async {
    _cancelToken?.cancel('refresh');
    _requestSerial++;
    _page = 1;
    _books = [];
    _hasMore = true;
    _errorMessage = null;
    await _loadData();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _requestSerial++;
    _cancelToken?.cancel('ExploreShowProvider disposed');
    _bookshelfTracker.dispose();
    super.dispose();
  }
}

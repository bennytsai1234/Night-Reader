import 'dart:async';

import 'package:night_reader/core/exception/user_error.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/bookshelf_state_tracker.dart';

import 'explore_book_details.dart';

typedef ExploreBookLoader = Future<List<SearchBook>> Function(
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
  bool _isLoading = true;
  bool _hasMore = true;
  String? _errorMessage;
  int _requestSerial = 0;
  bool _isDisposed = false;

  /// 清單上畫出來的書缺的封面與字數，在背景向書源補。
  final ExploreBookDetails details;

  // --- Getters ---
  /// 這個分類的書源；找到之前是 null。
  BookSource? get source => _bookSource;
  List<SearchBook> get books => _books;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => _books.isEmpty && !_isLoading && _errorMessage == null;

  ExploreShowProvider({
    required this.sourceUrl,
    required this.exploreUrl,
    required this.exploreName,
    required Future<void> entrance,
    BookshelfStateTracker? bookshelfTracker,
    ExploreBookLoader? exploreLoader,
    ExploreExtrasLoader? extrasLoader,
  }) : _bookshelfTracker = bookshelfTracker ?? BookshelfStateTracker(),
       _exploreLoader = exploreLoader ?? BookSourceService().exploreBooks,
       details = ExploreBookDetails(loader: extrasLoader) {
    // 進場動畫播完才讀書源、向書源抓書單（ADR 0018）：原本一進頁就開始，
    // 書單在換頁途中到，建清單與骨架換場都疊在換頁上。這之前照常是骨架。
    unawaited(entrance.then((_) => _init()));
  }

  Future<void> _init() async {
    if (_isDisposed) return;
    try {
      _bookSource = await _sourceDao.getByUrl(sourceUrl);
      if (_isDisposed) return;
      if (_bookSource == null) {
        _isLoading = false;
        _errorMessage = '找不到書源';
        notifyListeners();
        return;
      }
      await _bookshelfTracker.initialize(onChanged: notifyListeners);
      if (_isDisposed) return;
      await _loadData();
    } catch (error) {
      if (_isDisposed) return;
      AppLog.e('探索初始化失敗', error: error);
      _isLoading = false;
      _errorMessage = '探索內容初始化失敗';
      notifyListeners();
    }
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

      // 分類網址沒有分頁參數的書源每頁都回傳同一批書；去重後沒有新書就
      // 當作到底，不再無限追加同一頁。
      if (_page == 1) _books = [];
      final known = {for (final book in _books) book.bookUrl};
      final fresh = results.where((book) => known.add(book.bookUrl)).toList();
      if (fresh.isEmpty) {
        _hasMore = false;
      } else {
        _books.addAll(fresh);
        _page++;
      }
    } on DioException catch (error) {
      if (_isDisposed || requestId != _requestSerial) return;
      if (error.type == DioExceptionType.cancel) return;
      AppLog.e('探索載入失敗', error: error);
      _errorMessage = userErrorReason(error);
    } catch (error) {
      if (_isDisposed || requestId != _requestSerial) return;
      AppLog.e('探索載入失敗', error: error);
      _errorMessage = userErrorReason(error);
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
    if (_isDisposed || !_hasMore || _isLoading) return;
    await _loadData();
  }

  /// 重新載入
  Future<void> refresh() async {
    _cancelToken?.cancel('refresh');
    _requestSerial++;
    // 舊列表先留著，第一頁回來時才整批替換（見 _loadData）：下拉指示器留在
    // 畫面上完成動畫，刷新失敗也不會把原本的內容清掉。
    _page = 1;
    _hasMore = true;
    _errorMessage = null;
    if (_bookSource == null) {
      _isLoading = true;
      notifyListeners();
      await _init();
      return;
    }
    await _loadData();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _requestSerial++;
    _cancelToken?.cancel('ExploreShowProvider disposed');
    _bookshelfTracker.dispose();
    details.dispose();
    super.dispose();
  }
}

import 'package:flutter/foundation.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:pool/pool.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/di/injection.dart';

class ChangeCoverProvider extends ChangeNotifier {
  final BookSourceDao _sourceDao = getIt<BookSourceDao>();
  final SearchBookDao _searchBookDao = getIt<SearchBookDao>();
  final BookSourceService _service = BookSourceService();

  List<AggregatedSearchBook> _covers = [];
  bool _isInitialized = false;
  bool _isSearching = false;
  String? _errorMessage;
  int _searchCount = 0;
  int _totalSources = 0;

  List<AggregatedSearchBook> get covers => _covers;
  bool get isInitialized => _isInitialized;
  bool get isSearching => _isSearching;
  String? get errorMessage => _errorMessage;
  double get progress => _totalSources == 0 ? 0 : _searchCount / _totalSources;

  AggregatedSearchBook _buildDefaultCoverItem(String name, String author) {
    return AggregatedSearchBook(
      book: SearchBook(
        bookUrl: 'use_default_cover',
        name: name,
        author: author,
        origin: 'system',
        originName: '恢復預設封面',
      ),
      sources: ['系統'],
    );
  }

  void stopSearch() {
    _isSearching = false;
    notifyListeners();
  }

  void clear() {
    _covers = [];
    _isInitialized = false;
    _isSearching = false;
    _errorMessage = null;
    _searchCount = 0;
    _totalSources = 0;
    notifyListeners();
  }

  /// 先載入資料庫中既有封面，再視需要發起搜尋。
  Future<void> init(String name, String author) async {
    _isInitialized = false;
    _isSearching = false;
    _errorMessage = null;
    _covers = [_buildDefaultCoverItem(name, author)];
    _searchCount = 0;
    _totalSources = 0;
    notifyListeners();

    try {
      final stored = await _searchBookDao.getEnabledHasCover(name, author);
      for (final book in stored) {
        if (!_covers.any((cover) => cover.book.coverUrl == book.coverUrl)) {
          _covers.add(
            AggregatedSearchBook(book: book, sources: const ['本地記錄']),
          );
        }
      }
      _isInitialized = true;
      notifyListeners();

      if (stored.isEmpty) {
        await search(name, author);
      }
    } catch (error) {
      AppLog.e('載入封面資料失敗: $error', error: error);
      _isInitialized = true;
      _isSearching = false;
      _errorMessage = '封面載入失敗，請重試';
      notifyListeners();
    }
  }

  Future<void> search(String name, String author) async {
    if (_isSearching) return;
    _isInitialized = true;
    _isSearching = true;
    _errorMessage = null;
    _covers = [_buildDefaultCoverItem(name, author)];
    _searchCount = 0;
    _totalSources = 0;
    notifyListeners();

    try {
      final stored = await _searchBookDao.getEnabledHasCover(name, author);
      for (final book in stored) {
        if (!_covers.any((cover) => cover.book.coverUrl == book.coverUrl)) {
          _covers.add(
            AggregatedSearchBook(book: book, sources: const ['本地記錄']),
          );
        }
      }

      final enabledSources = await _sourceDao.getEnabled();
      final coverSources =
          enabledSources
              .where(
                (source) =>
                    source.ruleSearch?.coverUrl != null &&
                    source.ruleSearch!.coverUrl!.isNotEmpty,
              )
              .toList();

      _totalSources = coverSources.length;
      if (_totalSources == 0) return;

      final threadCount = await SharedPreferences.getInstance().then(
        (prefs) => prefs.getInt('thread_count') ?? 8,
      );
      final coverPool = Pool(threadCount);

      final tasks = <Future<bool>>[];
      for (final source in coverSources) {
        if (!_isSearching) break;
        tasks.add(
          coverPool.withResource(
            () => _searchSingleSource(source, name, author),
          ),
        );
      }
      final results = await Future.wait(tasks);
      if (_isSearching && results.isNotEmpty && results.every((ok) => !ok)) {
        _errorMessage = '封面搜尋失敗，請重試';
      }
    } catch (error) {
      AppLog.e('搜尋封面失敗: $error', error: error);
      _errorMessage = '封面搜尋失敗，請重試';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<bool> _searchSingleSource(
    BookSource source,
    String name,
    String author,
  ) async {
    if (!_isSearching) return true;
    try {
      final books = await _service.searchBooks(source, name);

      final filtered = books.where(
        (book) =>
            book.name == name &&
            (author.isEmpty ||
                (book.author?.contains(author) ?? false) ||
                author.contains(book.author ?? '')),
      );

      for (final result in filtered) {
        if (!_isSearching) break;
        if (result.coverUrl != null && result.coverUrl!.isNotEmpty) {
          if (!_covers.any((cover) => cover.book.coverUrl == result.coverUrl)) {
            final aggregated = AggregatedSearchBook(
              book: result,
              sources: [result.originName ?? '未知'],
            );
            _covers.add(aggregated);
            await _searchBookDao.upsert(aggregated.book);
            notifyListeners();
          }
        }
      }
      return true;
    } catch (error) {
      AppLog.e(
        '搜尋封面書源 ${source.bookSourceName} 失敗: $error',
        error: error,
      );
      return false;
    } finally {
      _searchCount++;
      notifyListeners();
    }
  }
}

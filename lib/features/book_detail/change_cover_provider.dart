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

  List<AggregatedSearchBook> _covers = []; // 修正類型
  bool _isSearching = false;
  int _searchCount = 0;
  int _totalSources = 0;

  List<AggregatedSearchBook> get covers => _covers;
  bool get isSearching => _isSearching;
  double get progress => _totalSources == 0 ? 0 : _searchCount / _totalSources;

  // 預設封面虛擬項 (原 Android defaultCover)
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
    _isSearching = false;
    _searchCount = 0;
    _totalSources = 0;
    notifyListeners();
  }

  /// 先載入資料庫中既有封面，再視需要發起搜尋。
  Future<void> init(String name, String author) async {
    _covers = [_buildDefaultCoverItem(name, author)];
    notifyListeners();

    // 1. 先從資料庫加載既有封面
    final stored = await _searchBookDao.getEnabledHasCover(name, author);
    if (stored.isNotEmpty) {
      for (var b in stored) {
        if (!_covers.any((c) => c.book.coverUrl == b.coverUrl)) {
          _covers.add(AggregatedSearchBook(book: b, sources: ['本地記錄']));
        }
      }
      notifyListeners();
    }

    // 2. 若本地沒有記錄，自動發起搜尋
    if (stored.isEmpty) {
      search(name, author);
    }
  }

  Future<void> search(String name, String author) async {
    _isSearching = false;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 50));

    _isSearching = true;
    _covers = [_buildDefaultCoverItem(name, author)];
    _searchCount = 0;
    notifyListeners();

    final stored = await _searchBookDao.getEnabledHasCover(name, author);
    for (var b in stored) {
      if (!_covers.any((c) => c.book.coverUrl == b.coverUrl)) {
        _covers.add(AggregatedSearchBook(book: b, sources: ['本地記錄']));
      }
    }

    final enabledSources = await _sourceDao.getEnabled();
    final coverSources =
        enabledSources
            .where(
              (s) =>
                  s.ruleSearch?.coverUrl != null &&
                  s.ruleSearch!.coverUrl!.isNotEmpty,
            )
            .toList();

    _totalSources = coverSources.length;
    if (_totalSources == 0) {
      _isSearching = false;
      notifyListeners();
      return;
    }

    final threadCount = await SharedPreferences.getInstance().then(
      (p) => p.getInt('thread_count') ?? 8,
    );
    final coverPool = Pool(threadCount);

    final tasks = <Future<void>>[];
    for (final source in coverSources) {
      if (!_isSearching) break;
      tasks.add(
        coverPool.withResource(() => _searchSingleSource(source, name, author)),
      );
    }

    await Future.wait(tasks);
    _isSearching = false;
    notifyListeners();
  }

  Future<void> _searchSingleSource(
    BookSource source,
    String name,
    String author,
  ) async {
    if (!_isSearching) return;
    try {
      final books = await _service.searchBooks(source, name);

      final filtered = books.where(
        (b) =>
            b.name == name &&
            (author.isEmpty ||
                (b.author?.contains(author) ?? false) ||
                author.contains(b.author ?? '')),
      );

      for (var result in filtered) {
        if (result.coverUrl != null && result.coverUrl!.isNotEmpty) {
          if (!_covers.any((c) => c.book.coverUrl == result.coverUrl)) {
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
    } catch (e) {
      AppLog.e('搜尋封面書源 ${source.bookSourceName} 失敗: $e', error: e);
    } finally {
      _searchCount++;
      notifyListeners();
    }
  }
}

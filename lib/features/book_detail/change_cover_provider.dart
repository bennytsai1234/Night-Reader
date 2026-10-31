import 'package:flutter/foundation.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/search/search_model.dart';
import 'package:pool/pool.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/di/injection.dart';

/// 換封面面板的狀態；每次開面板建立一個，關閉時停止搜尋。
class ChangeCoverProvider extends ChangeNotifier {
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    // 還在排隊或進行中的書源搜尋看到這個旗標就不再寫入結果。
    _isSearching = false;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// 正在套用封面（下載並儲存圖片可能要好幾秒）。期間忽略其他點選，
  /// 連點才不會在面板關閉後再多 pop 一層、把詳情頁也關掉。
  bool get isApplying => _isApplying;
  bool _isApplying = false;

  /// 以「套用中」包住一次套用；已經在套用時回傳 null、不執行。
  Future<T?> runApplying<T>(Future<T> Function() apply) async {
    if (_isApplying) return null;
    _isApplying = true;
    notifyListeners();
    try {
      return await apply();
    } finally {
      _isApplying = false;
      notifyListeners();
    }
  }

  ChangeCoverProvider({BookSourceService? service})
    : _service = service ?? BookSourceService();

  final BookSourceDao _sourceDao = getIt<BookSourceDao>();
  final SearchBookDao _searchBookDao = getIt<SearchBookDao>();
  final BookSourceService _service;

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
      final stored = await _addStoredCovers(await _coverNames(name), author);
      // 等的時候面板關了：不再開始搜尋。
      if (_disposed) return;
      _isInitialized = true;
      notifyListeners();

      if (stored == 0) {
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
    if (_isSearching || _disposed) return;
    _isInitialized = true;
    _isSearching = true;
    _errorMessage = null;
    _covers = [_buildDefaultCoverItem(name, author)];
    _searchCount = 0;
    _totalSources = 0;
    notifyListeners();

    try {
      final names = await _coverNames(name);
      await _addStoredCovers(names, author);

      final enabledSources = await _sourceDao.getEnabled();
      final coverSources = enabledSources
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
            () => _searchSingleSource(source, name, names, author),
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

  /// 封面候選的書名：原文與繁簡兩種寫法（[searchKeyVariants]）。網路結果與
  /// 資料庫紀錄都只認這幾個書名，資料庫按書名撈得到的範圍就是網路會收的
  /// 範圍，存得進去就讀得回來。
  Future<Set<String>> _coverNames(String name) async {
    try {
      await ChineseUtils.initialize();
    } catch (error) {
      AppLog.w('繁簡字典載入失敗，這次換封面只用原文書名: $error');
    }
    return searchKeyVariants(name).toSet();
  }

  /// [result] 是不是這本書的封面候選：書名是 [names] 之一，作者照
  /// [isSameBook] 的正規化比，任一邊沒寫作者時只比書名。搜尋時存進資料庫的
  /// 與下次從資料庫讀回的照同一條判斷。
  static bool _isCoverOf(SearchBook result, Set<String> names, String author) =>
      names.contains(result.name) &&
      isSameBook(
        result.name,
        result.author,
        result.name,
        author,
        checkAuthor:
            normalizeSearchText(author).isNotEmpty &&
            normalizeSearchText(result.author).isNotEmpty,
      );

  /// 把資料庫裡這本書的封面候選加進清單，回傳讀到幾個；面板已經關了時
  /// 不加。
  Future<int> _addStoredCovers(Set<String> names, String author) async {
    final stored = (await _searchBookDao.getEnabledWithCoverByNames(names))
        .where((book) => _isCoverOf(book, names, author))
        .toList();
    if (_disposed) return 0;
    for (final book in stored) {
      if (!_covers.any((cover) => cover.book.coverUrl == book.coverUrl)) {
        _covers.add(AggregatedSearchBook(book: book, sources: const ['本地記錄']));
      }
    }
    return stored.length;
  }

  Future<bool> _searchSingleSource(
    BookSource source,
    String name,
    Set<String> names,
    String author,
  ) async {
    if (!_isSearching) return true;
    try {
      final books = await _service.searchBooks(source, name);

      final filtered = books.where((book) => _isCoverOf(book, names, author));

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
      AppLog.e('搜尋封面書源 ${source.bookSourceName} 失敗: $error', error: error);
      return false;
    } finally {
      _searchCount++;
      notifyListeners();
    }
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';

import 'bookshelf_provider_base.dart';

/// BookshelfProvider 的 UI 狀態與分組邏輯擴展
mixin BookshelfLogicMixin on BookshelfProviderBase {
  void loadUiPreferences() {
    final prefs = getIt<SharedPreferences>();
    isGridView = prefs.getBool('bookshelf_is_grid') ?? isGridView;
    showLastUpdate =
        prefs.getBool('bookshelf_show_last_update') ?? showLastUpdate;
    UnifiedCovers.enabled.value =
        prefs.getBool(_unifiedCoversKey) ?? UnifiedCovers.enabled.value;
    final savedSort = prefs.getInt(PreferKey.bookshelfSort);
    if (savedSort != null &&
        savedSort >= 0 &&
        savedSort < BookshelfSortMode.values.length) {
      sortMode = BookshelfSortMode.values[savedSort];
    }
    _readShelfSkeleton(prefs.getString(_skeletonKey));
  }

  /// 上次書架讀完時的樣子：本數與前面幾本的書名、作者，JSON
  /// `{"count": n, "books": [[書名, 作者], ...]}`。
  static const String _skeletonKey = 'bookshelf_skeleton';

  /// 記下書名的本數：最高的手機加上最小字級，一個畫面也放不到 30 本書卡
  /// （網格每列 3 本約 10 列），再多也畫不到。
  static const int skeletonTitleLimit = 30;

  /// 確定寫進偏好設定的內容；寫入失敗時不更新，下次載入書架再寫一次。
  String? _savedSkeleton;

  void _readShelfSkeleton(String? saved) {
    _savedSkeleton = saved;
    if (saved == null) return;
    try {
      final json = jsonDecode(saved) as Map<String, dynamic>;
      lastBookCount = json['count'] as int;
      lastShelfTitles = [
        for (final entry in json['books'] as List<dynamic>)
          (name: entry[0] as String, author: entry[1] as String),
      ];
    } catch (error) {
      AppLog.w('書架骨架的紀錄讀不懂，這次鋪滿畫面: $error');
      lastBookCount = null;
      lastShelfTitles = const [];
    }
  }

  /// 記下書架上的本數與前面幾本的書名、作者，下次開 App 的骨架照著畫。
  /// 寫入在背景進行，失敗只記日誌，不算書架載入失敗。
  void rememberShelf(List<Book> books) {
    lastBookCount = books.length;
    lastShelfTitles = [
      for (final book in books.take(skeletonTitleLimit))
        (name: book.name, author: book.author),
    ];
    final encoded = jsonEncode({
      'count': lastBookCount,
      'books': [
        for (final title in lastShelfTitles) [title.name, title.author],
      ],
    });
    if (_savedSkeleton == encoded) return;
    unawaited(_saveShelfSkeleton(encoded));
  }

  Future<void> _saveShelfSkeleton(String encoded) async {
    try {
      if (await getIt<SharedPreferences>().setString(_skeletonKey, encoded)) {
        _savedSkeleton = encoded;
      } else {
        AppLog.w('書架骨架沒有寫進偏好設定');
      }
    } catch (error, stackTrace) {
      AppLog.e('書架骨架寫入失敗: $error', error: error, stackTrace: stackTrace);
    }
  }

  void setGridView(bool value) {
    if (isGridView == value) return;
    isGridView = value;
    SharedPreferences.getInstance().then(
      (p) => p.setBool('bookshelf_is_grid', isGridView),
    );
    notifyListeners();
  }

  static const String _unifiedCoversKey = 'bookshelf_unified_covers';

  /// 統一封面：書架上的書一律畫預設封面（見 [UnifiedCovers]）。
  bool get unifiedCovers => UnifiedCovers.enabled.value;

  void setUnifiedCovers(bool value) {
    if (unifiedCovers == value) return;
    UnifiedCovers.enabled.value = value;
    SharedPreferences.getInstance().then(
      (p) => p.setBool(_unifiedCoversKey, value),
    );
    notifyListeners();
  }

  Future<void> setSortMode(BookshelfSortMode value) async {
    if (sortMode == value) return;
    sortMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(PreferKey.bookshelfSort, value.index);
    await loadBooks();
  }

  Future<void> reorderBooks(int oldIndex, int newIndex) async {
    if (sortMode != BookshelfSortMode.custom) return;
    if (oldIndex < 0 ||
        oldIndex >= books.length ||
        newIndex < 0 ||
        newIndex > books.length) {
      return;
    }
    final item = books.removeAt(oldIndex);
    books.insert(newIndex, item);
    for (var i = 0; i < books.length; i++) {
      books[i].order = i;
      await bookDao.upsert(books[i]);
    }
    notifyListeners();
  }
}

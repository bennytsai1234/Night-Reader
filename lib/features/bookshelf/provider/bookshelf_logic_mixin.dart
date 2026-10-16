import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/di/injection.dart';
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
    lastBookCount = _savedBookCount = prefs.getInt(_bookCountKey);
  }

  static const String _bookCountKey = 'bookshelf_book_count';

  /// 確定寫進偏好設定的本數；寫入失敗時不更新，下次載入書架再寫一次。
  int? _savedBookCount;

  /// 記下書架上的本數，下次開 App 的骨架畫一樣多本。寫入在背景進行，
  /// 失敗只記日誌，不算書架載入失敗。
  void rememberBookCount(int count) {
    lastBookCount = count;
    if (_savedBookCount == count) return;
    unawaited(_saveBookCount(count));
  }

  Future<void> _saveBookCount(int count) async {
    try {
      if (await getIt<SharedPreferences>().setInt(_bookCountKey, count)) {
        _savedBookCount = count;
      } else {
        AppLog.w('書架本數沒有寫進偏好設定');
      }
    } catch (error, stackTrace) {
      AppLog.e('書架本數寫入失敗: $error', error: error, stackTrace: stackTrace);
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

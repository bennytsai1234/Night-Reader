import 'package:shared_preferences/shared_preferences.dart';
import 'package:reader/core/constant/prefer_key.dart';
import 'package:reader/core/di/injection.dart';
import 'bookshelf_provider_base.dart';

/// BookshelfProvider 的 UI 狀態與分組邏輯擴展
mixin BookshelfLogicMixin on BookshelfProviderBase {
  void loadUiPreferences() {
    final prefs = getIt<SharedPreferences>();
    isGridView = prefs.getBool('bookshelf_is_grid') ?? isGridView;
    showLastUpdate =
        prefs.getBool('bookshelf_show_last_update') ?? showLastUpdate;
    final savedSort = prefs.getInt(PreferKey.bookshelfSort);
    if (savedSort != null &&
        savedSort >= 0 &&
        savedSort < BookshelfSortMode.values.length) {
      sortMode = BookshelfSortMode.values[savedSort];
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

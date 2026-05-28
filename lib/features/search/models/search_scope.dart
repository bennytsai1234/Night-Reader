import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SearchScope - 搜尋範圍管理
/// (對標 Legado SearchScope.kt)
///
/// 支援三種模式：
/// - 全部書源 (scope == '')
/// - 書源分組 (scope == 'group1,group2,...')
/// - 單一書源 (scope == 'sourceName::sourceUrl')
class SearchScope {
  String _scope;

  static const String _prefKey = 'search_scope';

  SearchScope([this._scope = '']);

  factory SearchScope.fromSource(BookSource source) {
    final name = source.bookSourceName.replaceAll(':', '');
    return SearchScope('$name::${source.bookSourceUrl}');
  }

  factory SearchScope.fromGroups(List<String> groups) {
    return SearchScope(groups.join(','));
  }

  @override
  String toString() => _scope;

  /// 是否為單一書源模式
  bool get isSource => _scope.contains('::');

  /// 是否為全部書源
  bool get isAll => _scope.isEmpty;

  /// 顯示名稱
  String get display {
    if (_scope.contains('::')) {
      return _scope.substring(0, _scope.indexOf('::'));
    }
    if (_scope.isEmpty) {
      return '全部書源';
    }
    return _scope;
  }

  /// 顯示名稱列表
  List<String> get displayNames {
    if (_scope.contains('::')) {
      return [_scope.substring(0, _scope.indexOf('::'))];
    }
    if (_scope.isEmpty) return [];
    return _scope.split(',').where((s) => s.isNotEmpty).toList();
  }

  /// 更新為全部
  void updateAll() {
    _scope = '';
    _save();
  }

  /// 移除某個分組
  void removeGroup(String group) {
    if (isSource) {
      _scope = '';
    } else {
      final groups = _scope.split(',').where((s) => s != group).toList();
      _scope = groups.join(',');
    }
    _save();
  }

  /// 取得搜尋範圍內的書源列表 (對標 getBookSourceParts)
  Future<List<BookSource>> getBookSources() async {
    final dao = getIt<BookSourceDao>();

    if (_scope.isEmpty) {
      // 全部啟用書源
      return _sortSources(
        (await dao.getEnabled())
            .where((source) => source.isSearchEnabledByRuntime)
            .toList(),
      );
    }

    if (_scope.contains('::')) {
      // 單一書源
      final url = _scope.substring(_scope.indexOf('::') + 2);
      final source = await dao.getByUrl(url);
      if (source == null || !source.isSearchEnabledByRuntime) {
        return [];
      }
      return _sortSources([source]);
    }

    // 分組模式
    final groups = _scope.split(',').where((s) => s.isNotEmpty).toList();
    final allEnabled =
        (await dao.getEnabled())
            .where((source) => source.isSearchEnabledByRuntime)
            .toList();
    final result = <BookSource>[];
    final validGroups = <String>[];

    for (final group in groups) {
      final matched =
          allEnabled.where((s) {
            final g = s.bookSourceGroup ?? '';
            return g.split(',').map((e) => e.trim()).contains(group);
          }).toList();
      if (matched.isNotEmpty) {
        validGroups.add(group);
        result.addAll(matched);
      }
    }

    // 若分組內已無可用書源，退回全部
    if (result.isEmpty) {
      _scope = '';
      return _sortSources(
        (await dao.getEnabled())
            .where((source) => source.isSearchEnabledByRuntime)
            .toList(),
      );
    }

    // 清理無效分組
    if (validGroups.length != groups.length) {
      _scope = validGroups.join(',');
      _save();
    }

    // 去重
    final seen = <String>{};
    result.retainWhere((s) => seen.add(s.bookSourceUrl));

    return _sortSources(result);
  }

  List<BookSource> _sortSources(List<BookSource> sources) {
    final sorted = List<BookSource>.from(sources);
    sorted.sort((a, b) => a.customOrder.compareTo(b.customOrder));
    return sorted;
  }

  /// 持久化
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _scope);
  }

  /// 從持久化載入
  static Future<SearchScope> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SearchScope(prefs.getString(_prefKey) ?? '');
  }
}

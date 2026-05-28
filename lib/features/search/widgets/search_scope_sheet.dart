import 'package:flutter/material.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'package:reader/core/database/dao/book_source_dao.dart';
import 'package:reader/core/di/injection.dart';
import 'package:reader/core/models/book_source.dart';
import '../models/search_scope.dart';

/// SearchScopeSheet - 搜尋範圍選擇底部彈窗
/// (對標 Legado SearchScopeDialog)
///
/// 功能：
/// - 分組模式（Checkbox 多選）
/// - 書源模式（Radio 單選）
/// - 書源模式支援搜尋篩選
/// - 「全部書源」快捷按鈕
class SearchScopeSheet extends StatefulWidget {
  final SearchScope currentScope;
  final List<String> groups;
  final ValueChanged<SearchScope> onScopeChanged;

  const SearchScopeSheet({
    super.key,
    required this.currentScope,
    required this.groups,
    required this.onScopeChanged,
  });

  /// 顯示底部彈窗
  static void show(
    BuildContext context, {
    required SearchScope currentScope,
    required List<String> groups,
    required ValueChanged<SearchScope> onScopeChanged,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.topSheetLg),
      builder:
          (_) => SearchScopeSheet(
            currentScope: currentScope,
            groups: groups,
            onScopeChanged: onScopeChanged,
          ),
    );
  }

  @override
  State<SearchScopeSheet> createState() => _SearchScopeSheetState();
}

class _SearchScopeSheetState extends State<SearchScopeSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 分組模式
  final Set<String> _selectedGroups = {};

  // 書源模式
  BookSource? _selectedSource;
  List<BookSource> _allSources = [];
  List<BookSource> _filteredSources = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.currentScope.isSource ? 1 : 0,
    );

    // 初始化選中狀態
    if (!widget.currentScope.isAll && !widget.currentScope.isSource) {
      _selectedGroups.addAll(widget.currentScope.displayNames);
    }

    _loadSources();
  }

  Future<void> _loadSources() async {
    final dao = getIt<BookSourceDao>();
    _allSources =
        (await dao.getAll())
            .where((source) => source.isSearchEnabledByRuntime)
            .toList()
          ..sort((a, b) => a.customOrder.compareTo(b.customOrder));
    _filteredSources = List.from(_allSources);

    // 如果當前是單一書源模式，嘗試找到對應書源
    if (widget.currentScope.isSource) {
      final scopeStr = widget.currentScope.toString();
      final url = scopeStr.substring(scopeStr.indexOf('::') + 2);
      _selectedSource =
          _allSources.where((s) => s.bookSourceUrl == url).firstOrNull;
    }

    if (mounted) setState(() {});
  }

  void _filterSources(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredSources = List.from(_allSources);
      } else {
        _filteredSources =
            _allSources.where((s) {
              return s.bookSourceName.toLowerCase().contains(
                    query.toLowerCase(),
                  ) ||
                  s.bookSourceUrl.toLowerCase().contains(query.toLowerCase());
            }).toList();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 標題列
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '搜尋範圍',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          widget.onScopeChanged(SearchScope());
                          Navigator.pop(context);
                        },
                        child: const Text('全部書源'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _onConfirm,
                        child: const Text('確定'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Tab 切換
            TabBar(
              controller: _tabController,
              tabs: const [Tab(text: '分組'), Tab(text: '書源')],
            ),
            // Tab 內容
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGroupTab(scrollController),
                  _buildSourceTab(scrollController),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 分組模式：Checkbox 多選
  Widget _buildGroupTab(ScrollController scrollController) {
    if (widget.groups.isEmpty) {
      return Center(
        child: Text(
          '暫無分組',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      itemCount: widget.groups.length,
      itemBuilder: (context, index) {
        final group = widget.groups[index];
        final isSelected = _selectedGroups.contains(group);
        return CheckboxListTile(
          title: Text(group),
          value: isSelected,
          onChanged: (checked) {
            setState(() {
              if (checked == true) {
                _selectedGroups.add(group);
              } else {
                _selectedGroups.remove(group);
              }
            });
          },
        );
      },
    );
  }

  /// 書源模式：Radio 單選 + 搜尋
  Widget _buildSourceTab(ScrollController scrollController) {
    return Column(
      children: [
        // 搜尋框
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: '搜尋書源',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: AppRadius.cardSm),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
            onChanged: _filterSources,
          ),
        ),
        Expanded(
          child:
              _filteredSources.isEmpty
                  ? Center(
                    child: Text(
                      '無匹配書源',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                  : RadioGroup<String>(
                    groupValue: _selectedSource?.bookSourceUrl,
                    onChanged: (String? value) {
                      if (value != null) {
                        setState(() {
                          _selectedSource = _filteredSources.firstWhere(
                            (s) => s.bookSourceUrl == value,
                          );
                        });
                      }
                    },
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: _filteredSources.length,
                      itemBuilder: (context, index) {
                        final source = _filteredSources[index];
                        return ListTile(
                          leading: Radio<String>(value: source.bookSourceUrl),
                          title: Text(
                            source.bookSourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            source.bookSourceUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelXs.copyWith(
                              color:
                                  Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedSource = source;
                            });
                          },
                        );
                      },
                    ),
                  ),
        ),
      ],
    );
  }

  void _onConfirm() {
    final SearchScope newScope;
    if (_tabController.index == 0) {
      // 分組模式
      if (_selectedGroups.isEmpty) {
        newScope = SearchScope(); // 無選擇 = 全部
      } else {
        newScope = SearchScope.fromGroups(_selectedGroups.toList());
      }
    } else {
      // 書源模式
      if (_selectedSource != null) {
        newScope = SearchScope.fromSource(_selectedSource!);
      } else {
        newScope = SearchScope(); // 無選擇 = 全部
      }
    }
    widget.onScopeChanged(newScope);
    Navigator.pop(context);
  }
}

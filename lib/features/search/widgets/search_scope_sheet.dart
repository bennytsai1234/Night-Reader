import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/glass_segmented.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import '../models/search_scope.dart';
import 'package:night_reader/shared/widgets/search_field.dart';
import 'package:night_reader/shared/widgets/glass.dart';

/// SearchScopeSheet - 搜尋範圍選擇底部彈窗
/// (對標 Legado SearchScopeDialog)
///
/// 功能：
/// - 分組模式（打勾列多選）
/// - 書源模式（打勾列單選）
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

  static void show(
    BuildContext context, {
    required SearchScope currentScope,
    required List<String> groups,
    required ValueChanged<SearchScope> onScopeChanged,
  }) {
    AppBottomSheet.showCustom(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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

/// 範圍面板的兩種選法。
enum _ScopeMode { groups, source }

class _SearchScopeSheetState extends State<SearchScopeSheet> {
  late _ScopeMode _mode;
  final Set<String> _selectedGroups = {};
  BookSource? _selectedSource;
  List<BookSource> _allSources = [];
  List<BookSource> _filteredSources = [];
  final TextEditingController _searchController = TextEditingController();
  bool _sourcesLoading = true;
  Object? _sourcesLoadError;

  @override
  void initState() {
    super.initState();
    _mode =
        widget.currentScope.isSource ? _ScopeMode.source : _ScopeMode.groups;
    if (!widget.currentScope.isAll && !widget.currentScope.isSource) {
      _selectedGroups.addAll(widget.currentScope.displayNames);
    }
    _loadSources();
  }

  Future<void> _loadSources() async {
    if (mounted) {
      setState(() {
        _sourcesLoading = true;
        _sourcesLoadError = null;
      });
    }
    try {
      final dao = getIt<BookSourceDao>();
      final sources =
          (await dao.getAll())
              .where((source) => source.isSearchEnabledByRuntime)
              .toList()
            ..sort((a, b) => a.customOrder.compareTo(b.customOrder));
      if (!mounted) return;
      _allSources = sources;
      _filteredSources = List.from(_allSources);

      if (widget.currentScope.isSource) {
        final scopeStr = widget.currentScope.toString();
        final url = scopeStr.substring(scopeStr.indexOf('::') + 2);
        _selectedSource =
            _allSources.where((s) => s.bookSourceUrl == url).firstOrNull;
      }
    } catch (error) {
      if (!mounted) return;
      _sourcesLoadError = error;
      _allSources = [];
      _filteredSources = [];
    } finally {
      if (mounted) setState(() => _sourcesLoading = false);
    }
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
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(
              title: '搜尋範圍',
              leading: PlainTextAction(
                label: '全部書源',
                onPressed: () {
                  widget.onScopeChanged(SearchScope());
                  Navigator.pop(context);
                },
              ),
              trailing: PlainTextAction(
                label: '確定',
                emphasized: true,
                onPressed: _onConfirm,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppGrouped.margin,
                AppSpacing.xs,
                AppGrouped.margin,
                AppSpacing.sm,
              ),
              child: GlassSegmented<_ScopeMode>(
                segments: const [
                  GlassSegment(_ScopeMode.groups, '分組'),
                  GlassSegment(_ScopeMode.source, '書源'),
                ],
                selected: _mode,
                onChanged: (mode) => setState(() => _mode = mode),
              ),
            ),
            // 兩種清單共用面板的捲動控制器，不做交叉淡入，避免同時掛上兩個清單。
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(_mode),
                child:
                    _mode == _ScopeMode.groups
                        ? _buildGroupTab(scrollController)
                        : _buildSourceTab(scrollController),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyHint(String text) {
    return Center(
      child: Text(
        text,
        style: AppTextStyles.bodyBase.copyWith(
          color: AppChrome.of(context).sectionText,
        ),
      ),
    );
  }

  EdgeInsets _listPadding() => EdgeInsets.only(
    top: AppSpacing.sm,
    bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
  );

  Widget _buildGroupTab(ScrollController scrollController) {
    if (widget.groups.isEmpty) {
      return _emptyHint('暫無分組');
    }

    final primary = Theme.of(context).colorScheme.primary;
    final count = widget.groups.length;
    return ListView.builder(
      controller: scrollController,
      padding: _listPadding(),
      itemCount: count,
      itemBuilder: (context, index) {
        final group = widget.groups[index];
        final isSelected = _selectedGroups.contains(group);
        // 分組可複選：打勾表示納入，不套用互斥語意的 GroupedCheckRow。
        return GroupedSliceItem(
          index: index,
          count: count,
          child: Semantics(
            checked: isSelected,
            child: GroupedRow(
              title: group,
              showChevron: false,
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _selectedGroups.remove(group);
                  } else {
                    _selectedGroups.add(group);
                  }
                });
              },
              trailing: SizedBox(
                width: 22,
                child:
                    isSelected
                        ? Icon(Icons.check_rounded, size: 22, color: primary)
                        : null,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSourceTab(ScrollController scrollController) {
    if (_sourcesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sourcesLoadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '書源載入失敗',
              style: AppTextStyles.bodyBase.copyWith(
                color: AppChrome.of(context).sectionText,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            PlainTextAction(label: '重試', onPressed: _loadSources),
          ],
        ),
      );
    }

    final count = _filteredSources.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppGrouped.margin,
            AppSpacing.xs,
            AppGrouped.margin,
            AppSpacing.xs,
          ),
          child: SearchField(
            controller: _searchController,
            hintText: '搜尋書源',
            textInputAction: TextInputAction.done,
            onChanged: _filterSources,
          ),
        ),
        Expanded(
          child:
              count == 0
                  ? _emptyHint(
                    _allSources.isEmpty ? '目前沒有可搜尋的書源' : '找不到符合條件的書源',
                  )
                  : ListView.builder(
                    controller: scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: _listPadding(),
                    itemCount: count,
                    itemBuilder: (context, index) {
                      final source = _filteredSources[index];
                      return GroupedSliceItem(
                        index: index,
                        count: count,
                        child: GroupedCheckRow(
                          title: source.bookSourceName,
                          subtitle: source.bookSourceUrl,
                          selected:
                              _selectedSource?.bookSourceUrl ==
                              source.bookSourceUrl,
                          onTap: () => setState(() => _selectedSource = source),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  void _onConfirm() {
    final SearchScope newScope;
    if (_mode == _ScopeMode.groups) {
      newScope =
          _selectedGroups.isEmpty
              ? SearchScope()
              : SearchScope.fromGroups(_selectedGroups.toList());
    } else {
      newScope =
          _selectedSource != null
              ? SearchScope.fromSource(_selectedSource!)
              : SearchScope();
    }
    widget.onScopeChanged(newScope);
    Navigator.pop(context);
  }
}

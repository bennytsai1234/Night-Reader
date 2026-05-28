import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/shared/theme/app_text_styles.dart';
import 'package:reader/shared/theme/context_ext.dart';
import 'search_provider.dart';
import 'models/search_scope.dart';
import 'package:reader/core/models/book_source.dart';
import 'package:reader/core/models/search_book.dart';
import 'widgets/search_app_bar.dart';
import 'widgets/search_history_view.dart';
import 'widgets/search_result_item.dart';
import 'widgets/search_scope_sheet.dart';

/// SearchPage - 搜尋頁面
/// (對標 Legado SearchActivity)
class SearchPage extends StatelessWidget {
  final String? initialQuery;
  final BookSource? initialSource;

  const SearchPage({super.key, this.initialQuery, this.initialSource});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create:
          (_) => SearchProvider(
            initialScope:
                initialSource != null
                    ? SearchScope.fromSource(initialSource!)
                    : null,
          ),
      child: _SearchPageContent(
        initialQuery: initialQuery,
        initialSource: initialSource,
      ),
    );
  }
}

class _SearchPageContent extends StatefulWidget {
  final String? initialQuery;
  final BookSource? initialSource;

  const _SearchPageContent({this.initialQuery, this.initialSource});

  @override
  State<_SearchPageContent> createState() => _SearchPageContentState();
}

class _SearchPageContentState extends State<_SearchPageContent> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null || widget.initialSource != null) {
      _controller.text = widget.initialQuery ?? '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final provider = context.read<SearchProvider>();
        if (widget.initialSource != null) {
          provider.searchInSource(widget.initialSource!, _controller.text);
        } else if (_controller.text.isNotEmpty) {
          provider.search(_controller.text);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    if (value.isNotEmpty) {
      context.read<SearchProvider>().search(value);
    }
  }

  void _openScopeSheet() {
    final provider = context.read<SearchProvider>();
    SearchScopeSheet.show(
      context,
      currentScope: provider.searchScope,
      groups: provider.sourceGroups,
      onScopeChanged: (newScope) {
        provider.updateSearchScope(newScope);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          appBar: SearchAppBar(
            controller: _controller,
            provider: provider,
            onSearch: _onSearch,
            onScopePressed: _openScopeSheet,
            onScopeMenuSelected: _openScopeSheet,
          ),
          body: Column(
            children: [
              // 搜尋進度
              if (provider.isSearching) ...[
                LinearProgressIndicator(
                  value: provider.progress,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
                _buildCurrentSourcePanel(provider),
              ],
              // 失敗書源提示
              if (!provider.isSearching && provider.failedSources > 0)
                _buildFailedSourcesPanel(context, provider),
              // 篩選狀態提示
              if (provider.precisionSearch || !provider.searchScope.isAll)
                _buildFilterStatusPanel(provider),
              if (provider.hasUnfilteredResults && !provider.isSearching)
                _buildResultToolbar(context, provider),
              // 主體內容
              Expanded(
                child:
                    provider.results.isEmpty && !provider.isSearching
                        ? _buildEmptyOrHistory(provider)
                        : _buildResults(provider),
              ),
            ],
          ),
          // FAB 開始/停止搜尋 (對標 Legado fb_start_stop)
          floatingActionButton:
              provider.lastSearchKey.isNotEmpty
                  ? FloatingActionButton(
                    mini: true,
                    onPressed:
                        () =>
                            provider.isSearching
                                ? provider.stopSearch()
                                : provider.search(provider.lastSearchKey),
                    child: Icon(
                      provider.isSearching ? Icons.stop : Icons.refresh,
                    ),
                  )
                  : null,
        );
      },
    );
  }

  Widget _buildEmptyOrHistory(SearchProvider provider) {
    if (provider.hasUnfilteredResults &&
        provider.results.isEmpty &&
        provider.hasActiveResultFilters) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.filter_alt_off,
                size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                '沒有符合篩選的結果',
                style: AppTextStyles.bodyMd.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: provider.clearResultFilters,
                icon: const Icon(Icons.clear),
                label: const Text('清除篩選'),
              ),
            ],
          ),
        ),
      );
    }

    if (provider.lastSearchKey.isNotEmpty && provider.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '找不到相關書籍',
              style: AppTextStyles.bodyMd.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (provider.precisionSearch)
              ElevatedButton(
                onPressed: () => provider.togglePrecisionSearch(),
                child: const Text('關閉精準搜尋並重試'),
              ),
            if (!provider.searchScope.isAll) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed:
                    () => provider.updateSearchScope(
                      provider.searchScope..updateAll(),
                    ),
                child: Text('「${provider.searchScope.display}」結果為空，切換至全部書源'),
              ),
            ],
          ],
        ),
      );
    }
    return SearchHistoryView(
      provider: provider,
      controller: _controller,
      onSearch: _onSearch,
    );
  }

  Widget _buildFailedSourcesPanel(BuildContext context, SearchProvider p) =>
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        width: double.infinity,
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.08),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${p.failedSources} 個書源搜尋失敗（共 ${p.totalSources} 個）',
                style: AppTextStyles.labelSm.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _showFailureSheet(context),
              child: const Text('查看'),
            ),
            if (p.sourceFailures.isNotEmpty)
              TextButton(
                onPressed: p.retryFailedSources,
                child: const Text('重試失敗'),
              ),
          ],
        ),
      );

  Widget _buildCurrentSourcePanel(SearchProvider p) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.xs,
    ),
    width: double.infinity,
    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
    child: Text(
      '正在搜尋: ${p.currentSource}  (${p.progress * 100 ~/ 1}%)',
      style: AppTextStyles.labelXs.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );

  Widget _buildFilterStatusPanel(SearchProvider p) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.xs,
    ),
    color: context.warning.withValues(alpha: 0.1),
    child: Row(
      children: [
        Icon(Icons.filter_alt, size: 14, color: context.warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '已開啟: ${p.precisionSearch ? "精準搜尋" : ""} ${!p.searchScope.isAll ? "範圍(${p.searchScope.display})" : ""}',
            style: AppTextStyles.labelSm.copyWith(color: context.warning),
          ),
        ),
        GestureDetector(
          onTap: () {
            if (p.precisionSearch) p.togglePrecisionSearch();
            if (!p.searchScope.isAll) {
              p.updateSearchScope(SearchScope());
            }
          },
          child: Text(
            '全部重設',
            style: AppTextStyles.labelSm.copyWith(
              color: context.warning,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildResultToolbar(BuildContext context, SearchProvider p) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.35)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              '${p.resultCount}/${p.unfilteredResultCount}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<SearchResultSortMode>(
              tooltip: '排序',
              onSelected: p.updateSortMode,
              itemBuilder:
                  (context) =>
                      SearchResultSortMode.values
                          .map(
                            (mode) =>
                                CheckedPopupMenuItem<SearchResultSortMode>(
                                  value: mode,
                                  checked: p.sortMode == mode,
                                  child: Text(mode.displayName),
                                ),
                          )
                          .toList(),
              child: Chip(
                avatar: const Icon(Icons.sort, size: 16),
                label: Text('排序: ${p.sortMode.displayName}'),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: Icon(
                p.hasActiveResultFilters
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
                size: 16,
              ),
              label: Text(p.hasActiveResultFilters ? '篩選中' : '篩選'),
              onPressed: () => _showResultFilterSheet(context),
              visualDensity: VisualDensity.compact,
            ),
            if (p.hasActiveResultFilters) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: '清除篩選',
                icon: const Icon(Icons.close, size: 18),
                onPressed: p.clearResultFilters,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFailureSheet(BuildContext context) {
    final searchProvider = context.read<SearchProvider>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => Provider.value(
            value: searchProvider,
            child: Consumer<SearchProvider>(
              builder: (context, provider, _) {
                final failures = provider.sourceFailures;
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '失敗書源',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            if (failures.isNotEmpty)
                              TextButton.icon(
                                onPressed: provider.retryFailedSources,
                                icon: const Icon(Icons.refresh),
                                label: const Text('重試失敗'),
                              ),
                          ],
                        ),
                        if (failures.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: AppSpacing.xxl,
                            ),
                            child: Text('沒有可查看的失敗明細'),
                          )
                        else
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.sizeOf(context).height * 0.55,
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: failures.length,
                              separatorBuilder:
                                  (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final failure = failures[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(failure.source.bookSourceName),
                                  subtitle: Text(
                                    failure.message,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap:
                                      () => _showTextDialog(
                                        context,
                                        title: failure.source.bookSourceName,
                                        text: failure.message,
                                      ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
    );
  }

  void _showResultFilterSheet(BuildContext context) {
    final provider = context.read<SearchProvider>();
    final authorController = TextEditingController(text: provider.authorFilter);
    final kindController = TextEditingController(text: provider.kindFilter);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (sheetContext) => Provider.value(
            value: provider,
            child: Consumer<SearchProvider>(
              builder: (context, p, _) {
                final sources = p.availableSourceFilters;
                return SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: AppSpacing.lg,
                      right: AppSpacing.lg,
                      bottom:
                          MediaQuery.viewInsetsOf(sheetContext).bottom +
                          AppSpacing.lg,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                '篩選搜尋結果',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () {
                                  authorController.clear();
                                  kindController.clear();
                                  p.clearResultFilters();
                                },
                                child: const Text('清除'),
                              ),
                            ],
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: p.onlyInBookshelf,
                            onChanged: p.setOnlyInBookshelf,
                            title: const Text('只看已加入書架'),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: p.onlyWithCover,
                            onChanged: p.setOnlyWithCover,
                            title: const Text('只看有封面'),
                          ),
                          TextField(
                            controller: authorController,
                            decoration: const InputDecoration(
                              labelText: '作者包含',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            onChanged: p.setAuthorFilter,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: kindController,
                            decoration: const InputDecoration(
                              labelText: '分類包含',
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            onChanged: p.setKindFilter,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '書源',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          if (sources.isEmpty)
                            const Text('目前沒有可篩選的書源')
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children:
                                  sources.map((source) {
                                    return FilterChip(
                                      label: Text(source),
                                      selected: p.sourceFilters.contains(
                                        source,
                                      ),
                                      onSelected:
                                          (_) => p.toggleSourceFilter(source),
                                    );
                                  }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
    ).whenComplete(() {
      authorController.dispose();
      kindController.dispose();
    });
  }

  void _showTextDialog(
    BuildContext context, {
    required String title,
    required String text,
  }) {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(title),
            content: SelectableText(text),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('關閉'),
              ),
            ],
          ),
    );
  }

  Widget _buildResults(SearchProvider p) {
    final results = p.results;
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (ctx, i) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final book = results[i];
        return SearchResultItem(
          result: AggregatedSearchBook(
            book: book,
            sources:
                book.sourceLabels.isNotEmpty
                    ? book.sourceLabels
                    : [book.originName ?? '未知來源'],
          ),
          isInBookshelf: p.isInBookshelf(book),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

import 'search_provider.dart';
import 'models/search_scope.dart';

import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/explore/widgets/explore_book_item.dart';
import 'package:night_reader/features/explore/widgets/glass_capsule.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';

import 'widgets/grouped_slice.dart';
import 'widgets/search_app_bar.dart';
import 'widgets/search_history_view.dart';
import 'widgets/search_result_item.dart';
import 'widgets/search_scope_sheet.dart';
import 'widgets/sheet_header.dart';

/// SearchPage - 搜尋頁面
/// (對標 Legado SearchActivity)
class SearchPage extends StatelessWidget {
  final String? initialQuery;
  final BookSource? initialSource;

  const SearchPage({super.key, this.initialQuery, this.initialSource});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SearchProvider(
        initialScope: initialSource != null
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

  /// Scaffold 內容區的系統內距（含玻璃頁首）。
  EdgeInsets _bodyPadding = EdgeInsets.zero;

  bool get _opensBlank =>
      widget.initialQuery == null && widget.initialSource == null;

  @override
  void initState() {
    super.initState();
    if (!_opensBlank) {
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
      FocusScope.of(context).unfocus();
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
        final showResults =
            !(provider.results.isEmpty && !provider.isSearching);
        return Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: AppChrome.of(context).groupedBackground,
          appBar: SearchAppBar(
            controller: _controller,
            provider: provider,
            onSearch: _onSearch,
            onScopePressed: _openScopeSheet,
            // 從搜尋鈕進來的空白搜尋頁直接聚焦輸入框（Telegram 搜尋的進場方式）。
            autofocus: _opensBlank,
            onCancel: () => Navigator.maybePop(context),
          ),
          // 內距要從 Scaffold 內取得：延伸到頁首下方時 top 才包含頁首高度。
          body: Builder(
            builder: (bodyContext) {
              final padding = MediaQuery.paddingOf(bodyContext);
              _bodyPadding = padding;
              return Stack(
                children: [
                  Positioned.fill(
                    child: showResults
                        ? _buildResults(provider)
                        : _buildEmptyOrHistory(provider),
                  ),
                  if (provider.isSearching)
                    Positioned(
                      // 進度條貼在玻璃頁首實色區的下緣。
                      top: padding.top - AppGlass.headerFadeHeight,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: provider.progress,
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  /// 清單頂端的狀態列；跟著結果或歷史一起捲動。
  List<Widget> _buildPanels(SearchProvider provider) {
    return [
      if (provider.isSearching) _buildCurrentSourcePanel(provider),
      if (!provider.isSearching && provider.failedSources > 0)
        _buildFailedSourcesPanel(context, provider),
      if (provider.precisionSearch || !provider.searchScope.isAll)
        _buildFilterStatusPanel(provider),
      if (provider.hasUnfilteredResults && !provider.isSearching)
        _buildResultToolbar(context, provider),
    ];
  }

  Widget _buildEmptyOrHistory(SearchProvider provider) {
    final state = _buildEmptyState(provider);
    if (state == null) {
      return SearchHistoryView(
        provider: provider,
        controller: _controller,
        onSearch: _onSearch,
        leading: _buildPanels(provider),
      );
    }
    final padding = _bodyPadding;
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: Column(
        children: [
          ..._buildPanels(provider),
          Expanded(child: state),
        ],
      ),
    );
  }

  Widget? _buildEmptyState(SearchProvider provider) {
    if (provider.hasUnfilteredResults &&
        provider.results.isEmpty &&
        provider.hasActiveResultFilters) {
      return AppStateView(
        icon: Icons.filter_alt_off,
        title: '沒有符合篩選的結果',
        description: '目前的結果都被篩選條件排除了。',
        primaryAction: AppStateAction(
          label: '清除篩選',
          icon: Icons.clear,
          onPressed: provider.clearResultFilters,
        ),
      );
    }

    if (provider.lastSearchKey.isNotEmpty && provider.totalSources == 0) {
      final scoped = !provider.searchScope.isAll;
      return AppStateView(
        icon: Icons.source_outlined,
        title: scoped ? '目前範圍沒有可搜尋的書源' : '尚未加入可搜尋的書源',
        description: scoped ? '切換搜尋範圍，或到書源管理調整書源。' : '先加入書源，再回來搜尋書籍。',
        primaryAction: scoped
            ? AppStateAction(
                label: '切換至全部書源',
                icon: Icons.public,
                onPressed: () => provider.updateSearchScope(
                  provider.searchScope..updateAll(),
                ),
              )
            : AppStateAction(
                label: '管理書源',
                icon: Icons.source_outlined,
                onPressed: () => _openSourceManager(),
              ),
        secondaryAction: scoped
            ? AppStateAction(
                label: '管理書源',
                icon: Icons.settings_outlined,
                onPressed: () => _openSourceManager(),
              )
            : null,
      );
    }

    if (provider.lastSearchKey.isNotEmpty && provider.results.isEmpty) {
      final broadenScopeAction = AppStateAction(
        label: '切換至全部書源',
        icon: Icons.public,
        onPressed: () =>
            provider.updateSearchScope(provider.searchScope..updateAll()),
      );
      return AppStateView(
        icon: Icons.search_off,
        title: '找不到相關書籍',
        description: '放寬搜尋條件或搜尋範圍後再試一次。',
        primaryAction: provider.precisionSearch
            ? AppStateAction(
                label: '關閉精準搜尋並重試',
                icon: Icons.tune,
                onPressed: provider.togglePrecisionSearch,
              )
            : provider.searchScope.isAll
            ? null
            : broadenScopeAction,
        secondaryAction: provider.precisionSearch && !provider.searchScope.isAll
            ? broadenScopeAction
            : null,
      );
    }
    return null;
  }

  void _openSourceManager() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SourceManagerPage()),
    );
  }

  /// 清單頂端的提示條：圓角淡色底、圖示、說明與右側文字動作。
  Widget _noticeBar({
    required Color color,
    required IconData icon,
    required String text,
    List<Widget> actions = const [],
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppGrouped.margin,
        AppSpacing.sm,
        AppGrouped.margin,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: AppGrouped.cardRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppGrouped.rowPadding,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.labelSm.copyWith(
                    height: 1.3,
                    color: color,
                  ),
                ),
              ),
              for (final action in actions) ...[
                const SizedBox(width: AppSpacing.md),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFailedSourcesPanel(BuildContext context, SearchProvider p) =>
      _noticeBar(
        color: Theme.of(context).colorScheme.error,
        icon: Icons.warning_amber_rounded,
        text: '${p.failedSources} 個書源搜尋失敗（共 ${p.totalSources} 個）',
        actions: [
          PlainTextAction(
            label: '查看',
            small: true,
            onPressed: () => _showFailureSheet(context),
          ),
          if (p.sourceFailures.isNotEmpty)
            PlainTextAction(
              label: '重試失敗',
              small: true,
              onPressed: p.retryFailedSources,
            ),
        ],
      );

  Widget _buildCurrentSourcePanel(SearchProvider p) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppGrouped.margin + AppGrouped.rowPadding,
      AppSpacing.sm,
      AppGrouped.margin + AppGrouped.rowPadding,
      0,
    ),
    child: Text(
      '正在搜尋：${p.currentSource}（${p.progress * 100 ~/ 1}%）',
      style: AppTextStyles.labelXs.copyWith(
        height: 1.3,
        color: AppChrome.of(context).sectionText,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );

  Widget _buildFilterStatusPanel(SearchProvider p) => _noticeBar(
    color: context.warning,
    icon: Icons.filter_alt,
    text:
        '已開啟：${p.precisionSearch ? "精準搜尋" : ""} ${!p.searchScope.isAll ? "範圍（${p.searchScope.display}）" : ""}',
    actions: [
      PlainTextAction(
        label: '全部重設',
        small: true,
        emphasized: true,
        onPressed: () {
          if (p.precisionSearch) p.togglePrecisionSearch();
          if (!p.searchScope.isAll) {
            p.updateSearchScope(SearchScope());
          }
        },
      ),
    ],
  );

  Widget _buildResultToolbar(BuildContext context, SearchProvider p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppGrouped.margin,
        AppSpacing.sm,
        AppGrouped.margin,
        AppSpacing.xs,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text(
              '${p.resultCount}/${p.unfilteredResultCount}',
              style: AppTextStyles.uiSm.copyWith(
                color: AppChrome.of(context).sectionText,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Builder(
              builder: (anchorContext) => GlassCapsule(
                label: '排序：${p.sortMode.displayName}',
                icon: Icons.sort_rounded,
                trailingIcon: Icons.expand_more_rounded,
                blur: false,
                onTap: () async {
                  final mode = await showGlassMenu<SearchResultSortMode>(
                    context: anchorContext,
                    anchor: globalRectOf(anchorContext),
                    entries: [
                      for (final mode in SearchResultSortMode.values)
                        GlassMenuItem(
                          value: mode,
                          label: mode.displayName,
                          checked: p.sortMode == mode,
                        ),
                    ],
                  );
                  if (mode != null) p.updateSortMode(mode);
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GlassCapsule(
              label: p.hasActiveResultFilters ? '篩選中' : '篩選',
              icon: p.hasActiveResultFilters
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined,
              selected: p.hasActiveResultFilters,
              blur: false,
              onTap: () => _showResultFilterSheet(context),
            ),
            if (p.hasActiveResultFilters) ...[
              const SizedBox(width: AppSpacing.sm),
              GlassCapsule(
                label: '清除',
                icon: Icons.close_rounded,
                tooltip: '清除篩選',
                blur: false,
                onTap: p.clearResultFilters,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFailureSheet(BuildContext context) {
    final searchProvider = context.read<SearchProvider>();
    AppBottomSheet.showCustom<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppChrome.of(context).groupedBackground,
      builder: (sheetContext) => Provider.value(
        value: searchProvider,
        child: Consumer<SearchProvider>(
          builder: (context, provider, _) {
            final failures = provider.sourceFailures;
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.7,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SheetHeader(
                      title: '失敗書源',
                      trailing: failures.isNotEmpty
                          ? PlainTextAction(
                              label: '重試失敗',
                              onPressed: provider.retryFailedSources,
                            )
                          : null,
                    ),
                    if (failures.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xxl,
                        ),
                        child: Text(
                          '沒有可查看的失敗明細',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyBase.copyWith(
                            color: AppChrome.of(context).sectionText,
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(
                            top: AppSpacing.sm,
                            bottom: AppSpacing.xl,
                          ),
                          itemCount: failures.length,
                          itemBuilder: (context, index) {
                            final failure = failures[index];
                            return GroupedSliceItem(
                              index: index,
                              count: failures.length,
                              child: GroupedRow(
                                title: failure.source.bookSourceName,
                                subtitle: failure.message,
                                onTap: () => _showTextDialog(
                                  context,
                                  title: failure.source.bookSourceName,
                                  text: failure.message,
                                ),
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

    AppBottomSheet.showCustom<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppChrome.of(context).groupedBackground,
      builder: (sheetContext) => Provider.value(
        value: provider,
        child: Consumer<SearchProvider>(
          builder: (context, p, _) {
            final sources = p.availableSourceFilters;
            final primary = Theme.of(context).colorScheme.primary;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SheetHeader(
                        title: '篩選搜尋結果',
                        trailing: PlainTextAction(
                          label: '清除',
                          onPressed: () {
                            authorController.clear();
                            kindController.clear();
                            p.clearResultFilters();
                          },
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GroupedSection(
                                topGap: AppSpacing.sm,
                                children: [
                                  GroupedSwitchRow(
                                    title: '只看已加入書架',
                                    value: p.onlyInBookshelf,
                                    onChanged: p.setOnlyInBookshelf,
                                  ),
                                  GroupedSwitchRow(
                                    title: '只看有封面',
                                    value: p.onlyWithCover,
                                    onChanged: p.setOnlyWithCover,
                                  ),
                                ],
                              ),
                              GroupedSection(
                                header: '內容',
                                children: [
                                  GroupedTextFieldRow(
                                    label: '作者包含',
                                    controller: authorController,
                                    hintText: '不限',
                                    onChanged: p.setAuthorFilter,
                                  ),
                                  GroupedTextFieldRow(
                                    label: '分類包含',
                                    controller: kindController,
                                    hintText: '不限',
                                    onChanged: p.setKindFilter,
                                  ),
                                ],
                              ),
                              if (sources.isEmpty)
                                const GroupedSection(
                                  header: '書源',
                                  children: [GroupedRow(title: '目前沒有可篩選的書源')],
                                )
                              else
                                GroupedSection(
                                  header: '書源',
                                  footer: '可複選；不選表示不限書源。',
                                  children: [
                                    for (final source in sources)
                                      Semantics(
                                        checked: p.sourceFilters.contains(
                                          source,
                                        ),
                                        child: GroupedRow(
                                          title: source,
                                          showChevron: false,
                                          onTap: () =>
                                              p.toggleSourceFilter(source),
                                          trailing: SizedBox(
                                            width: 22,
                                            child:
                                                p.sourceFilters.contains(source)
                                                ? Icon(
                                                    Icons.check_rounded,
                                                    size: 22,
                                                    color: primary,
                                                  )
                                                : null,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
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
    showAppAlert<void>(
      context: context,
      title: title,
      content: SelectableText(text, style: AppTextStyles.bodySm),
      actions: const [
        AppAlertAction(label: '關閉', value: null, isDefault: true),
      ],
    );
  }

  Widget _buildResults(SearchProvider p) {
    final results = p.results;
    final panels = _buildPanels(p);
    final padding = _bodyPadding;
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: padding.top,
        bottom: padding.bottom + AppSpacing.xl,
      ),
      itemCount: panels.length + results.length,
      itemBuilder: (ctx, i) {
        if (i < panels.length) return panels[i];
        final index = i - panels.length;
        final book = results[index];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (index > 0)
              const InsetSeparator(indent: ExploreBookItem.textIndent),
            SearchResultItem(
              result: AggregatedSearchBook(
                book: book,
                sources: book.sourceLabels.isNotEmpty
                    ? book.sourceLabels
                    : [book.originName ?? '未知來源'],
              ),
              isInBookshelf: p.isInBookshelf(book),
            ),
          ],
        );
      },
    );
  }
}

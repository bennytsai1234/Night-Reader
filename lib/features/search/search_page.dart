import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show BoxHitTestResult, PipelineOwner, RenderProxyBox, RenderSliver;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:provider/provider.dart';
import 'package:night_reader/shared/navigation/transition_settled.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/app_bottom_sheet.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';

import 'search_model.dart';
import 'search_provider.dart';
import 'models/search_scope.dart';

import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/explore/widgets/explore_book_item.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';

import 'widgets/search_app_bar.dart';
import 'widgets/search_history_view.dart';
import 'widgets/search_result_item.dart';
import 'widgets/search_scope_sheet.dart';
import 'widgets/search_suggestion_view.dart';

/// SearchPage - 搜尋頁面
/// (對標 Legado SearchActivity)
class SearchPage extends StatefulWidget {
  final String? initialQuery;
  final BookSource? initialSource;

  const SearchPage({super.key, this.initialQuery, this.initialSource});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  /// 進場動畫播完時完成；書架、分組與搜尋紀錄等它才讀（ADR 0018）。
  Future<void>? _entrance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entrance ??= TransitionSettled.entered(context);
  }

  @override
  Widget build(BuildContext context) {
    final initialSource = widget.initialSource;
    return ChangeNotifierProvider(
      create: (_) => SearchProvider(
        entrance: _entrance!,
        initialScope: initialSource != null
            ? SearchScope.fromSource(initialSource)
            : null,
      ),
      child: SearchView(
        initialQuery: widget.initialQuery,
        initialSource: initialSource,
      ),
    );
  }
}

/// 搜尋頁的畫面；[SearchProvider] 由上層提供（[SearchPage]）。
class SearchView extends StatefulWidget {
  final String? initialQuery;
  final BookSource? initialSource;

  const SearchView({super.key, this.initialQuery, this.initialSource});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  /// Scaffold 內容區的系統內距（含玻璃頁首）。
  EdgeInsets _bodyPadding = EdgeInsets.zero;

  /// 這一輪搜尋已經出現過的結果；新一輪搜尋開始時清空。
  final Set<String> _knownResultKeys = {};

  /// 這一幀才串流進來的結果。只有這一幀就畫出來的列播淡入，落在畫面外、
  /// 之後才捲進來的列不播；幀結束時清空。
  final Set<String> _arrivingResultKeys = {};

  /// 頁面第一次建出來時已經在的結果（例如回到頁面）直接到位，不播淡入。
  bool _arrivalsPrimed = false;

  /// 結果會隨書源回傳重新排序、更換代表書；以合併卡的身分辨認同一本書。
  static String _resultKey(SearchBook book) => searchResultIdentity(book);

  /// 這一次建出的、之前不在畫面上的列要不要淡入。順序還會重排時（使用者
  /// 沒捲過），新建的列只會是重排從畫面外換進來的書：它沒有舊位置可以滑過來，
  /// 改成淡入，不在一幀內冒出來。順序固定後新建的列是捲進來的，不播。
  bool _fadeUnseenRows = false;

  /// 畫面上的結果列；結果有變時先記下位置，重排後各自從舊位置滑過去。
  final _ResultMoves _moves = _ResultMoves();

  void _trackArrivals(SearchProvider provider) {
    // 新一輪搜尋開始時會先清空結果。不看「是否搜尋中」：最後一批結果可能和
    // 搜尋完成在同一幀到，那一批也要淡入。
    if (provider.results.isEmpty) _knownResultKeys.clear();
    final animate = _arrivalsPrimed;
    _arrivalsPrimed = true;
    _fadeUnseenRows = animate && !provider.resultOrderHeld;
    _moves.rememberPositions();
    var arrived = false;
    for (final book in provider.results) {
      final key = _resultKey(book);
      if (_knownResultKeys.add(key) && animate) {
        _arrivingResultKeys.add(key);
        arrived = true;
      }
    }
    if (arrived) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _arrivingResultKeys.clear(),
      );
    }
  }

  bool get _opensBlank =>
      widget.initialQuery == null && widget.initialSource == null;

  @override
  void initState() {
    super.initState();
    if (_opensBlank) return;
    _controller.text = widget.initialQuery ?? '';
    unawaited(_searchWhenReady());
  }

  /// 帶著關鍵字或書源進來時，進場動畫播完、搜尋範圍讀好才開始搜尋：搜尋
  /// 要解析書源，不和換頁疊在一起（ADR 0018）。
  Future<void> _searchWhenReady() async {
    final provider = context.read<SearchProvider>();
    await provider.ready;
    if (!mounted) return;
    if (widget.initialSource != null) {
      unawaited(
        provider.searchInSource(widget.initialSource!, _controller.text),
      );
    } else if (_controller.text.isNotEmpty) {
      unawaited(provider.search(_controller.text));
    }
  }

  /// 頁面被不透明的整頁蓋住後，Overlay 會關掉這一頁的 TickerMode；跳出
  /// 選單、對話框與底部面板時不會。用它決定搜尋要不要暫停。
  ValueListenable<TickerModeData>? _tickerMode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerMode = TickerMode.getValuesNotifier(context);
    if (tickerMode == _tickerMode) return;
    _tickerMode?.removeListener(_onTickerModeChanged);
    _tickerMode = tickerMode..addListener(_onTickerModeChanged);
    _onTickerModeChanged();
  }

  void _onTickerModeChanged() {
    final provider = context.read<SearchProvider>();
    if (_tickerMode!.value.enabled) {
      provider.resumeSearch();
    } else {
      provider.pauseSearch();
    }
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_onTickerModeChanged);
    _controller.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    if (value.isNotEmpty) {
      FocusScope.of(context, createDependency: false).unfocus();
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
        _trackArrivals(provider);
        final showResults =
            !(provider.results.isEmpty && !provider.isSearching);
        return Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: AppChrome.of(context).groupedBackground,
          appBar: SearchAppBar(
            controller: _controller,
            focusNode: _inputFocus,
            provider: provider,
            onSearch: _onSearch,
            onScopePressed: _openScopeSheet,
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
                  // 蓋在結果上面而不是換掉它，打完字取消時結果和捲動位置還在。
                  Positioned.fill(child: _buildSuggestions(provider)),
                  Positioned(
                    // 進度條貼在玻璃頁首實色區的下緣。
                    top: padding.top - AppGlass.headerFadeHeight,
                    left: 0,
                    right: 0,
                    // 搜尋結束時停在最後的進度淡出，不在一幀內消失。
                    child: _FadeSwap(
                      child: provider.isSearching
                          ? ListenableBuilder(
                              key: const ValueKey('progress'),
                              listenable: provider.progressUpdates,
                              builder: (context, _) => LinearProgressIndicator(
                                value: provider.progress,
                                minHeight: 2,
                                backgroundColor: Colors.transparent,
                              ),
                            )
                          : const SizedBox(width: double.infinity, height: 2),
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

  /// 輸入框有焦點、正在打一個還沒搜過的詞時，列出符合的搜尋紀錄與書架書名。
  Widget _buildSuggestions(SearchProvider provider) => ListenableBuilder(
    listenable: Listenable.merge([_controller, _inputFocus]),
    builder: (context, _) {
      final input = _controller.text.trim();
      final suggestions =
          _inputFocus.hasFocus &&
              input.isNotEmpty &&
              input != provider.lastSearchKey
          ? provider.suggestionsFor(input)
          : const <SearchSuggestion>[];
      if (suggestions.isEmpty) return const SizedBox.shrink();
      return ColoredBox(
        color: AppChrome.of(context).groupedBackground,
        child: SearchSuggestionView(
          suggestions: suggestions,
          onSelected: (word) {
            _controller.text = word;
            _onSearch(word);
          },
        ),
      );
    },
  );

  /// 清單頂端的狀態列；跟著結果或歷史一起捲動。
  List<Widget> _buildPanels(SearchProvider provider) {
    return [
      if (provider.precisionSearch || !provider.searchScope.isAll)
        _buildFilterStatusPanel(provider),
      if (provider.isSearching || provider.hasUnfilteredResults)
        _buildStatusSlot(context, provider)
      else if (provider.failedSources > 0)
        _buildFailedSourcesPanel(context, provider),
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
        text: '${p.failedSources} 個書源搜尋失敗（共 ${p.searchedSourceCount} 個）',
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

  /// 搜尋中的進度與結束後的結果工具列輪流佔同一格、高度相同，搜尋結束時
  /// 下面的結果不會被推動。
  Widget _buildStatusSlot(BuildContext context, SearchProvider p) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppGrouped.margin,
      AppSpacing.sm,
      AppGrouped.margin,
      AppSpacing.xs,
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: GlassCapsule.height),
      // 搜尋結束時進度字樣與工具列在同一格交叉淡換；工具列的膠囊都是
      // blur: false，可以跟著淡。
      child: _FadeSwap(
        alignment: AlignmentDirectional.centerStart,
        child: p.isSearching
            ? KeyedSubtree(
                key: const ValueKey('progress'),
                child: _buildSearchProgress(p),
              )
            : KeyedSubtree(
                key: const ValueKey('toolbar'),
                child: _buildResultToolbar(context, p),
              ),
      ),
    ),
  );

  /// 剩下的書源不超過這個數時，改列出還在等哪幾個並可略過；三個名稱
  /// 大致排得進一行。
  static const _namedWaitingLimit = 3;

  Widget _buildSearchProgress(SearchProvider p) => ListenableBuilder(
    listenable: p.progressUpdates,
    builder: (context, _) => _buildSearchProgressContent(p),
  );

  Widget _buildSearchProgressContent(SearchProvider p) {
    final remaining = p.totalSources - p.completedSources;
    final waiting = p.waitingSources;
    final namesWaiting =
        p.totalSources > 0 &&
        remaining <= _namedWaitingLimit &&
        waiting.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(left: AppGrouped.rowPadding),
      child: Row(
        children: [
          Expanded(
            child: Text(
              namesWaiting
                  ? '還在等：${waiting.join('、')}'
                  : p.totalSources > 0
                  ? '正在搜尋 ${p.completedSources}/${p.totalSources}'
                  : '正在搜尋',
              style: AppTextStyles.labelXs.copyWith(
                height: 1.3,
                color: AppChrome.of(context).sectionText,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (namesWaiting)
            PlainTextAction(label: '略過', small: true, onPressed: p.stopSearch),
        ],
      ),
    );
  }

  Widget _buildFilterStatusPanel(SearchProvider p) => _noticeBar(
    color: context.warning,
    icon: Icons.filter_alt,
    text:
        '已開啟：${[if (p.precisionSearch) '精準搜尋', if (!p.searchScope.isAll) '範圍（${p.searchScope.display}）'].join('、')}',
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
    return Align(
      alignment: AlignmentDirectional.centerStart,
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
            if (p.failedSources > 0) ...[
              const SizedBox(width: AppSpacing.sm),
              GlassCapsule(
                label: '${p.failedSources} 個書源失敗',
                icon: Icons.warning_amber_rounded,
                foregroundColor: Theme.of(context).colorScheme.error,
                blur: false,
                onTap: () => _showFailureSheet(context),
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
      builder: (sheetContext) => ListenableBuilder(
        listenable: Listenable.merge([
          searchProvider,
          searchProvider.progressUpdates,
        ]),
        builder: (context, _) {
          final provider = searchProvider;
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
    );
  }

  void _showResultFilterSheet(BuildContext context) {
    final provider = context.read<SearchProvider>();

    AppBottomSheet.showCustom<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // 輸入框控制器由面板擁有，退場動畫結束後才釋放。
      builder: (sheetContext) => TextControllersScope(
        initialTexts: [provider.authorFilter],
        // 面板在另一條路由上，拿不到頁面的 provider；用會跟著通知重建的
        // ChangeNotifierProvider.value 接過來，不是 Provider.value。
        builder: (_, fields) => ChangeNotifierProvider.value(
          value: provider,
          child: Consumer<SearchProvider>(
            builder: (context, p, _) {
              final [authorController] = fields;
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
                              p.clearResultFilters();
                            },
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xl,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 「只看有封面」「分類包含」拿掉了：封面
                                // 是書源給不給的事，分類字樣各書源寫法不
                                // 一（ADR 0030）。
                                GroupedSection(
                                  topGap: AppSpacing.sm,
                                  children: [
                                    GroupedSwitchRow(
                                      title: '只看已加入書架',
                                      value: p.onlyInBookshelf,
                                      onChanged: p.setOnlyInBookshelf,
                                    ),
                                    GroupedTextFieldRow(
                                      label: '作者包含',
                                      controller: authorController,
                                      hintText: '不限',
                                      onChanged: p.setAuthorFilter,
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
                                                  p.sourceFilters.contains(
                                                    source,
                                                  )
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
      ),
    );
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
    // 重排時同一本書的列（連同它的狀態與畫面上的位置）跟著書走，才能從
    // 原本的位置滑到新位置。
    final indexByKey = <String, int>{
      for (var i = 0; i < results.length; i++) _resultKey(results[i]): i,
    };
    return NotificationListener<ScrollUpdateNotification>(
      // 使用者一開始捲，結果順序就固定，之後找到的書接在尾端。
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.dragDetails != null &&
            notification.metrics.pixels > 0) {
          p.holdResultOrder();
        }
        return false;
      },
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(
          top: padding.top,
          bottom: padding.bottom + AppSpacing.xl,
        ),
        itemCount: panels.length + results.length,
        findChildIndexCallback: (key) {
          final index = key is ValueKey<String> ? indexByKey[key.value] : null;
          return index == null ? null : panels.length + index;
        },
        itemBuilder: (ctx, i) {
          if (i < panels.length) return panels[i];
          final index = i - panels.length;
          final book = results[index];
          final key = _resultKey(book);
          // 相關度排序時，每換一段就在那一段第一本書上方標出段名；順序固定
          // 後接到尾端的書若是前面的段，尾端會再出現一次同名的段。
          final tier = p.relevanceTierOf(book);
          final startsTier =
              tier != null &&
              (index == 0 || tier != p.relevanceTierOf(results[index - 1]));
          return _ResultEntrance(
            // 以書名＋作者當 key，「展開來源」等列內狀態才會跟著那本書，不會
            // 留在原本的位置。
            key: ValueKey(key),
            animate: _arrivingResultKeys.contains(key) || _fadeUnseenRows,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (startsTier)
                  _RelevanceTierHeader(tier: tier, first: index == 0)
                else if (index > 0)
                  const InsetSeparator(indent: ExploreBookItem.textIndent),
                // 只有書卡滑動；段名與分隔線屬於清單的位置，照新版面。
                _ResultMove(
                  key: const ValueKey('book'),
                  moves: _moves,
                  child: SearchResultItem(
                    result: AggregatedSearchBook(
                      book: book,
                      sources: book.sourceLabels.isNotEmpty
                          ? book.sourceLabels
                          : [book.originName ?? '未知來源'],
                    ),
                    coverUrl: p.coverOf(book),
                    onOpen: () => p.rememberOpenedCard(book),
                    isInBookshelf: p.isInBookshelf(book),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 同一格裡兩種內容交叉淡換（[AppMotion.fade]）；系統關閉動畫時直接換。
/// 兩者疊在一起、靠 [alignment] 對齊，淡換期間版面取較大的那個。
class _FadeSwap extends StatelessWidget {
  const _FadeSwap({
    this.alignment = AlignmentDirectional.center,
    required this.child,
  });

  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.fade,
      switchInCurve: AppMotion.fadeCurve,
      switchOutCurve: AppMotion.fadeCurve,
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      child: child,
    );
  }
}

/// 搜尋結果重新排序、上面多出或少掉一列時，這一本的書卡從原本的位置滑到新位置，
/// 不在一幀內跳過去。時長與曲線同新結果的淡入（[AppMotion.fade]），插進一本
/// 書時下面的列讓位和它淡入同時完成。
///
/// 結果有變、清單重建之前，頁面先叫 [_ResultMoves.rememberPositions] 記下
/// 每一列在清單裡的位置（這時版面還是上一幀的；清單重建時搬動過的列會
/// 失去位置紀錄，所以不能等列自己重建才量），畫出來時每一列再量一次；位置
/// 不同就從舊位置開始，平移回原位。量的是在整條清單裡的位置，和目前捲到
/// 哪裡無關。只是畫的位置平移，不改版面。
class _ResultMove extends StatefulWidget {
  const _ResultMove({super.key, required this.moves, required this.child});

  final _ResultMoves moves;
  final Widget child;

  @override
  State<_ResultMove> createState() => _ResultMoveState();
}

class _ResultMoveState extends State<_ResultMove>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
    value: 1,
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.fadeCurve,
  );

  void _restart() {
    if (mounted) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ResultMoveBox(
    moves: widget.moves,
    progress: _progress,
    enabled: !MediaQuery.disableAnimationsOf(context),
    onMoved: _restart,
    child: widget.child,
  );
}

/// 畫面上所有搜尋結果列的登記處。
class _ResultMoves {
  final Set<_RenderResultMove> _rows = {};

  /// 結果有變、清單重建之前呼叫。
  void rememberPositions() {
    for (final row in _rows) {
      row.rememberPosition();
    }
  }
}

class _ResultMoveBox extends SingleChildRenderObjectWidget {
  const _ResultMoveBox({
    required this.moves,
    required this.progress,
    required this.enabled,
    required this.onMoved,
    required super.child,
  });

  final _ResultMoves moves;
  final Animation<double> progress;
  final bool enabled;
  final VoidCallback onMoved;

  @override
  _RenderResultMove createRenderObject(BuildContext context) =>
      _RenderResultMove(
        moves: moves,
        progress: progress,
        enabled: enabled,
        onMoved: onMoved,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderResultMove renderObject,
  ) {
    renderObject
      ..enabled = enabled
      ..onMoved = onMoved;
  }
}

class _RenderResultMove extends RenderProxyBox {
  _RenderResultMove({
    required this.moves,
    required this.progress,
    required this.enabled,
    required this.onMoved,
  });

  final _ResultMoves moves;

  /// 平移的進度；同一列一直是同一個（State 擁有）。
  final Animation<double> progress;

  bool enabled;
  VoidCallback onMoved;

  /// 平移從這個距離開始，隨進度收到 0。
  double _from = 0;

  /// 剛換了起點、動畫下一幀才從頭播：這一幀照起點畫。
  bool _restartPending = false;

  /// 清單重建前記下的位置（上一幀的版面）；畫出來時拿來比。
  double? _before;

  double get _shift => _restartPending ? _from : _from * (1 - progress.value);

  /// 這一列頂端在清單裡的位置：清單項目的排版位置加上這一列在項目裡的
  /// 位置。項目剛被搬動、還沒重新排版時量不到，回傳 null。
  double? _listOffset() {
    if (!attached || !hasSize) return null;
    RenderObject item = this;
    while (item.parent is! RenderSliver) {
      final parent = item.parent;
      if (parent == null) return null;
      item = parent;
    }
    if (item is! RenderBox) return null;
    final itemOffset = (item.parent! as RenderSliver).childScrollOffset(item);
    if (itemOffset == null) return null;
    return itemOffset + localToGlobal(Offset.zero, ancestor: item).dy;
  }

  void rememberPosition() {
    if (!attached || !enabled) return;
    _before = _listOffset();
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    progress.addListener(markNeedsPaint);
    moves._rows.add(this);
  }

  @override
  void detach() {
    moves._rows.remove(this);
    progress.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final before = _before;
    _before = null;
    if (before != null) {
      final now = _listOffset();
      if (now != null && (before - now).abs() > 0.5) {
        // 動畫途中又移動：從目前畫的位置接著滑，不跳回去。
        _from = _shift + before - now;
        _restartPending = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _restartPending = false;
          onMoved();
        });
      }
    }
    super.paint(context, offset.translate(0, _paintShift));
  }

  double get _paintShift => enabled ? _shift : 0.0;

  // 點擊與讀屏的位置跟著畫的位置走，滑動途中點到的就是看到的那一列。
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, _paintShift, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintOffset(
      offset: Offset(0, _paintShift),
      position: position,
      hitTest: (result, position) =>
          super.hitTestChildren(result, position: position),
    );
  }
}

/// 相關度分段的段名，接在該段第一本書上方。
class _RelevanceTierHeader extends StatelessWidget {
  const _RelevanceTierHeader({required this.tier, required this.first});

  final int tier;
  final bool first;

  static const _labels = ['完全相符', '部分相符', '其他結果'];

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      AppGrouped.margin,
      first ? AppSpacing.sm : AppSpacing.xl,
      AppGrouped.margin,
      0,
    ),
    child: GroupedSectionHeader(_labels[tier]),
  );
}

/// 串流進來的搜尋結果第一次出現時短暫淡入；結果是內容，只淡不移（ADR 0022）。
///
/// 要不要播在建立時就決定：同一列之後重建、或捲出畫面回收後再出現，都不再
/// 播。播完後透明度為 1，不再多出圖層。
class _ResultEntrance extends StatefulWidget {
  const _ResultEntrance({
    super.key,
    required this.animate,
    required this.child,
  });

  final bool animate;
  final Widget child;

  @override
  State<_ResultEntrance> createState() => _ResultEntranceState();
}

class _ResultEntranceState extends State<_ResultEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    if (!widget.animate) return;
    final controller = AnimationController(
      vsync: this,
      duration: AppMotion.fade,
    );
    _controller = controller;
    _opacity = CurvedAnimation(parent: controller, curve: AppMotion.fadeCurve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = _controller;
    if (controller == null ||
        controller.isAnimating ||
        controller.isCompleted) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = 1;
    } else {
      controller.forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) return widget.child;
    return FadeTransition(opacity: _opacity, child: widget.child);
  }
}

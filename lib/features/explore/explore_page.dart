import 'package:night_reader/core/exception/user_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:provider/provider.dart';

import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/shared/theme/app_chrome.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/app_dialogs.dart';
import 'package:night_reader/shared/widgets/app_state_view.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/features/source_manager/source_editor_page.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';

import 'explore_provider.dart';
import 'explore_show_page.dart';

import 'package:night_reader/shared/widgets/group_filter_bar.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import 'widgets/explore_skeletons.dart';
import 'widgets/legado_explore_kind_flow.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ExplorePageContent();
  }
}

class _ExplorePageContent extends StatefulWidget {
  const _ExplorePageContent();

  @override
  State<_ExplorePageContent> createState() => _ExplorePageContentState();
}

enum _SourceAction { edit, top, search, refresh, delete }

class _ExplorePageContentState extends State<_ExplorePageContent>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();

  /// 分組篩選列出現的進度，1 是完整出現。第一幀照 provider 手上的分組
  /// （讀到書源前是上次的紀錄）直接到位；之後有無分組改變（紀錄不準、
  /// 分組刪光或新增）時，篩選列從頁首下緣長出或收回，清單連續讓位。
  late final AnimationController _filterBar = AnimationController(
    vsync: this,
    duration: AppMotion.menu,
  );
  late final Animation<double> _filterBarShown = CurvedAnimation(
    parent: _filterBar,
    curve: AppMotion.menuCurve,
  );
  bool? _filterBarTarget;

  void _syncFilterBar(BuildContext context, bool shown) {
    if (_filterBarTarget == shown) return;
    final first = _filterBarTarget == null;
    _filterBarTarget = shown;
    if (first || MediaQuery.disableAnimationsOf(context)) {
      _filterBar.value = shown ? 1 : 0;
    } else if (shown) {
      _filterBar.forward();
    } else {
      _filterBar.reverse();
    }
  }

  /// 沒有發現書源時用到：連一個書源都沒有時改成帶去匯入。
  late final Stream<bool> _hasSources = getIt.isRegistered<BookSourceDao>()
      ? getIt<BookSourceDao>().watchHasAny()
      : Stream<bool>.value(true);
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};
  final Map<String, GlobalKey> _kindsKeys = <String, GlobalKey>{};

  /// 直接展開下一個書源時，上方被收合的書源；它這一幀立即收合，不播動畫。
  String? _snapCollapseUrl;

  /// Scaffold 內容區的系統內距（含玻璃頁首與底部浮動分頁列）。
  EdgeInsets _bodyPadding = EdgeInsets.zero;

  @override
  void dispose() {
    _filterBar.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExploreProvider>();
    // 讀到書源前 provider 的分組是上次的紀錄，篩選列從第一幀就留好。
    _syncFilterBar(
      context,
      provider.sourceLoadError == null && provider.groups.isNotEmpty,
    );
    // 內距要從 Scaffold 內取得：延伸到頁首下方時 top 才包含頁首高度。
    final body = Builder(
      builder: (bodyContext) {
        _bodyPadding = MediaQuery.paddingOf(bodyContext);
        return SkeletonSwitcher(
          loading: provider.isLoadingSources,
          skeleton: ExploreSourceListSkeleton(padding: _listPadding),
          builder: (_) => _buildSourceList(provider),
        );
      },
    );

    // 篩選列長出、收回時頁首每一幀變高，Scaffold 要重新量；清單是同一個
    // [body]，只隨讓位的內距重排。
    return AnimatedBuilder(
      animation: _filterBarShown,
      builder: (context, _) => Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: AppChrome.of(context).groupedBackground,
        appBar: _buildHeader(provider),
        body: body,
      ),
    );
  }

  GlassNavHeader _buildHeader(ExploreProvider provider) {
    final shown = _filterBarShown.value;
    return GlassNavHeader(
      title: '發現',
      backgroundColor: AppChrome.of(context).groupedBackground,
      bottom: shown > 0
          ? ClipRect(
              // 完整出現時不裁，膠囊的陰影照常伸出去。
              clipBehavior: shown < 1 ? Clip.hardEdge : Clip.none,
              child: Align(
                alignment: Alignment.bottomCenter,
                heightFactor: shown,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppGrouped.margin,
                    0,
                    AppGrouped.margin,
                    AppSpacing.sm,
                  ),
                  child: GroupFilterBar<String?>(
                    all: GroupFilterOption<String?>(
                      null,
                      '全部',
                      count: provider.filterAllCount,
                    ),
                    groups: [
                      for (final group in provider.groups)
                        GroupFilterOption<String?>(
                          group,
                          group,
                          count: provider.groupCounts[group],
                        ),
                    ],
                    selected: provider.selectedGroup,
                    // provider 對同一分組是切換語意；篩選列只在選到不同分組時
                    // 回報，因此不會誤觸取消。
                    onChanged: provider.setGroupFilter,
                  ),
                ),
              ),
            )
          : null,
      bottomHeight: (GroupFilterBar.height + AppSpacing.sm) * shown,
    );
  }

  /// 狀態頁讓出頁首與底部浮動分頁列。
  Widget _padState(Widget child) {
    final padding = _bodyPadding;
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: child,
    );
  }

  /// 書源清單讓出頁首與底部浮動分頁列。
  EdgeInsets get _listPadding => EdgeInsets.only(
    top: _bodyPadding.top + AppSpacing.sm,
    bottom: _bodyPadding.bottom + AppSpacing.xl,
  );

  Widget _buildSourceList(ExploreProvider provider) {
    if (provider.sourceLoadError != null) {
      return _padState(
        AppStateView(
          icon: Icons.error_outline,
          title: '發現書源載入失敗',
          description: provider.sourceLoadError!,
          tone: AppStateTone.error,
          primaryAction: AppStateAction(
            label: '重試',
            icon: Icons.refresh,
            onPressed: provider.refresh,
          ),
        ),
      );
    }

    if (provider.isEmpty &&
        provider.searchQuery.isEmpty &&
        provider.selectedGroup == null) {
      return _padState(
        StreamBuilder<bool>(
          stream: _hasSources,
          // 還不知道有沒有書源時兩種空頁都不畫，知道了才淡入對的那一種；
          // 之後匯入或刪光書源也是交叉淡換。
          builder: (context, snapshot) => _FadeSwitch(
            child: switch (snapshot.data) {
              null => const SizedBox.expand(key: ValueKey('unknown')),
              true => KeyedSubtree(
                key: const ValueKey('noExplore'),
                child: _buildNoExploreSources(provider),
              ),
              false => AppStateView(
                key: const ValueKey('noSources'),
                icon: Icons.travel_explore_outlined,
                title: '還沒有書源',
                description: '匯入書源後，這裡會列出可以瀏覽分類的書源。',
                primaryAction: AppStateAction(
                  label: '匯入書源',
                  icon: Icons.download_rounded,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SourceManagerPage(),
                    ),
                  ),
                ),
              ),
            },
          ),
        ),
      );
    }
    return _buildFilteredSourceList(provider);
  }

  /// 有書源、但沒有一個支援發現。
  Widget _buildNoExploreSources(ExploreProvider provider) {
    return AppStateView(
      icon: Icons.travel_explore_outlined,
      title: '目前沒有可用的發現書源',
      description: '到書源管理啟用支援發現功能的書源。',
      primaryAction: AppStateAction(
        label: '管理書源',
        icon: Icons.source_outlined,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SourceManagerPage()),
        ),
      ),
      secondaryAction: AppStateAction(
        label: '重新整理',
        icon: Icons.refresh,
        onPressed: provider.refresh,
      ),
    );
  }

  Widget _buildFilteredSourceList(ExploreProvider provider) {
    if (provider.isEmpty) {
      return _padState(
        AppStateView(
          icon: Icons.search_off,
          title: '找不到符合條件的書源',
          description: '清除搜尋或分組條件後再試一次。',
          primaryAction: AppStateAction(
            label: '清除條件',
            icon: Icons.clear,
            onPressed: () {
              if (provider.selectedGroup != null) {
                provider.setGroupFilter(null);
              } else {
                provider.setSearchQuery('');
              }
            },
          ),
          secondaryAction: AppStateAction(
            label: '重新整理',
            icon: Icons.refresh,
            onPressed: provider.refresh,
          ),
        ),
      );
    }

    final count = provider.sources.length;
    return ListView.builder(
      controller: _scrollController,
      padding: _listPadding,
      itemCount: count,
      itemBuilder: (context, index) {
        final source = provider.sources[index];
        final isExpanded = provider.expandedIndex == index;
        return GroupedSliceItem(
          index: index,
          count: count,
          child: _buildSourceItem(provider, source, index, isExpanded),
        );
      },
    );
  }

  Widget _buildSourceItem(
    ExploreProvider provider,
    BookSource source,
    int index,
    bool isExpanded,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Builder(
          builder: (rowContext) => Semantics(
            // 讀屏才知道分類已展開或收合。
            expanded: isExpanded,
            child: InkWell(
              key: _itemKeys.putIfAbsent(source.bookSourceUrl, GlobalKey.new),
              onTap: () {
                if (!isExpanded) _collapseExpandedAbove(provider, index);
                provider.toggleExpand(index);
                if (!isExpanded) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _ensureSourceVisible(source.bookSourceUrl);
                  });
                }
              },
              onLongPress: () => _showSourceMenu(rowContext, provider, source),
              child: _SourceRow(
                name: source.bookSourceName,
                expanded: isExpanded,
                loading: isExpanded && provider.isLoadingKinds,
              ),
            ),
          ),
        ),
        KeyedSubtree(
          key: _kindsKeys.putIfAbsent(source.bookSourceUrl, GlobalKey.new),
          child: _KindsReveal(
            open: isExpanded && !provider.isLoadingKinds,
            snap: source.bookSourceUrl == _snapCollapseUrl,
            child: isExpanded && !provider.isLoadingKinds
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppGrouped.rowPadding,
                      0,
                      AppGrouped.rowPadding,
                      AppSpacing.lg,
                    ),
                    child: provider.expandedKinds.isEmpty
                        ? Text(
                            '暫無分類',
                            style: AppTextStyles.bodySm.copyWith(
                              color: AppChrome.of(context).sectionText,
                            ),
                          )
                        : _buildKindTags(provider, source),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildKindTags(ExploreProvider provider, BookSource source) {
    final kinds = provider.expandedKinds;
    final chrome = AppChrome.of(context);
    final error = Theme.of(context).colorScheme.error;

    return LegadoExploreKindFlow(
      styles: kinds.map((kind) => kind.effectiveStyle).toList(),
      children: kinds.map((kind) {
        final isError = kind.title.startsWith('ERROR:');
        final hasUrl = kind.url != null && kind.url!.isNotEmpty;
        return GlassCapsule(
          label: isError ? '分類載入失敗' : kind.title,
          maxLines: 2,
          blur: false,
          tint: chrome.groupedBackground,
          foregroundColor: isError ? error : null,
          onTap: isError
              ? () => _showKindError(context, kind)
              : hasUrl
              ? () => _navigateToExploreShow(source, kind)
              : null,
        );
      }).toList(),
    );
  }

  void _showKindError(BuildContext context, ExploreKind kind) {
    showAppAlert<void>(
      context: context,
      title: '分類載入錯誤',
      content: SelectableText(
        kind.url ?? kind.title,
        style: AppTextStyles.bodySm,
      ),
      actions: const [
        AppAlertAction(label: '關閉', value: null, isDefault: true),
      ],
    );
  }

  void _navigateToExploreShow(BookSource source, ExploreKind kind) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExploreShowPage(
          sourceUrl: source.bookSourceUrl,
          exploreUrl: kind.url!,
          exploreName: kind.title,
        ),
      ),
    );
  }

  Future<void> _showSourceMenu(
    BuildContext rowContext,
    ExploreProvider provider,
    BookSource source,
  ) async {
    final action = await showContextPreviewMenu<_SourceAction>(
      context: rowContext,
      sourceRect: globalRectOf(rowContext),
      previewRadius: AppGrouped.cardRadius,
      preview: Material(
        color: AppChrome.of(rowContext).groupedSurface,
        child: _SourceRow(
          name: source.bookSourceName,
          expanded: false,
          loading: false,
        ),
      ),
      entries: const [
        GlassMenuItem(
          value: _SourceAction.edit,
          label: '編輯',
          icon: Icons.edit_outlined,
        ),
        GlassMenuItem(
          value: _SourceAction.top,
          label: '置頂',
          icon: Icons.vertical_align_top_rounded,
        ),
        GlassMenuItem(
          value: _SourceAction.search,
          label: '搜尋',
          icon: Icons.search_rounded,
        ),
        GlassMenuItem(
          value: _SourceAction.refresh,
          label: '重新整理分類',
          icon: Icons.refresh_rounded,
        ),
        GlassMenuDivider(),
        GlassMenuItem(
          value: _SourceAction.delete,
          label: '刪除',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ],
    );

    if (!mounted || action == null) return;

    try {
      switch (action) {
        case _SourceAction.edit:
          final full = await provider.getFullSource(source.bookSourceUrl);
          if (full != null && mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SourceEditorPage(source: full)),
            );
          }
          return;
        case _SourceAction.top:
          await provider.topSource(source);
          return;
        case _SourceAction.search:
          final full = await provider.getFullSource(source.bookSourceUrl);
          if (full == null || !mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SearchPage(initialSource: full)),
          );
          return;
        case _SourceAction.refresh:
          await provider.refreshKindsCache(source);
          return;
        case _SourceAction.delete:
          await _confirmDelete(provider, source);
          return;
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureMessage('書源操作', error))));
    }
  }

  Future<void> _confirmDelete(
    ExploreProvider provider,
    BookSource source,
  ) async {
    final confirmed = await showAppConfirm(
      context: context,
      title: '刪除書源',
      message: '確定刪除「${source.bookSourceName}」嗎？',
      confirmLabel: '刪除',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await provider.deleteSource(source);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureMessage('刪除書源', error))));
    }
  }

  /// 不先收起就展開 [index] 時，若展開中的書源在它上方，該書源的分類區
  /// 會收掉、把下面整段往上拉。這裡讓它立即收合並同步扣掉捲動位置，
  /// 被點的書源留在原處；之後的 [_ensureSourceVisible] 才量得到正確位置。
  void _collapseExpandedAbove(ExploreProvider provider, int index) {
    final previous = provider.expandedIndex;
    if (previous < 0 || previous >= index) return;
    final previousUrl = provider.sources[previous].bookSourceUrl;
    final collapsing =
        _kindsKeys[previousUrl]?.currentContext?.size?.height ?? 0;
    if (collapsing <= 0 || !_scrollController.hasClients) return;

    _snapCollapseUrl = previousUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapCollapseUrl = null;
    });
    final position = _scrollController.position;
    _scrollController.jumpTo(
      (position.pixels - collapsing).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  Future<void> _ensureSourceVisible(String sourceUrl) async {
    final itemContext = _itemKeys[sourceUrl]?.currentContext;
    if (itemContext == null || !_scrollController.hasClients) return;
    final target = itemContext.findRenderObject();
    if (target == null) return;
    final viewport = RenderAbstractViewport.maybeOf(target);
    if (viewport == null) return;
    // 展開的書源捲到玻璃頁首與分組篩選列下方，而不是被頁首蓋住。
    final headerExtent = _bodyPadding.top;
    final position = _scrollController.position;
    final offset = (viewport.getOffsetToReveal(target, 0).offset - headerExtent)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    await _scrollController.animateTo(
      offset,
      duration: AppMotion.fade,
      curve: Curves.easeOutCubic,
    );
  }
}

/// 書源列：名稱、載入中指示與展開箭頭。
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.name,
    required this.expanded,
    required this.loading,
  });

  final String name;
  final bool expanded;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppGrouped.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppGrouped.rowPadding,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyBase.copyWith(
                  height: 1.3,
                  color: scheme.onSurface,
                  fontWeight: expanded ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (loading) ...[
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                  semanticsLabel: '正在載入分類',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: AppMotion.menu,
              curve: AppMotion.menuCurve,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: chrome.sectionText.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空頁之間的交叉淡換（[AppMotion.fade]）；系統關閉動畫時直接換。
class _FadeSwitch extends StatelessWidget {
  const _FadeSwitch({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.fade,
      switchInCurve: AppMotion.fadeCurve,
      switchOutCurve: AppMotion.fadeCurve,
      child: child,
    );
  }
}

/// 書源的分類區展開、收合：區塊高度從 0 長到內容高度（或反過來），分類
/// 膠囊跟著同一段進度淡入淡出，並被區塊邊緣裁住。收合時沿用展開時最後
/// 畫出的分類，provider 已經換去載入別的書源也一樣，最後一幀才拿掉；原本
/// 收合的第一幀分類就消失，留一塊空白再縮小。
class _KindsReveal extends StatefulWidget {
  const _KindsReveal({
    required this.open,
    required this.snap,
    required this.child,
  });

  final bool open;

  /// 這一次切換直接到位、不播動畫（見 `_collapseExpandedAbove`）。
  final bool snap;

  /// 展開時的內容；收合時可以是 null，沿用上一次的。
  final Widget? child;

  @override
  State<_KindsReveal> createState() => _KindsRevealState();
}

class _KindsRevealState extends State<_KindsReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.menu,
    value: widget.open ? 1 : 0,
  )..addStatusListener((_) => setState(() {}));
  // 收合也是先快後慢，和展開同一條曲線。
  late final Animation<double> _shown = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.menuCurve,
    reverseCurve: AppMotion.menuCurve.flipped,
  );
  late Widget? _last = widget.open ? widget.child : null;

  @override
  void didUpdateWidget(_KindsReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open) _last = widget.child;
    if (widget.open == oldWidget.open) return;
    if (widget.snap || MediaQuery.disableAnimationsOf(context)) {
      _controller.value = widget.open ? 1 : 0;
    } else if (widget.open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = _last;
    if (_controller.isDismissed || child == null) {
      return const SizedBox(width: double.infinity);
    }
    return SizeTransition(
      sizeFactor: _shown,
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: _shown, child: child),
    );
  }
}

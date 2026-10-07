import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:provider/provider.dart';

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
import 'package:night_reader/shared/widgets/folder_tabs.dart';
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

class _ExplorePageContentState extends State<_ExplorePageContent> {
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};

  /// Scaffold 內容區的系統內距（含玻璃頁首與底部浮動分頁列）。
  EdgeInsets _bodyPadding = EdgeInsets.zero;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExploreProvider>();
    final showTabs =
        !provider.isLoadingSources &&
        provider.sourceLoadError == null &&
        provider.groups.isNotEmpty;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppChrome.of(context).groupedBackground,
      appBar: GlassNavHeader(
        title: '發現',
        backgroundColor: AppChrome.of(context).groupedBackground,
        bottom:
            showTabs
                ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppGrouped.margin,
                    0,
                    AppGrouped.margin,
                    AppSpacing.sm,
                  ),
                  child: FolderTabs<String?>(
                    tabs: [
                      const FolderTab<String?>(null, '全部'),
                      for (final group in provider.groups)
                        FolderTab<String?>(group, group),
                    ],
                    selected: provider.selectedGroup,
                    // 分組篩選以資料夾分頁切換；provider 對同一分組是切換語意，
                    // 分頁只在選到不同分頁時回報，因此不會誤觸取消。
                    onChanged: provider.setGroupFilter,
                  ),
                )
                : null,
        bottomHeight: showTabs ? FolderTabs.height + AppSpacing.sm : 0,
      ),
      // 內距要從 Scaffold 內取得：延伸到頁首下方時 top 才包含頁首高度。
      body: Builder(
        builder: (bodyContext) {
          _bodyPadding = MediaQuery.paddingOf(bodyContext);
          return _buildSourceList(provider);
        },
      ),
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

  Widget _buildSourceList(ExploreProvider provider) {
    if (provider.isLoadingSources) {
      return _padState(const Center(child: CircularProgressIndicator()));
    }

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
        AppStateView(
          icon: Icons.travel_explore_outlined,
          title: '目前沒有可用的發現書源',
          description: '到書源管理啟用支援發現功能的書源。',
          primaryAction: AppStateAction(
            label: '管理書源',
            icon: Icons.source_outlined,
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SourceManagerPage()),
                ),
          ),
          secondaryAction: AppStateAction(
            label: '重新整理',
            icon: Icons.refresh,
            onPressed: provider.refresh,
          ),
        ),
      );
    }

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

    final padding = _bodyPadding;
    final count = provider.sources.length;
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: padding.top + AppSpacing.sm,
        bottom: padding.bottom + AppSpacing.xl,
      ),
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
          builder:
              (rowContext) => InkWell(
                key: _itemKeys.putIfAbsent(source.bookSourceUrl, GlobalKey.new),
                onTap: () {
                  provider.toggleExpand(index);
                  if (!isExpanded) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _ensureSourceVisible(source.bookSourceUrl);
                    });
                  }
                },
                onLongPress:
                    () => _showSourceMenu(rowContext, provider, source),
                child: _SourceRow(
                  name: source.bookSourceName,
                  expanded: isExpanded,
                  loading: isExpanded && provider.isLoadingKinds,
                ),
              ),
        ),
        AnimatedSize(
          duration: AppMotion.menu,
          curve: AppMotion.menuCurve,
          alignment: Alignment.topCenter,
          child:
              isExpanded && !provider.isLoadingKinds
                  ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppGrouped.rowPadding,
                      0,
                      AppGrouped.rowPadding,
                      AppSpacing.lg,
                    ),
                    child:
                        provider.expandedKinds.isEmpty
                            ? Text(
                              '暫無分類',
                              style: AppTextStyles.bodySm.copyWith(
                                color: AppChrome.of(context).sectionText,
                              ),
                            )
                            : _buildKindTags(provider, source),
                  )
                  : const SizedBox(width: double.infinity),
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
      children:
          kinds.map((kind) {
            final isError = kind.title.startsWith('ERROR:');
            final hasUrl = kind.url != null && kind.url!.isNotEmpty;
            return GlassCapsule(
              label: isError ? '分類載入失敗' : kind.title,
              maxLines: 2,
              blur: false,
              tint: chrome.groupedBackground,
              foregroundColor: isError ? error : null,
              onTap:
                  isError
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
      actions: const [AppAlertAction(label: '關閉', value: null, isDefault: true)],
    );
  }

  void _navigateToExploreShow(BookSource source, ExploreKind kind) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ExploreShowPage(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('書源操作失敗：$error')));
    }
  }

  Future<void> _confirmDelete(ExploreProvider provider, BookSource source) async {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('刪除書源失敗：$error')));
    }
  }

  Future<void> _ensureSourceVisible(String sourceUrl) async {
    final itemContext = _itemKeys[sourceUrl]?.currentContext;
    if (itemContext == null || !_scrollController.hasClients) return;
    final target = itemContext.findRenderObject();
    if (target == null) return;
    final viewport = RenderAbstractViewport.maybeOf(target);
    if (viewport == null) return;
    // 展開的書源捲到玻璃頁首與資料夾分頁下方，而不是被頁首蓋住。
    final headerExtent = _bodyPadding.top;
    final position = _scrollController.position;
    final offset = (viewport.getOffsetToReveal(target, 0).offset -
            headerExtent)
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

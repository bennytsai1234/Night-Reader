import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:reader/core/models/book_source.dart';
import 'package:reader/shared/theme/app_tokens.dart';
import 'package:reader/core/models/source/explore_kind.dart';
import 'package:reader/features/search/search_page.dart';
import 'package:reader/features/source_manager/source_editor_page.dart';

import 'explore_provider.dart';
import 'explore_show_page.dart';
import 'widgets/legado_explore_kind_flow.dart';

const String _allGroupsMenuValue = '__all_groups__';

/// ExplorePage - 發現主頁面
/// (對標 Android ExploreFragment + ExploreAdapter)
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

class _ExplorePageContentState extends State<_ExplorePageContent> {
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExploreProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('發現'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchPage()),
                ),
          ),
          if (provider.groups.isNotEmpty)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.tune_rounded,
                color:
                    provider.selectedGroup == null
                        ? null
                        : theme.colorScheme.primary,
              ),
              tooltip: '按分組篩選',
              onSelected:
                  (value) => provider.setGroupFilter(
                    value == _allGroupsMenuValue ? null : value,
                  ),
              itemBuilder: (ctx) {
                final items = <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: _allGroupsMenuValue,
                    child: _buildCheckedMenuRow(
                      theme,
                      checked: provider.selectedGroup == null,
                      text: '全部',
                    ),
                  ),
                ];
                items.addAll(
                  provider.groups.map((group) {
                    return PopupMenuItem<String>(
                      value: group,
                      child: _buildCheckedMenuRow(
                        theme,
                        checked: provider.selectedGroup == group,
                        text: group,
                      ),
                    );
                  }),
                );
                return items;
              },
            ),
        ],
      ),
      body: _buildSourceList(provider, theme),
    );
  }

  Widget _buildCheckedMenuRow(
    ThemeData theme, {
    required bool checked,
    required String text,
  }) {
    return Row(
      children: [
        Icon(
          checked ? Icons.check : Icons.circle_outlined,
          size: 18,
          color: checked ? theme.colorScheme.primary : null,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(color: checked ? theme.colorScheme.primary : null),
        ),
      ],
    );
  }

  Widget _buildSourceList(ExploreProvider provider, ThemeData theme) {
    if (provider.isEmpty &&
        provider.searchQuery.isEmpty &&
        provider.selectedGroup == null) {
      return _buildEmptyState(
        theme: theme,
        icon: Icons.travel_explore_outlined,
        message: '目前無可用發現規則的書源',
        actions: [
          FilledButton.icon(
            onPressed: provider.refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('重新整理'),
          ),
        ],
      );
    }

    if (provider.isEmpty) {
      return _buildEmptyState(
        theme: theme,
        icon: Icons.search_off,
        message: '找不到符合條件的書源',
        actions: [
          TextButton.icon(
            onPressed: () {
              if (provider.selectedGroup != null) {
                provider.setGroupFilter(null);
              } else {
                provider.setSearchQuery('');
              }
            },
            icon: const Icon(Icons.clear),
            label: const Text('清除條件'),
          ),
          FilledButton.icon(
            onPressed: provider.refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('重新整理'),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, AppSpacing.lg),
      itemCount: provider.sources.length,
      itemBuilder: (context, index) {
        final source = provider.sources[index];
        final isExpanded = provider.expandedIndex == index;
        return _buildSourceItem(provider, source, index, isExpanded, theme);
      },
    );
  }

  Widget _buildEmptyState({
    required ThemeData theme,
    required IconData icon,
    required String message,
    required List<Widget> actions,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 52, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceItem(
    ExploreProvider provider,
    BookSource source,
    int index,
    bool isExpanded,
    ThemeData theme,
  ) {
    final titleBackground = theme.colorScheme.primaryContainer.withValues(
      alpha: 0.55,
    );
    final titleForeground = theme.colorScheme.onPrimaryContainer;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        index == provider.sources.length - 1 ? AppSpacing.md : 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPressStart:
                (details) => _showSourceMenu(
                  context,
                  provider,
                  source,
                  details.globalPosition,
                ),
            child: Material(
              color: titleBackground,
              borderRadius: AppRadius.cardMd,
              child: InkWell(
                key: _itemKeys.putIfAbsent(source.bookSourceUrl, GlobalKey.new),
                borderRadius: AppRadius.cardMd,
                onTap: () {
                  provider.toggleExpand(index);
                  if (!isExpanded) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _ensureSourceVisible(source.bookSourceUrl);
                    });
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          source.bookSourceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: titleForeground,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isExpanded && provider.isLoadingKinds)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      if (isExpanded && provider.isLoadingKinds)
                        const SizedBox(width: 6),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.chevron_right,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isExpanded && !provider.isLoadingKinds)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                0,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: AppRadius.cardMd,
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.8,
                    ),
                  ),
                ),
                child:
                    provider.expandedKinds.isEmpty
                        ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: 10,
                          ),
                          child: Text(
                            '暫無分類',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                        : _buildKindTags(provider, source, theme),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKindTags(
    ExploreProvider provider,
    BookSource source,
    ThemeData theme,
  ) {
    final kinds = provider.expandedKinds;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: LegadoExploreKindFlow(
        styles: kinds.map((kind) => kind.effectiveStyle).toList(),
        children:
            kinds.map((kind) {
              final isError = kind.title.startsWith('ERROR:');
              final hasUrl = kind.url != null && kind.url!.isNotEmpty;
              final background =
                  isError
                      ? theme.colorScheme.error.withValues(alpha: 0.08)
                      : theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.42,
                      );
              final borderColor =
                  isError
                      ? theme.colorScheme.error.withValues(alpha: 0.2)
                      : theme.colorScheme.outlineVariant;
              final textColor =
                  isError
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface;

              return Material(
                color: background,
                borderRadius: AppRadius.cardMd,
                child: InkWell(
                  borderRadius: AppRadius.cardMd,
                  onTap:
                      isError
                          ? () => _showKindError(context, kind)
                          : hasUrl
                          ? () => _navigateToExploreShow(source, kind)
                          : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.cardMd,
                        border: Border.all(color: borderColor),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        kind.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          height: 1.15,
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  void _showKindError(BuildContext context, ExploreKind kind) {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('ERROR'),
            content: SelectableText(kind.url ?? kind.title),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('關閉'),
              ),
            ],
          ),
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
    BuildContext context,
    ExploreProvider provider,
    BookSource source,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final menuPosition = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<String>(
      context: context,
      position: menuPosition,
      items: [
        const PopupMenuItem<String>(value: 'edit', child: Text('編輯')),
        const PopupMenuItem<String>(value: 'top', child: Text('置頂')),
        const PopupMenuItem<String>(value: 'search', child: Text('搜索')),
        const PopupMenuItem<String>(value: 'refresh', child: Text('刷新分類')),
        const PopupMenuItem<String>(value: 'delete', child: Text('刪除')),
      ],
    );

    if (!context.mounted || action == null) return;

    switch (action) {
      case 'edit':
        final full = await provider.getFullSource(source.bookSourceUrl);
        if (full != null && context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SourceEditorPage(source: full)),
          );
        }
        return;
      case 'top':
        await provider.topSource(source);
        return;
      case 'search':
        final full = await provider.getFullSource(source.bookSourceUrl);
        if (full == null || !context.mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SearchPage(initialSource: full)),
        );
        return;
      case 'refresh':
        await provider.refreshKindsCache(source);
        return;
      case 'delete':
        _confirmDelete(context, provider, source);
        return;
    }
  }

  void _confirmDelete(
    BuildContext context,
    ExploreProvider provider,
    BookSource source,
  ) {
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('確認'),
            content: Text('確定刪除「${source.bookSourceName}」嗎？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  provider.deleteSource(source);
                },
                child: Text(
                  '刪除',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _ensureSourceVisible(String sourceUrl) async {
    final itemContext = _itemKeys[sourceUrl]?.currentContext;
    if (itemContext == null || !_scrollController.hasClients) return;
    await Scrollable.ensureVisible(
      itemContext,
      duration: const Duration(milliseconds: 220),
      alignment: 0.0,
      curve: Curves.easeOutCubic,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/core/models/source/explore_kind.dart';
import 'package:night_reader/features/search/search_page.dart';
import 'package:night_reader/features/source_manager/source_editor_page.dart';
import 'package:night_reader/features/source_manager/source_manager_page.dart';

import 'explore_provider.dart';
import 'explore_show_page.dart';
import 'widgets/legado_explore_kind_flow.dart';

const String _allGroupsMenuValue = '__all_groups__';

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
            tooltip: '搜尋書籍',
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SearchPage()),
                ),
          ),
          if (!provider.isLoadingSources &&
              provider.sourceLoadError == null &&
              provider.groups.isNotEmpty)
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
    if (provider.isLoadingSources) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.sourceLoadError != null) {
      return _buildEmptyState(
        theme: theme,
        icon: Icons.error_outline,
        message: provider.sourceLoadError!,
        actions: [
          TextButton.icon(
            onPressed: provider.refresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重試'),
          ),
        ],
      );
    }

    if (provider.isEmpty &&
        provider.searchQuery.isEmpty &&
        provider.selectedGroup == null) {
      return _buildEmptyState(
        theme: theme,
        icon: Icons.travel_explore_outlined,
        message: '目前沒有可用的發現書源',
        actions: [
          TextButton.icon(
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SourceManagerPage()),
                ),
            icon: const Icon(Icons.source_outlined, size: 18),
            label: const Text('管理書源'),
          ),
          TextButton.icon(
            onPressed: provider.refresh,
            icon: const Icon(Icons.refresh, size: 18),
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
            icon: const Icon(Icons.clear, size: 18),
            label: const Text('清除條件'),
          ),
          TextButton.icon(
            onPressed: provider.refresh,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重新整理'),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, 0, AppSpacing.md),
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
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: actions,
              ),
            ],
          ),
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
    final titleBackground = theme.colorScheme.primary.withValues(alpha: 0.06);
    final titleForeground = theme.colorScheme.onSurface;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        index == provider.sources.length - 1 ? AppSpacing.sm : AppSpacing.sm,
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
              borderRadius: AppRadius.cardSm,
              child: InkWell(
                key: _itemKeys.putIfAbsent(source.bookSourceUrl, GlobalKey.new),
                borderRadius: AppRadius.cardSm,
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
                    vertical: 8,
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
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      if (isExpanded && provider.isLoadingKinds)
                        const SizedBox(width: AppSpacing.xs),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.chevron_right,
                        size: 19,
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
                AppSpacing.xs,
                AppSpacing.xs,
                AppSpacing.xs,
                0,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: AppRadius.cardSm,
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
                            vertical: 8,
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
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: LegadoExploreKindFlow(
        styles: kinds.map((kind) => kind.effectiveStyle).toList(),
        children:
            kinds.map((kind) {
              final isError = kind.title.startsWith('ERROR:');
              final hasUrl = kind.url != null && kind.url!.isNotEmpty;
              final background =
                  isError
                      ? theme.colorScheme.error.withValues(alpha: 0.06)
                      : theme.colorScheme.primary.withValues(alpha: 0.05);
              final borderColor =
                  isError
                      ? theme.colorScheme.error.withValues(alpha: 0.18)
                      : theme.colorScheme.outlineVariant;
              final textColor =
                  isError
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface;

              return Material(
                color: background,
                borderRadius: AppRadius.cardSm,
                child: InkWell(
                  borderRadius: AppRadius.cardSm,
                  onTap:
                      isError
                          ? () => _showKindError(context, kind)
                          : hasUrl
                          ? () => _navigateToExploreShow(source, kind)
                          : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 34),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.cardSm,
                        border: Border.all(color: borderColor),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        isError ? '分類載入失敗' : kind.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          height: 1.1,
                          color: textColor,
                          fontWeight: FontWeight.w500,
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
            title: const Text('分類載入錯誤'),
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
        const PopupMenuItem<String>(value: 'search', child: Text('搜尋')),
        const PopupMenuItem<String>(value: 'refresh', child: Text('重新整理分類')),
        const PopupMenuItem<String>(value: 'delete', child: Text('刪除')),
      ],
    );

    if (!context.mounted || action == null) return;

    try {
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
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('書源操作失敗：$error')));
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
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await provider.deleteSource(source);
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('刪除書源失敗：$error')),
                    );
                  }
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

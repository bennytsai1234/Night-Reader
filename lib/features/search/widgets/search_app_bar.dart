import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import '../search_provider.dart';

/// SearchAppBar - 搜尋頁面頂部欄
/// (對標 Legado SearchActivity 的 TitleBar + SearchView)
///
/// 功能：
/// - 搜尋輸入框
/// - 搜尋範圍顯示按鈕（點擊觸發 onScopePressed）
/// - 開始/停止搜尋按鈕
/// - 精準搜尋切換（PopupMenu）
class SearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController controller;
  final SearchProvider provider;
  final Function(String) onSearch;
  final VoidCallback? onScopePressed;
  final VoidCallback? onScopeMenuSelected;

  const SearchAppBar({
    super.key,
    required this.controller,
    required this.provider,
    required this.onSearch,
    this.onScopePressed,
    this.onScopeMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scopeDisplay =
        provider.scopeLoaded ? provider.searchScope.display : '載入中...';
    final inputBackground = theme.colorScheme.surfaceContainerHighest;
    final inputForeground = theme.colorScheme.onSurface;
    final inputHint = theme.colorScheme.onSurfaceVariant;

    return AppBar(
      titleSpacing: 0,
      title: Row(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: inputBackground,
                borderRadius: AppRadius.cardMd,
              ),
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: '搜尋書名或作者',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: inputHint),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                ),
                style: TextStyle(color: inputForeground),
                textInputAction: TextInputAction.search,
                onSubmitted: onSearch,
              ),
            ),
          ),
        ],
      ),
      actions: [
        Tooltip(
          message: '選擇搜尋範圍',
          child: InkWell(
            onTap: onScopePressed,
            borderRadius: AppRadius.cardXs,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    scopeDisplay,
                    style: AppTextStyles.labelSm.copyWith(
                      color:
                          provider.searchScope.isAll
                              ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
                              : theme.colorScheme.onSurface,
                      fontWeight:
                          provider.searchScope.isAll
                              ? FontWeight.normal
                              : FontWeight.bold,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: provider.isSearching ? '停止搜尋' : '搜尋',
          icon: Icon(
            provider.isSearching ? Icons.stop_circle_outlined : Icons.search,
            color:
                provider.isSearching
                    ? Theme.of(context).colorScheme.error
                    : null,
          ),
          onPressed: () {
            if (provider.isSearching) {
              provider.stopSearch();
            } else {
              onSearch(controller.text);
            }
          },
        ),
        PopupMenuButton<String>(
          tooltip: '搜尋設定',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'precision') {
              provider.togglePrecisionSearch();
            }
          },
          itemBuilder:
              (context) => [
                CheckedPopupMenuItem<String>(
                  value: 'precision',
                  checked: provider.precisionSearch,
                  child: const Text('精準搜尋（完全匹配）'),
                ),
              ],
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

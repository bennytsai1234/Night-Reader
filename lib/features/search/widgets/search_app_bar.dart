import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

import '../search_provider.dart';

import 'package:night_reader/shared/widgets/search_field.dart';

/// SearchAppBar - 搜尋頁面頂部欄
/// (對標 Legado SearchActivity 的 TitleBar + SearchView)
///
/// Telegram 式搜尋頁首：上排是圓角搜尋框與「取消」，下排是玻璃膠囊：
/// - 搜尋範圍（點擊觸發 onScopePressed）
/// - 精準搜尋切換
/// - 開始／停止搜尋
class SearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController controller;
  final SearchProvider provider;
  final ValueChanged<String> onSearch;
  final VoidCallback? onScopePressed;
  final VoidCallback onCancel;
  final bool autofocus;

  const SearchAppBar({
    super.key,
    required this.controller,
    required this.provider,
    required this.onSearch,
    required this.onCancel,
    this.onScopePressed,
    this.autofocus = false,
  });

  static const double _bottomHeight = GlassCapsule.height + AppSpacing.sm;

  @override
  Size get preferredSize =>
      const GlassNavHeader(bottomHeight: _bottomHeight).preferredSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scopeDisplay = provider.scopeLoaded
        ? provider.searchScope.display
        : '載入中…';

    return GlassNavHeader(
      automaticallyImplyLeading: false,
      titleWidget: Padding(
        // NavigationToolbar 兩側已有 middleSpacing，補到與分組卡片對齊。
        padding: const EdgeInsets.symmetric(
          horizontal: AppGrouped.margin - AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: SearchField(
                controller: controller,
                hintText: '搜尋書名或作者',
                autofocus: autofocus,
                onSubmitted: onSearch,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            PlainTextAction(label: '取消', onPressed: onCancel),
          ],
        ),
      ),
      bottomHeight: _bottomHeight,
      bottom: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppGrouped.margin,
          0,
          AppGrouped.margin,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Flexible(
              child: GlassCapsule(
                label: scopeDisplay,
                icon: Icons.layers_outlined,
                trailingIcon: Icons.expand_more_rounded,
                selected: !provider.searchScope.isAll,
                tooltip: '選擇搜尋範圍：$scopeDisplay',
                onTap: onScopePressed,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GlassCapsule(
              label: '精準搜尋',
              icon: provider.precisionSearch
                  ? Icons.check_rounded
                  : Icons.text_fields_rounded,
              selected: provider.precisionSearch,
              tooltip: '精準搜尋（完全匹配）',
              onTap: provider.togglePrecisionSearch,
            ),
            const Spacer(),
            const SizedBox(width: AppSpacing.sm),
            GlassCapsule(
              label: provider.isSearching ? '停止' : '搜尋',
              icon: provider.isSearching
                  ? Icons.stop_rounded
                  : Icons.search_rounded,
              foregroundColor: provider.isSearching ? scheme.error : null,
              tooltip: provider.isSearching ? '停止搜尋' : '搜尋',
              onTap: () {
                if (provider.isSearching) {
                  provider.stopSearch();
                } else {
                  onSearch(controller.text);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

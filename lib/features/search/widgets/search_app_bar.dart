import 'package:flutter/material.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/shared/widgets/book_kind_mark.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/layout/readable_width.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

import '../search_provider.dart';

import 'package:night_reader/shared/widgets/search_field.dart';

/// SearchAppBar - 搜尋頁面頂部欄
/// (對標 Legado SearchActivity 的 TitleBar + SearchView)
///
/// Telegram 式搜尋頁首：上排是圓角搜尋框與「取消」，下排是玻璃膠囊，
/// 字都是兩個字（docs/design/screens.md「搜尋」）：
/// - 搜哪一類書（書源不只一類時才有）
/// - 搜尋範圍（點擊觸發 onScopePressed）
/// - 精準搜尋切換
/// - 開始／停止搜尋
class SearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final SearchProvider provider;
  final ValueChanged<String> onSearch;
  final VoidCallback? onScopePressed;
  final VoidCallback onCancel;

  const SearchAppBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.provider,
    required this.onSearch,
    required this.onCancel,
    this.onScopePressed,
  });

  static const double _bottomHeight = GlassCapsule.height + AppSpacing.sm;

  @override
  Size get preferredSize =>
      const GlassNavHeader(bottomHeight: _bottomHeight).preferredSize;

  /// 類別膠囊上的字，兩個字。
  static String _shortLabel(BookSourceKind kind) => switch (kind) {
    BookSourceKind.comic => '漫畫',
    BookSourceKind.audio => '有聲',
    _ => '小說',
  };

  /// 類別選單同發現頁的書源類型：書源數、勾選目前那一類、右側圖示；
  /// 沒有書源的那一類灰掉（ADR 0059）。
  Future<void> _pickKind(BuildContext capsuleContext) async {
    final current = provider.kind;
    final picked = await showGlassMenu<BookSourceKind>(
      context: capsuleContext,
      anchor: globalRectOf(capsuleContext),
      entries: [
        for (final option in SearchProvider.switchableKinds)
          GlassMenuItem(
            value: option,
            label: '${option.sourceLabel}　${provider.kindCounts[option] ?? 0}',
            icon: BookKindMark.switchIconOf(option),
            checked: option == current,
            enabled: provider.kindCounts.containsKey(option),
          ),
      ],
    );
    if (picked != null) provider.setKind(picked);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scope = provider.searchScope;
    final scopeDisplay = scope.display;
    final kind = provider.kind;

    return GlassNavHeader(
      automaticallyImplyLeading: false,
      titleWidget: Padding(
        // NavigationToolbar 兩側已有 middleSpacing，補到與分組卡片對齊；
        // 平板上跟著內容欄（[ReadableWidth]）。
        padding: EdgeInsets.symmetric(
          horizontal:
              AppGrouped.margin -
              AppSpacing.md +
              ReadableWidth.sideOf(MediaQuery.sizeOf(context).width),
        ),
        child: Row(
          children: [
            Expanded(
              child: SearchField(
                controller: controller,
                focusNode: focusNode,
                hintText: '搜尋書名或作者',
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
            // 範圍膠囊是左半邊唯一能縮的，放得下就照原寬（不和右側留白
            // 平分空間），範圍名稱太長才截斷。
            Expanded(
              child: Row(
                children: [
                  Builder(
                    builder: (capsuleContext) => GlassCapsule(
                      label: _shortLabel(kind),
                      icon: BookKindMark.switchIconOf(kind),
                      trailingIcon: Icons.expand_more_rounded,
                      selected:
                          provider.kinds.isNotEmpty &&
                          kind != provider.kinds.first,
                      tooltip: '搜尋的類別：${kind.sourceLabel}',
                      onTap: () => _pickKind(capsuleContext),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: GlassCapsule(
                      label: scope.isAll ? '全部' : scopeDisplay,
                      icon: Icons.layers_outlined,
                      trailingIcon: Icons.expand_more_rounded,
                      selected: !scope.isAll,
                      tooltip: '選擇搜尋範圍：$scopeDisplay',
                      onTap: onScopePressed,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  GlassCapsule(
                    label: '精準',
                    icon: provider.precisionSearch
                        ? Icons.check_rounded
                        : Icons.text_fields_rounded,
                    selected: provider.precisionSearch,
                    tooltip: '精準搜尋（完全匹配）',
                    onTap: provider.togglePrecisionSearch,
                  ),
                ],
              ),
            ),
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

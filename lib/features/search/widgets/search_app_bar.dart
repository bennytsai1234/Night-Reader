import 'package:flutter/material.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/shared/widgets/book_kind_mark.dart';
import 'package:night_reader/shared/widgets/glass_menu.dart';
import 'package:night_reader/shared/layout/readable_width.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

import '../search_provider.dart';

import 'package:night_reader/shared/widgets/search_field.dart';
import 'package:night_reader/core/services/ui_language.dart';

/// SearchAppBar - 搜尋頁面頂部欄
/// (對標 Legado SearchActivity 的 TitleBar + SearchView)
///
/// Telegram 式搜尋頁首：上排是返回、圓角搜尋框與 ✦（AI 找書），下排是玻璃膠囊，
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
  final VoidCallback onBack;

  /// 搜尋框右邊的 ✦：AI 找書（ADR 0060）。
  final VoidCallback onAiFind;

  const SearchAppBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.provider,
    required this.onSearch,
    required this.onBack,
    required this.onAiFind,
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
        // 左右各一顆（docs/design/components.md）：只有圖示、和搜尋框同高，
        // 搜尋框在標題的位置。
        child: Row(
          children: [
            _BareAction(
              icon: Icons.arrow_back_ios_new_rounded,
              iconSize: 20,
              tooltip: '返回',
              onPressed: onBack,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SearchField(
                controller: controller,
                focusNode: focusNode,
                hintText: '搜尋書名或作者',
                onSubmitted: onSearch,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _BareAction(
              icon: Icons.auto_awesome_outlined,
              iconSize: 24,
              tooltip: 'AI 找書',
              accent: true,
              onPressed: onAiFind,
            ),
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
                      // 三類都沒有書源時整顆停用（ADR 0059）。
                      onTap: provider.kindCounts.isEmpty
                          ? null
                          : () => _pickKind(capsuleContext),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: GlassCapsule(
                      label: scope.isAll ? '全部' : scopeDisplay,
                      // 書源的分組或名稱照原文（ADR 0066）。
                      translate: scope.isAll,
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
                    tooltip: '精準搜尋',
                    onTap: provider.togglePrecisionSearch,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GlassCapsule(
              label: provider.isSearching ? '結束' : '搜尋',
              icon: provider.isSearching
                  ? Icons.stop_rounded
                  : Icons.search_rounded,
              foregroundColor: provider.isSearching ? scheme.error : null,
              tooltip: provider.isSearching ? '結束搜尋' : '搜尋',
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

/// 搜尋頁首兩側的鈕：只有圖示、不加底，和搜尋框同寬高的一格
/// （docs/design/screens.md「搜尋」）。✦ 是 24 的強調色，有沒有設定 AI 服務都在。
class _BareAction extends StatelessWidget {
  const _BareAction({
    required this.icon,
    required this.iconSize,
    required this.tooltip,
    required this.onPressed,
    this.accent = false,
  });

  final IconData icon;
  final double iconSize;
  final String tooltip;
  final VoidCallback onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: context.ui(tooltip),
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: context.ui(tooltip),
        child: PressScale(
          scale: 0.9,
          onTap: onPressed,
          child: SizedBox(
            width: _width,
            height: AppGlass.buttonSize,
            child: Center(
              child: Icon(
                icon,
                size: iconSize,
                color: accent ? scheme.primary : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const double _width = 28;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_chrome.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'glass.dart';

class FloatingTabItem {
  const FloatingTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Telegram iOS 26 式浮動膠囊分頁列，右側可附一顆圓形搜尋鈕。
///
/// 選取膠囊跟著 [controller] 的頁面位置連續移動（滑動切頁時同步）；手指
/// 在分頁列上橫向拖曳時膠囊跟手，放開後選最近的分頁。放在
/// [Scaffold.bottomNavigationBar] 並搭配 `extendBody: true`，內容會延伸到
/// 分頁列底下，浮動 SnackBar 也會自動避開分頁列。
class FloatingTabBar extends StatefulWidget {
  const FloatingTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.controller,
    this.onSearch,
    this.searchTooltip = '搜尋',
  });

  final List<FloatingTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// 主頁的 [PageController]；提供時選取膠囊跟著頁面捲動位置。
  final PageController? controller;
  final VoidCallback? onSearch;
  final String searchTooltip;

  @override
  State<FloatingTabBar> createState() => _FloatingTabBarState();
}

class _FloatingTabBarState extends State<FloatingTabBar> {
  /// 拖曳中的膠囊位置（以分頁索引為單位）；null 表示跟隨頁面。
  double? _dragPosition;

  double _pagePosition() {
    final controller = widget.controller;
    if (controller != null &&
        controller.hasClients &&
        controller.position.hasContentDimensions) {
      return controller.page ?? widget.currentIndex.toDouble();
    }
    return widget.currentIndex.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final width = MediaQuery.sizeOf(context).width;
    final searchWidth =
        widget.onSearch == null ? 0.0 : AppGlass.tabBarHeight + AppGlass.tabBarGap;
    final barWidth = math.min(
      AppGlass.tabBarMaxWidth,
      width - AppGrouped.margin * 2 - searchWidth,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppGrouped.margin,
        AppSpacing.sm,
        AppGrouped.margin,
        bottom + AppGlass.tabBarBottomGap,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: barWidth,
            height: AppGlass.tabBarHeight,
            child: _buildBar(context, barWidth),
          ),
          if (widget.onSearch != null) ...[
            const SizedBox(width: AppGlass.tabBarGap),
            Semantics(
              button: true,
              label: widget.searchTooltip,
              child: PressScale(
                onTap: widget.onSearch,
                child: SizedBox.square(
                  dimension: AppGlass.tabBarHeight,
                  child: GlassSurface(
                    shape: BoxShape.circle,
                    child: Icon(
                      Icons.search_rounded,
                      size: 26,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBar(BuildContext context, double barWidth) {
    final chrome = AppChrome.of(context);
    final count = widget.items.length;
    final itemWidth = (barWidth - AppGlass.tabInnerInset * 2) / count;

    int indexAt(double dx) =>
        ((dx - AppGlass.tabInnerInset) / itemWidth).floor().clamp(0, count - 1);

    void updateDrag(double dx) {
      final position = ((dx - AppGlass.tabInnerInset) / itemWidth - 0.5).clamp(
        0.0,
        (count - 1).toDouble(),
      );
      setState(() => _dragPosition = position);
    }

    void endDrag() {
      final position = _dragPosition;
      if (position == null) return;
      final index = position.round();
      setState(() => _dragPosition = null);
      if (index != widget.currentIndex) HapticFeedback.selectionClick();
      widget.onTap(index);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => widget.onTap(indexAt(d.localPosition.dx)),
      onHorizontalDragStart: (d) => updateDrag(d.localPosition.dx),
      onHorizontalDragUpdate: (d) => updateDrag(d.localPosition.dx),
      onHorizontalDragEnd: (_) => endDrag(),
      onHorizontalDragCancel: endDrag,
      child: GlassSurface(
        borderRadius: AppRadius.pillShape,
        child: AnimatedBuilder(
          animation: widget.controller ?? const AlwaysStoppedAnimation(0),
          builder: (context, _) {
            final target = _dragPosition ?? _pagePosition();
            return TweenAnimationBuilder<double>(
              tween: Tween(end: target),
              // 拖曳與跟頁時直接跟手；只有跳轉（例如無 controller）時用彈簧。
              duration:
                  _dragPosition != null || widget.controller != null
                      ? Duration.zero
                      : AppMotion.spring,
              curve: AppMotion.springCurve,
              builder: (context, position, _) {
                return Stack(
                  children: [
                    Positioned(
                      left: AppGlass.tabInnerInset + position * itemWidth,
                      top: AppGlass.tabInnerInset,
                      width: itemWidth,
                      height: AppGlass.tabItemHeight,
                      child: AnimatedScale(
                        scale: _dragPosition != null ? 1.06 : 1,
                        duration: AppMotion.menu,
                        curve: AppMotion.springCurve,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: chrome.selectionLens,
                            borderRadius: AppRadius.pillShape,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      left: AppGlass.tabInnerInset,
                      right: AppGlass.tabInnerInset,
                      top: AppGlass.tabInnerInset,
                      bottom: AppGlass.tabInnerInset,
                      child: Row(
                        children: [
                          for (var i = 0; i < count; i++)
                            Expanded(
                              child: _TabItem(
                                item: widget.items[i],
                                // 依膠囊距離漸變選取色，滑頁時顏色跟著過渡。
                                selection: (1 - (position - i).abs()).clamp(
                                  0.0,
                                  1.0,
                                ),
                                selected: i == widget.currentIndex,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.item,
    required this.selection,
    required this.selected,
  });

  final FloatingTabItem item;
  final double selection;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        Color.lerp(scheme.onSurfaceVariant, scheme.primary, selection)!;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            selection > 0.5 ? item.selectedIcon : item.icon,
            size: 24,
            color: color,
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            maxLines: 1,
            style: AppTextStyles.micro.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

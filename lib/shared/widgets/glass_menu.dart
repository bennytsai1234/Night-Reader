import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_chrome.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'glass.dart';

/// 情境選單的一個項目。
sealed class GlassMenuEntry<T> {
  const GlassMenuEntry();
}

class GlassMenuItem<T> extends GlassMenuEntry<T> {
  const GlassMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.subtitle,
    this.destructive = false,
    this.checked = false,
    this.enabled = true,
  });

  final T value;
  final String label;

  /// Telegram 把圖示放在右側。
  final IconData? icon;
  final String? subtitle;
  final bool destructive;

  /// 顯示在左側的勾號（切換類選項）。
  final bool checked;
  final bool enabled;
}

/// 群組之間的粗分隔。
class GlassMenuDivider<T> extends GlassMenuEntry<T> {
  const GlassMenuDivider();
}

/// 從 [anchor]（全域座標）旁邊彈出玻璃選單，取代 [PopupMenuButton]。
Future<T?> showGlassMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required List<GlassMenuEntry<T>> entries,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    _GlassMenuRoute<T>(
      anchor: anchor,
      entries: entries,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context, rootNavigator: true).context,
      ),
    ),
  );
}

/// 長按預覽選單：[preview] 從 [sourceRect] 浮起，旁邊列出動作
/// （Telegram 長按聊天的 context preview）。
Future<T?> showContextPreviewMenu<T>({
  required BuildContext context,
  required Rect sourceRect,
  required Widget preview,
  required List<GlassMenuEntry<T>> entries,
  BorderRadius previewRadius = AppRadius.cardLg,
}) {
  HapticFeedback.mediumImpact();
  return Navigator.of(context, rootNavigator: true).push<T>(
    _GlassMenuRoute<T>(
      anchor: sourceRect,
      entries: entries,
      preview: preview,
      previewRadius: previewRadius,
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context, rootNavigator: true).context,
      ),
    ),
  );
}

/// 取得 widget 在螢幕上的範圍，供 [showGlassMenu] 當錨點。
Rect globalRectOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// 圓形玻璃按鈕＋選單，取代 [PopupMenuButton]。
class GlassMenuButton<T> extends StatelessWidget {
  const GlassMenuButton({
    super.key,
    required this.entriesBuilder,
    required this.onSelected,
    this.icon = Icons.more_horiz_rounded,
    this.tooltip = '更多',
    this.child,
    this.enabled = true,
  });

  final List<GlassMenuEntry<T>> Function(BuildContext context) entriesBuilder;
  final ValueChanged<T> onSelected;
  final IconData icon;
  final String tooltip;

  /// 覆寫按鈕外觀；為 null 時使用 [GlassIconButton]。
  final Widget? child;

  /// 停用時按鈕變淡、點擊不開選單。
  final bool enabled;

  Future<void> _open(BuildContext context) async {
    final value = await showGlassMenu<T>(
      context: context,
      anchor: globalRectOf(context),
      entries: entriesBuilder(context),
    );
    if (value != null) onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) {
        final onTap = enabled ? () => _open(buttonContext) : null;
        if (child != null) {
          return Semantics(
            button: true,
            enabled: enabled,
            label: tooltip,
            child: PressScale(
              onTap: onTap,
              // 停用透明度同 [GlassIconButton]。
              child: enabled ? child! : Opacity(opacity: 0.38, child: child!),
            ),
          );
        }
        return GlassIconButton(icon: icon, tooltip: tooltip, onPressed: onTap);
      },
    );
  }
}

class _GlassMenuRoute<T> extends PopupRoute<T> {
  _GlassMenuRoute({
    required this.anchor,
    required this.entries,
    required this.capturedThemes,
    this.preview,
    this.previewRadius = AppRadius.cardLg,
  });

  final Rect anchor;
  final List<GlassMenuEntry<T>> entries;
  final CapturedThemes capturedThemes;
  final Widget? preview;
  final BorderRadius previewRadius;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '關閉選單';

  @override
  Duration get transitionDuration => AppMotion.menu;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 160);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return capturedThemes.wrap(
      _GlassMenuOverlay<T>(route: this, animation: animation),
    );
  }
}

class _GlassMenuOverlay<T> extends StatelessWidget {
  const _GlassMenuOverlay({required this.route, required this.animation});

  final _GlassMenuRoute<T> route;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final media = MediaQuery.of(context);
    final screen = media.size;
    final safe = media.padding;
    const edge = AppGrouped.margin;
    final hasPreview = route.preview != null;

    final menuHeight = _estimateMenuHeight(route.entries);
    final maxMenuHeight = screen.height - safe.vertical - edge * 2;
    final clampedMenuHeight = math.min(menuHeight, maxMenuHeight);
    final menuWidth = math.min(AppGlass.menuWidth, screen.width - edge * 2);

    // 選單水平位置：靠錨點同側對齊。
    final anchor = route.anchor;
    final alignRight = anchor.center.dx > screen.width / 2;
    final menuLeft = (alignRight ? anchor.right - menuWidth : anchor.left)
        .clamp(edge, screen.width - edge - menuWidth);

    // 預覽：必要時往上推，讓預覽＋選單都放得下。
    Rect previewRect = anchor;
    double menuTop;
    bool menuBelow;
    var menuMaxHeight = maxMenuHeight;
    if (hasPreview) {
      final needed = anchor.height + AppSpacing.md + clampedMenuHeight;
      final double top = anchor.top.clamp(
        safe.top + edge,
        math.max(safe.top + edge, screen.height - safe.bottom - edge - needed),
      );
      previewRect = Rect.fromLTWH(
        anchor.left,
        top,
        anchor.width,
        anchor.height,
      );
      menuTop = previewRect.bottom + AppSpacing.md;
      menuBelow = true;
      // 預覽很高（例如橫向）時下方放不下整個選單：選單高度只取剩下的空間、
      // 改成可捲動，最後幾項才不會畫到螢幕外。至少留一列的高度。
      menuMaxHeight = math.max(
        screen.height - safe.bottom - edge - menuTop,
        AppGlass.menuRowHeight,
      );
    } else {
      final spaceBelow = screen.height - safe.bottom - edge - anchor.bottom;
      menuBelow =
          spaceBelow >= clampedMenuHeight ||
          spaceBelow >= anchor.top - safe.top - edge;
      menuTop = menuBelow
          ? anchor.bottom + AppSpacing.sm
          : anchor.top - AppSpacing.sm - clampedMenuHeight;
      menuTop = menuTop.clamp(
        safe.top + edge,
        screen.height - safe.bottom - edge - clampedMenuHeight,
      );
    }

    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.springCurve,
      reverseCurve: Curves.easeInCubic,
    );
    final fade = CurvedAnimation(parent: animation, curve: AppMotion.fadeCurve);

    final menu = ConstrainedBox(
      constraints: BoxConstraints.tightFor(width: menuWidth)
          .copyWith(maxHeight: menuMaxHeight),
      child: GlassSurface(
        borderRadius: AppRadius.cardXl,
        grouped: false,
        tint: chrome.groupedSurface.withValues(alpha: 0.9),
        child: Material(
          type: MaterialType.transparency,
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            children: _buildEntries(context, chrome),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: FadeTransition(
              opacity: fade,
              child: hasPreview
                  ? BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: ColoredBox(color: chrome.barrier),
                    )
                  : ColoredBox(
                      color: chrome.barrier.withValues(
                        alpha: chrome.barrier.a * 0.4,
                      ),
                    ),
            ),
          ),
        ),
        if (hasPreview)
          AnimatedBuilder(
            animation: curved,
            builder: (context, child) {
              final rect = Rect.lerp(anchor, previewRect, curved.value)!;
              return Positioned.fromRect(
                rect: rect,
                child: Transform.scale(
                  scale: 1 + 0.03 * curved.value,
                  child: child,
                ),
              );
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: route.previewRadius,
                boxShadow: [
                  BoxShadow(
                    color: chrome.glassShadow,
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: route.previewRadius,
                child: IgnorePointer(child: route.preview),
              ),
            ),
          ),
        Positioned(
          left: menuLeft,
          top: menuTop,
          child: FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
              alignment: Alignment(alignRight ? 1 : -1, menuBelow ? -1 : 1),
              child: menu,
            ),
          ),
        ),
      ],
    );
  }

  double _estimateMenuHeight(List<GlassMenuEntry<T>> entries) {
    var height = 0.0;
    for (final entry in entries) {
      switch (entry) {
        case GlassMenuDivider<T>():
          height += AppSpacing.sm;
        case GlassMenuItem<T>(:final subtitle):
          height += subtitle == null
              ? AppGlass.menuRowHeight
              : AppGrouped.rowTallMinHeight;
      }
    }
    return height;
  }

  List<Widget> _buildEntries(BuildContext context, AppChrome chrome) {
    final scheme = Theme.of(context).colorScheme;
    final danger = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.rustDark
        : AppPalette.rust;
    final hasChecks = route.entries.any(
      (e) => e is GlassMenuItem<T> && e.checked,
    );
    final widgets = <Widget>[];
    GlassMenuEntry<T>? previous;
    for (final entry in route.entries) {
      switch (entry) {
        case GlassMenuDivider<T>():
          widgets.add(
            Container(
              height: AppSpacing.sm,
              color: chrome.separator.withValues(
                alpha: chrome.separator.a * 0.5,
              ),
            ),
          );
        case GlassMenuItem<T>():
          if (previous is GlassMenuItem<T>) {
            widgets.add(
              Container(height: AppGlass.hairline, color: chrome.separator),
            );
          }
          final color = entry.destructive ? danger : scheme.onSurface;
          widgets.add(
            InkWell(
              onTap: entry.enabled
                  ? () => Navigator.of(context).pop(entry.value)
                  : null,
              child: Opacity(
                opacity: entry.enabled ? 1 : 0.4,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: entry.subtitle == null
                        ? AppGlass.menuRowHeight
                        : AppGrouped.rowTallMinHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppGrouped.rowPadding,
                    ),
                    child: Row(
                      children: [
                        if (hasChecks)
                          SizedBox(
                            width: 26,
                            child: entry.checked
                                ? Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: color,
                                  )
                                : null,
                          ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodyBase.copyWith(
                                  height: 1.25,
                                  color: color,
                                ),
                              ),
                              if (entry.subtitle != null)
                                Text(
                                  entry.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodySm.copyWith(
                                    height: 1.25,
                                    color: chrome.sectionText,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (entry.icon != null) ...[
                          const SizedBox(width: AppSpacing.md),
                          Icon(entry.icon, size: 20, color: color),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
      }
      previous = entry;
    }
    return widgets;
  }
}

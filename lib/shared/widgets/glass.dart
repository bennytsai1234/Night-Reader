import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_chrome.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';

/// 霧面紙材質：紙／墨色調、輕度背景模糊、髮絲亮邊與漫射陰影。
///
/// 色調本身約 84% 不透明，即使模糊被降級仍像一張紙面，不會變成透明。
/// 模糊走 [BackdropFilter.grouped]，同一 [BackdropGroup] 下的多塊玻璃共用
/// 一次背景取樣。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.tint,
    this.shadow = true,
    this.blur = true,
    this.grouped = true,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  /// 覆寫色調（例如閱讀器選單用選單主題色）；需自帶透明度。
  final Color? tint;
  final bool shadow;
  final bool blur;

  /// 與同一頁的其他玻璃共用背景取樣。疊在其他玻璃上方的元件（選單、
  /// 面板）要設為 false，重疊區域共用取樣會只模糊一次。
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final radius = shape == BoxShape.circle ? null : borderRadius;
    final decoration = BoxDecoration(
      color: tint ?? chrome.glassTint,
      shape: shape,
      borderRadius: radius,
      border: Border.all(color: chrome.glassBorder, width: AppGlass.hairline),
    );
    Widget content = DecoratedBox(decoration: decoration, child: child);
    if (blur) {
      final filter = ImageFilter.blur(
        sigmaX: AppGlass.blurSigma,
        sigmaY: AppGlass.blurSigma,
      );
      content =
          grouped
              ? BackdropFilter.grouped(filter: filter, child: content)
              : BackdropFilter(filter: filter, child: content);
    }
    content =
        shape == BoxShape.circle
            ? ClipOval(child: content)
            : ClipRRect(
              borderRadius: radius ?? BorderRadius.zero,
              child: content,
            );
    if (!shadow) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: chrome.glassShadow,
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: content,
    );
  }
}

/// 按下時微縮的回饋（Telegram 玻璃按鈕的按壓感）。
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.92,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: _pressed ? const Duration(milliseconds: 90) : AppMotion.spring,
        curve: _pressed ? Curves.easeOut : AppMotion.springCurve,
        child: widget.child,
      ),
    );
  }
}

/// 44×44 圓形玻璃按鈕；導航頁首兩側與閱讀器選單使用。
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.tint,
    this.size = AppGlass.buttonSize,
    this.iconSize = 22,
    this.onLongPress,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final Color? color;
  final Color? tint;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    Widget button = PressScale(
      onTap: onPressed,
      onLongPress: onLongPress,
      child: SizedBox.square(
        dimension: size,
        child: GlassSurface(
          shape: BoxShape.circle,
          tint: tint,
          shadow: false,
          child: Center(
            child: Icon(
              icon,
              size: iconSize,
              color: (color ?? scheme.onSurface).withValues(
                alpha: enabled ? 1 : 0.38,
              ),
            ),
          ),
        ),
      ),
    );
    button = Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: button,
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// 膠囊形玻璃文字按鈕（例如頁首的「完成」「編輯」）。
class GlassTextButton extends StatelessWidget {
  const GlassTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// 主要動作用主色字並加粗。
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final color = emphasized ? scheme.primary : scheme.onSurface;
    return Semantics(
      button: true,
      enabled: enabled,
      child: PressScale(
        onTap: onPressed,
        child: SizedBox(
          height: AppGlass.buttonSize,
          child: GlassSurface(
            borderRadius: AppRadius.pillShape,
            shadow: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: AppTextStyles.uiMd.copyWith(
                    color: color.withValues(alpha: enabled ? 1 : 0.38),
                    fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 內容捲到浮動列底下時的邊緣漸隱。
class EdgeFade extends StatelessWidget {
  const EdgeFade({
    super.key,
    required this.edge,
    required this.height,
    this.color,
    this.solidFraction = 0,
  });

  /// [AxisDirection.up] 表示貼在上緣（由上往下淡出）。
  final AxisDirection edge;
  final double height;
  final Color? color;

  /// 從邊緣起算保持實色的比例。
  final double solidFraction;

  @override
  Widget build(BuildContext context) {
    final base = color ?? Theme.of(context).scaffoldBackgroundColor;
    final top = edge == AxisDirection.up;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                base,
                base,
                base.withValues(alpha: 0.72),
                base.withValues(alpha: 0),
              ],
              stops: [
                0,
                solidFraction,
                solidFraction + (1 - solidFraction) * 0.45,
                1,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Telegram 式導航頁首：置中標題、兩側圓形玻璃按鈕、下緣漸隱，無實心底板與
/// 分隔線。
///
/// 作為 [Scaffold.appBar] 使用。頁面搭配 `extendBodyBehindAppBar: true` 時，
/// 內容會捲到頁首底下並在下緣淡出；此時清單需讓出
/// `MediaQuery.paddingOf(context).top`（未指定 padding 的 ScrollView 會自動
/// 處理）。不延伸時頁首就是一段與背景同色的平整區域。
class GlassNavHeader extends StatelessWidget implements PreferredSizeWidget {
  const GlassNavHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions = const [],
    this.automaticallyImplyLeading = true,
    this.bottom,
    this.bottomHeight = 0,
    this.backgroundColor,
    this.foregroundColor,
    this.systemOverlayStyle,
  });

  final String? title;
  final Widget? titleWidget;

  /// 覆寫左側按鈕；為 null 且可返回時自動放返回鈕。
  final Widget? leading;
  final List<Widget> actions;
  final bool automaticallyImplyLeading;

  /// 標題列下方附加的內容（例如分段控制、搜尋框、橫向分頁）。
  final Widget? bottom;
  final double bottomHeight;

  /// 漸隱底色；預設為 scaffold 背景色。
  final Color? backgroundColor;
  final Color? foregroundColor;
  final SystemUiOverlayStyle? systemOverlayStyle;

  @override
  Size get preferredSize => Size.fromHeight(
    AppGlass.headerToolbarHeight + bottomHeight + AppGlass.headerFadeHeight,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    final bg = backgroundColor ?? theme.scaffoldBackgroundColor;
    final fg = foregroundColor ?? theme.colorScheme.onSurface;
    final route = ModalRoute.of(context);
    final canPop = route?.impliesAppBarDismissal ?? false;
    final effectiveLeading =
        leading ??
        (automaticallyImplyLeading && canPop
            ? GlassIconButton(
              icon:
                  route is PageRoute && route.fullscreenDialog
                      ? Icons.close_rounded
                      : Icons.arrow_back_ios_new_rounded,
              iconSize: 20,
              tooltip: '返回',
              color: fg,
              onPressed: () => Navigator.maybePop(context),
            )
            : null);
    final solidHeight =
        topPadding + AppGlass.headerToolbarHeight + bottomHeight;
    final totalHeight = solidHeight + AppGlass.headerFadeHeight;
    final brightness = ThemeData.estimateBrightnessForColor(bg);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          systemOverlayStyle ??
          (brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark),
      child: SizedBox(
        height: totalHeight,
        child: Stack(
          children: [
            Positioned.fill(
              child: EdgeFade(
                edge: AxisDirection.up,
                height: totalHeight,
                color: bg,
                solidFraction: (solidHeight - AppSpacing.xs) / totalHeight,
              ),
            ),
            Positioned(
              top: topPadding,
              left: 0,
              right: 0,
              height: AppGlass.headerToolbarHeight,
              child: NavigationToolbar(
                middleSpacing: AppSpacing.md,
                leading:
                    effectiveLeading == null
                        ? null
                        : Padding(
                          padding: const EdgeInsets.only(
                            left: AppGrouped.margin,
                          ),
                          child: IconTheme.merge(
                            data: IconThemeData(color: fg),
                            child: effectiveLeading,
                          ),
                        ),
                middle:
                    titleWidget ??
                    (title == null
                        ? null
                        : Semantics(
                          header: true,
                          child: Text(
                            title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.titleSm.copyWith(
                              fontWeight: FontWeight.w600,
                              color: fg,
                            ),
                          ),
                        )),
                trailing:
                    actions.isEmpty
                        ? null
                        : Padding(
                          padding: const EdgeInsets.only(
                            right: AppGrouped.margin,
                          ),
                          child: IconTheme.merge(
                            data: IconThemeData(color: fg),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < actions.length; i++) ...[
                                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                                  actions[i],
                                ],
                              ],
                            ),
                          ),
                        ),
              ),
            ),
            if (bottom != null)
              Positioned(
                top: topPadding + AppGlass.headerToolbarHeight,
                left: 0,
                right: 0,
                height: bottomHeight,
                child: bottom!,
              ),
          ],
        ),
      ),
    );
  }
}

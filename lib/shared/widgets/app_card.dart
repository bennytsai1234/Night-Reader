import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// 統一卡片容器 — 嚴格依循夜讀設計系統規範
///
/// 預設繼承 [ThemeData.cardTheme] 的形狀、圓角、微透光邊框與淺深色陰影。
/// 支援 InkWell 點擊回饋並確保水波紋被裁切於卡片圓角內。
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;
  final Color? color;
  final BorderSide? borderSide;
  final Clip clipBehavior;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.color,
    this.borderSide,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardTheme = theme.cardTheme;
    final effectiveRadius = borderRadius ?? AppRadius.cardLg;

    Widget content = padding != null ? Padding(padding: padding!, child: child) : child;

    if (onTap != null || onLongPress != null) {
      content = InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: effectiveRadius,
        child: content,
      );
    }

    BorderSide resolvedSide = BorderSide.none;
    if (borderSide != null) {
      resolvedSide = borderSide!;
    } else if (cardTheme.shape is RoundedRectangleBorder) {
      resolvedSide = (cardTheme.shape as RoundedRectangleBorder).side;
    }

    return Card(
      margin: margin ?? EdgeInsets.zero,
      color: color ?? cardTheme.color,
      elevation: cardTheme.elevation,
      shadowColor: cardTheme.shadowColor,
      clipBehavior: clipBehavior,
      shape: RoundedRectangleBorder(
        borderRadius: effectiveRadius,
        side: resolvedSide,
      ),
      child: content,
    );
  }
}

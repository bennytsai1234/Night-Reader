import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

/// 分組樣式底部面板的標題列：置中標題、兩側放文字或圓形玻璃按鈕。
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
  });

  final String title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppGrouped.margin,
        AppSpacing.sm,
        AppGrouped.margin,
        AppSpacing.xs,
      ),
      child: SizedBox(
        height: AppGlass.buttonSize,
        child: NavigationToolbar(
          middleSpacing: AppSpacing.md,
          leading: leading,
          trailing: trailing,
          middle: Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleMd.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 頁首或面板上的純文字動作（Telegram 的「取消」「清除」）。
class PlainTextAction extends StatelessWidget {
  const PlainTextAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.emphasized = false,
    this.destructive = false,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;
  final bool destructive;

  /// 組標題旁的小字動作。
  final bool small;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final base =
        destructive
            ? (Theme.of(context).brightness == Brightness.dark
                ? AppPalette.rustDark
                : AppPalette.rust)
            : scheme.primary;
    final style = (small ? AppTextStyles.uiSm : AppTextStyles.bodyBase)
        .copyWith(
          height: 1.2,
          color: base.withValues(alpha: enabled ? 1 : 0.4),
          fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
        );
    return Semantics(
      button: true,
      enabled: enabled,
      child: PressScale(
        scale: 0.95,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: small ? 28 : AppGlass.buttonSize,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: small ? 0 : AppSpacing.xs,
            ),
            child: Center(
              widthFactor: 1,
              child: Text(label, style: style),
            ),
          ),
        ),
      ),
    );
  }
}

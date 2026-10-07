import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

/// 小型玻璃膠囊（分類標籤、搜尋範圍等可點的小選項）。
///
/// 放在卡片等不透明底上時傳 `blur: false`，省下背景取樣。
class GlassCapsule extends StatelessWidget {
  const GlassCapsule({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.trailingIcon,
    this.selected = false,
    this.foregroundColor,
    this.blur = true,
    this.tint,
    this.maxLines = 1,
    this.tooltip,
  });

  static const double height = 34.0;

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final IconData? trailingIcon;

  /// 開啟中的選項：主色字與淡主色底。
  final bool selected;

  /// 覆寫文字與圖示顏色（例如錯誤項目）。
  final Color? foregroundColor;
  final bool blur;

  /// 覆寫未選取時的底色（例如放在卡片上時改用分組底色，與卡片區隔）。
  final Color? tint;
  final int maxLines;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final color = (foregroundColor ??
            (selected ? scheme.primary : scheme.onSurface))
        .withValues(alpha: enabled ? 1 : 0.45);
    final style = AppTextStyles.uiSm.copyWith(
      color: color,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    );

    Widget capsule = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: height),
      child: GlassSurface(
        borderRadius: AppRadius.pillShape,
        shadow: false,
        blur: blur,
        tint:
            selected
                ? Color.alphaBlend(
                  scheme.primary.withValues(alpha: 0.12),
                  scheme.surface.withValues(alpha: 0.9),
                )
                : tint,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md + 2,
            vertical: AppSpacing.xs + 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: color),
                const SizedBox(width: AppSpacing.xs),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: style,
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 2),
                Icon(trailingIcon, size: 16, color: color),
              ],
            ],
          ),
        ),
      ),
    );
    capsule = Semantics(
      button: enabled,
      selected: selected,
      label: tooltip,
      child: PressScale(scale: 0.95, onTap: onTap, child: capsule),
    );
    if (tooltip == null) return capsule;
    return Tooltip(message: tooltip!, child: capsule);
  }
}

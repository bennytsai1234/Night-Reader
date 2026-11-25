import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/context_ext.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';

/// 替換規則多選時底部的玻璃工具列：只有啟用、停用、刪除三個動作。
class ReaderReplaceRuleSelectBar extends StatelessWidget {
  const ReaderReplaceRuleSelectBar({
    super.key,
    required this.hasSelection,
    required this.onEnable,
    required this.onDisable,
    required this.onDelete,
  });

  /// 工具列本體高度（不含系統區與上下間距），同書源管理的多選工具列。
  static const double height = AppGlass.buttonSize + AppSpacing.sm * 2;

  final bool hasSelection;
  final VoidCallback onEnable;
  final VoidCallback onDisable;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actionsEnabled = hasSelection;
    return FloatingGlassToolbar(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: _BarTextButton(
              label: '啟用',
              color: scheme.onSurface,
              onTap: actionsEnabled ? onEnable : null,
            ),
          ),
          Expanded(
            child: _BarTextButton(
              label: '停用',
              color: scheme.onSurface,
              onTap: actionsEnabled ? onDisable : null,
            ),
          ),
          Expanded(
            child: _BarTextButton(
              label: '刪除',
              color: context.danger,
              onTap: actionsEnabled ? onDelete : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarTextButton extends StatelessWidget {
  const _BarTextButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: PressScale(
        onTap: onTap,
        child: SizedBox(
          height: AppGlass.buttonSize,
          child: Center(
            child: UiText(
              label,
              style: AppTextStyles.uiMd.copyWith(
                color: context.actionColor(color, enabled: enabled),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

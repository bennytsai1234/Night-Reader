import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';
import 'package:night_reader/shared/widgets/skeleton/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';

/// 卡片內「左側標籤、右側控件」的一列。
class GroupedLabeledRow extends StatelessWidget implements GroupedSkeletonItem {
  const GroupedLabeledRow({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: AppGrouped.rowPadding,
    vertical: AppSpacing.xs,
  );
  static const double _minHeight = AppGrouped.rowMinHeight - AppSpacing.xs * 2;
  static final TextStyle _labelStyle = AppTextStyles.bodyBase.copyWith(
    height: 1.3,
  );

  /// 標籤靠左；控件照它本身的大小靠右，放不下時和 build 一樣等比縮小。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final inner = width - _padding.horizontal;
    final label = GroupedItemShape.text(
      context,
      this.label,
      style: _labelStyle,
      width: inner,
    );
    final control = groupedPartShape(child, context);
    final room = inner - label.width! - AppSpacing.md;
    final scale = math.min(1.0, room / control.width!);
    final height = math.max(
      _minHeight,
      math.max(label.height, control.height * scale),
    );
    final controlLeft = inner - control.width! * scale;
    final controlTop = (height - control.height * scale) / 2;
    return GroupedItemShape(
      height,
      marks: [
        ...label.marksAt(Offset(0, (height - label.height) / 2)),
        for (final mark in control.marks)
          SkeletonShape(
            Rect.fromLTRB(
              controlLeft + mark.rect.left * scale,
              controlTop + mark.rect.top * scale,
              controlLeft + mark.rect.right * scale,
              controlTop + mark.rect.bottom * scale,
            ),
            radius: mark.radius * scale,
          ),
      ],
    ).padded(_padding);
  }

  @override
  Widget build(BuildContext context) {
    return GroupedContent(
      padding: _padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _minHeight),
        child: Row(
          children: [
            UiText(
              label,
              style: _labelStyle.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // 窄螢幕放不下時整個控件等比縮小，不溢出卡片。
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(fit: BoxFit.scaleDown, child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

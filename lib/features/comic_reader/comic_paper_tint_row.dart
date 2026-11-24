import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/core/chinese/ui_language.dart';
import 'package:night_reader/features/reader/features/settings/comic_paper_tint.dart';
import 'package:night_reader/features/reader/features/settings/reader_settings_controller.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/skeleton/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';

/// 漫畫偏好的「深色時的紙色」：一排色票，紙色上一個黑色的「漫」，就是漫畫
/// 染完的樣子（`docs/design/comics.md`「紙色」）。淺色時漫畫照原色，整排
/// 灰掉、不能按。
class ComicPaperTintRow extends StatelessWidget implements GroupedSkeletonItem {
  const ComicPaperTintRow({super.key, required this.settings});

  final ReaderSettingsController settings;

  static const double _swatchSize = 52;

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final labels = [
      for (final tint in ComicPaperTint.values)
        GroupedItemShape.text(
          context,
          tint.label,
          style: AppTextStyles.labelSm,
          width: double.infinity,
        ),
    ];
    // 每一格和 Row 裡的 Column 一樣寬（色票與名稱取較寬的），格與格之間
    // 照 spaceBetween 平分剩下的寬度。
    final columns = [
      for (final label in labels) math.max(_swatchSize, label.width!),
    ];
    final content = columns.fold<double>(0, (sum, column) => sum + column);
    final gap = math.max(0.0, width - content) / (columns.length - 1);
    final marks = <SkeletonShape>[];
    var left = 0.0;
    for (var i = 0; i < labels.length; i++) {
      final column = columns[i];
      marks.add(
        SkeletonShape(
          Rect.fromLTWH(
            left + (column - _swatchSize) / 2,
            0,
            _swatchSize,
            _swatchSize,
          ),
          radius: AppRadius.pillShape,
        ),
      );
      marks.addAll(
        labels[i].marksAt(
          Offset(
            left + (column - labels[i].width!) / 2,
            _swatchSize + AppSpacing.xs,
          ),
        ),
      );
      left += column + gap;
    }
    return GroupedItemShape(
      _swatchSize + AppSpacing.xs + labels.first.height,
      marks: marks,
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = Theme.of(context).brightness == Brightness.dark;
    final row = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final tint in ComicPaperTint.values)
          _swatch(
            context,
            tint,
            selected: tint == settings.comicPaperTint,
            enabled: enabled,
          ),
      ],
    );
    if (enabled) return row;
    return IgnorePointer(child: DisabledDim(child: row));
  }

  Widget _swatch(
    BuildContext context,
    ComicPaperTint tint, {
    required bool selected,
    required bool enabled,
  }) {
    final scheme = Theme.of(context).colorScheme;
    void onTap() => settings.setComicPaperTint(tint);
    return Semantics(
      label: context.ui(tint.label),
      selected: selected,
      button: true,
      enabled: enabled,
      // excludeSemantics 也排除了子樹手勢的點擊動作，要在這裡補上。
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppMotion.menu,
              width: _swatchSize,
              height: _swatchSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.color ?? Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  // 灰掉時強調色換成一般字色（[AppDisabled]）。
                  color: !selected
                      ? scheme.outlineVariant
                      : enabled
                      ? scheme.primary
                      : scheme.onSurface,
                  width: selected ? 3 : 1,
                ),
              ),
              // 漫畫的黑線條乘上紙色照樣是黑的。
              child: const UiText(
                '漫',
                // 色票大小固定，字不隨系統字級放大。
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            UiText(
              tint.label,
              style: AppTextStyles.labelSm.copyWith(
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

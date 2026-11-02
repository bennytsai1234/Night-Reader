import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book_source_part.dart';
import 'package:night_reader/core/models/source/book_source_logic.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/shared/layout/readable_width.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/grouped_list.dart';
import 'package:night_reader/shared/widgets/grouped_list_skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

import 'source_item_tile.dart';

/// 還不知道內容時的佔位長度，資料到齊後改照真正書源量字。
const List<double> _nameWidths = [0.4, 0.55, 0.3, 0.5, 0.35, 0.45];
const List<double> _urlWidths = [0.6, 0.45, 0.7, 0.5, 0.65, 0.4];

/// 書源管理的載入骨架。資料尚未讀回時保留一般書源列的預覽；資料讀好而
/// 換場尚未開始時，以同一份書源的標題、網址、功能標籤及錯誤行計算形狀。
class SourceListSkeleton extends StatelessWidget {
  const SourceListSkeleton({
    super.key,
    required this.padding,
    required this.count,
    this.sources = const [],
    this.progressOf,
  });

  final EdgeInsets padding;
  final int? count;
  final List<BookSourcePart> sources;
  final SourceCheckProgress? Function(String url)? progressOf;

  /// 尚未知資料時估算一列的高度，用於決定要鋪滿多少骨架。
  static double rowHeightOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return AppSpacing.md * 2 +
        scaler.scale(AppTextStyles.bodyBase.fontSize!) * 1.3 +
        2 +
        scaler.scale(AppTextStyles.bodySm.fontSize!) * 1.3 +
        AppSpacing.xs +
        _tagHeightOf(context);
  }

  /// 書源到齊後，內容排隊建構時的空位也照同一列的真正形狀留高度。
  static double rowHeightFor(
    BuildContext context,
    BookSourcePart source, {
    SourceCheckProgress? progress,
  }) {
    final width = math.min(
      MediaQuery.sizeOf(context).width,
      ReadableWidth.maxWidth,
    );
    return _sourceRowShape(
      context,
      width - AppGrouped.margin * 2,
      seed: 0,
      source: source,
      progress: progress,
    ).height;
  }

  static double _tagHeightOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(AppTextStyles.labelXs.fontSize!) *
          1.15 +
      4;

  @override
  Widget build(BuildContext context) {
    final rowHeight = rowHeightOf(context);
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fill =
              ((constraints.maxHeight - padding.vertical) / rowHeight).ceil() +
              1;
          final rows = count == null ? fill : count!.clamp(0, fill);
          final cardCount = count == null || count! > fill ? rows + 1 : rows;
          return ListView.builder(
            addRepaintBoundaries: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: padding,
            itemCount: rows,
            itemBuilder: (context, index) => GroupedSliceItem(
              index: index,
              count: cardCount,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final source = index < sources.length ? sources[index] : null;
                  final shape = _sourceRowShape(
                    context,
                    constraints.maxWidth,
                    seed: index,
                    source: source,
                    progress: source == null
                        ? null
                        : progressOf?.call(source.bookSourceUrl),
                  );
                  return SkeletonShapes(
                    height: shape.height,
                    shapes: (_) => shape.marks,
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 與 SourceItemTile 的實際 Row/Column 共用間距與字級。所有標記都相對
/// 卡片列左上角；卡片底色和圓角由 GroupedSliceItem 畫。
GroupedItemShape _sourceRowShape(
  BuildContext context,
  double width, {
  required int seed,
  BookSourcePart? source,
  SourceCheckProgress? progress,
}) {
  final titleStyle = AppTextStyles.bodyBase.copyWith(
    height: 1.3,
    fontWeight: FontWeight.w500,
  );
  final urlStyle = AppTextStyles.bodySm.copyWith(height: 1.3);
  final labelStyle = AppTextStyles.labelXs.copyWith(height: 1.15);
  final errorStyle = AppTextStyles.labelSm.copyWith(height: 1.3);
  final labelHeight = SourceListSkeleton._tagHeightOf(context);
  final textWidth = math.max(
    0.0,
    width -
        AppGrouped.rowPadding * 2 -
        AppSpacing.md -
        GroupedSwitch.trackWidth,
  );
  final marks = <SkeletonShape>[];
  final left = AppGrouped.rowPadding;
  final scale = MediaQuery.textScalerOf(context);
  final barFactor = Skeleton.barHeightFactor;

  GroupedItemShape text(
    String value,
    TextStyle style,
    double maxWidth, {
    int maxLines = 1,
  }) => GroupedItemShape.text(
    context,
    value,
    style: style,
    width: math.max(0.0, maxWidth),
    maxLines: maxLines,
  );

  void placeholder(
    double x,
    double y,
    double w,
    double h, {
    BorderRadius radius = AppRadius.cardXs,
  }) {
    if (w <= 0 || h <= 0) return;
    marks.add(SkeletonShape(Rect.fromLTWH(x, y, w, h), radius: radius));
  }

  (double, double) pill(
    String label,
    TextStyle style,
    double maxWidth,
    double horizontal,
  ) {
    final shape = text(label, style, maxWidth - horizontal);
    return (math.min(maxWidth, shape.width! + horizontal), shape.height + 4);
  }

  final group = source?.bookSourceGroup?.trim();
  final hasGroup = group != null && group.isNotEmpty;
  final health = source?.runtimeHealth;
  final hasHealth =
      health != null && health.category != SourceHealthCategory.healthy;
  final groupSize = hasGroup
      ? pill(group, labelStyle, 120, AppSpacing.sm * 2)
      : (0.0, 0.0);
  final statusSize = hasHealth
      ? pill(
          health.label,
          labelStyle.copyWith(fontWeight: FontWeight.w600),
          textWidth,
          AppSpacing.xs * 2,
        )
      : (0.0, 0.0);
  final hasExplore = source?.hasExploreUrl ?? false;
  final trailingWidth =
      (hasGroup ? AppSpacing.sm + groupSize.$1 : 0) +
      (hasExplore ? AppSpacing.sm + 8 : 0) +
      (hasHealth ? AppSpacing.sm + statusSize.$1 : 0);
  final nameWidth = math.max(0.0, textWidth - trailingWidth);
  final title = text(source?.bookSourceName ?? '書源', titleStyle, nameWidth);
  final url = text(
    source?.bookSourceUrl ?? 'https://example.org',
    urlStyle,
    textWidth,
  );
  final titleHeight = [
    title.height,
    if (hasGroup) groupSize.$2,
    if (hasExplore) 8.0,
    if (hasHealth) statusSize.$2,
  ].reduce(math.max);
  var y = AppSpacing.md;
  final titleTop = y + (titleHeight - title.height) / 2;
  if (source == null) {
    placeholder(
      left,
      titleTop +
          (title.height - scale.scale(titleStyle.fontSize!) * barFactor) / 2,
      nameWidth * _nameWidths[seed % _nameWidths.length],
      scale.scale(titleStyle.fontSize!) * barFactor,
    );
  } else {
    marks.addAll(title.marksAt(Offset(left, titleTop)));
  }
  var right = left + (source == null ? title.width! : title.width!);
  if (hasGroup) {
    right += AppSpacing.sm;
    placeholder(
      right,
      y + (titleHeight - groupSize.$2) / 2,
      groupSize.$1,
      groupSize.$2,
      radius: AppRadius.pillShape,
    );
    right += groupSize.$1;
  }
  if (hasExplore) {
    right += AppSpacing.sm;
    placeholder(
      right,
      y + (titleHeight - 8) / 2,
      8,
      8,
      radius: const BorderRadius.all(Radius.circular(4)),
    );
    right += 8;
  }
  if (hasHealth) {
    right += AppSpacing.sm;
    placeholder(
      right,
      y + (titleHeight - statusSize.$2) / 2,
      statusSize.$1,
      statusSize.$2,
    );
  }

  y += titleHeight + 2;
  if (source == null) {
    placeholder(
      left,
      y + (url.height - scale.scale(urlStyle.fontSize!) * barFactor) / 2,
      textWidth * _urlWidths[seed % _urlWidths.length],
      scale.scale(urlStyle.fontSize!) * barFactor,
    );
  } else {
    marks.addAll(url.marksAt(Offset(left, y)));
  }
  y += url.height + AppSpacing.xs;

  final tags = source == null
      ? List<String>.filled(3 + seed % 2, '搜')
      : sourceFunctionTags(source);
  var tagX = left;
  var tagY = y;
  var rows = 0;
  for (final tag in tags) {
    final tagSize = source == null
        ? (labelHeight, labelHeight)
        : pill(tag, labelStyle, textWidth, AppSpacing.xs * 2);
    if (tagX > left && tagX + tagSize.$1 > left + textWidth) {
      tagX = left;
      tagY += labelHeight + AppSpacing.xs;
    }
    placeholder(tagX, tagY, tagSize.$1, tagSize.$2);
    tagX += tagSize.$1 + AppSpacing.xs;
    rows = rows == 0 ? 1 : rows;
  }
  if (rows > 0) y = tagY + labelHeight;

  final error = progress == null && source != null
      ? sourceErrorLine(source)
      : null;
  if (progress != null) {
    y += AppSpacing.sm;
    final symbol = progress.isFinal ? 14.0 : 12.0;
    placeholder(
      left,
      y + 2,
      symbol,
      symbol,
      radius: BorderRadius.circular(symbol / 2),
    );
    final message = text(
      progress.message,
      errorStyle.copyWith(
        fontWeight: progress.isFinal ? FontWeight.w600 : FontWeight.w500,
      ),
      textWidth - symbol - AppSpacing.sm,
      maxLines: 2,
    );
    marks.addAll(message.marksAt(Offset(left + symbol + AppSpacing.sm, y)));
    y += math.max(symbol + 2, message.height);
  }
  if (error != null) {
    y += AppSpacing.xs;
    final errorShape = text(error, errorStyle, textWidth, maxLines: 2);
    marks.addAll(errorShape.marksAt(Offset(left, y)));
    y += errorShape.height;
  }

  final height = math.max(
    y + AppSpacing.md,
    GroupedSwitch.trackHeight + AppSpacing.md * 2,
  );
  placeholder(
    width - AppGrouped.rowPadding - GroupedSwitch.trackWidth,
    (height - GroupedSwitch.trackHeight) / 2,
    GroupedSwitch.trackWidth,
    GroupedSwitch.trackHeight,
    radius: AppRadius.pillShape,
  );
  return GroupedItemShape(height, marks: marks);
}

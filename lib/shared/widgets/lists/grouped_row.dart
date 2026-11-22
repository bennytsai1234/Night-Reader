import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../navigation/transition_origin.dart';
import '../../theme/app_chrome.dart';
import '../../theme/app_haptics.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import '../skeleton/grouped_list_skeleton.dart';
import '../text/drag_overflow_text.dart';
import '../text/ui_text.dart';
import 'grouped_section.dart';
import 'press_ink.dart';

/// 分組清單的一列：列首（圖示方塊或任意 widget）、標題、副標、右側數值、
/// 右側控件與箭頭。按下時整列高亮，不畫水波紋。
class GroupedRow extends StatelessWidget
    implements GroupedRowLike, GroupedSkeletonItem {
  const GroupedRow({
    super.key,
    required this.title,
    this.titleWidget,
    this.titleMark,
    this.subtitle,
    this.leading,
    this.value,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.showChevron,
    this.destructive = false,
    this.accent = false,
    this.heading = false,
    this.enabled = true,
    this.maxSubtitleLines = 2,
    this.maxTitleLines,
    this.translateTitle = true,
    this.translateSubtitle = true,
    this.translateValue = true,
  });

  final String title;

  /// 卡片第一列的粗字標題：本身是資料、標出這一組是哪一本書、哪一版、哪一類
  /// 結果的那一行（書名、版本號與日期、「修好了 · 3」），右側 [value] 放
  /// 跟著它的數值（ADR 0076）。
  final bool heading;

  /// 標題、副標、右側數值是書或使用者的資料（書名、章名、書源名稱、自己寫的
  /// 字）時給 false：不跟介面語言轉換，書的資料照閱讀偏好的繁簡轉換（ADR 0066）。
  final bool translateTitle;
  final bool translateSubtitle;
  final bool translateValue;

  /// 覆寫標題（例如帶徽章）；[title] 仍作為語意標籤。
  final Widget? titleWidget;

  /// 接在標題字後面的小記號（例如閱讀統計裡漫畫、有聲書的 `BookKindMark`）。
  final Widget? titleMark;

  /// 標題下方的值（網址、最新章節、錯誤訊息），不放功能說明（ADR 0009）。
  final String? subtitle;

  /// 通常是 [GroupedIconTile]。
  final Widget? leading;

  /// 右側次要文字（目前值）。
  final String? value;

  /// 右側控件（開關、勾選、載入中）。
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 是否顯示右側箭頭；預設為「可點且沒有 trailing」。
  final bool? showChevron;

  /// 危險動作（紅色標題）。
  final bool destructive;

  /// 動作列（主色標題，例如「新增書源」）。
  final bool accent;
  final bool enabled;
  final int maxSubtitleLines;

  /// 標題最多幾行，超過以「…」截斷；null 時照寬度換行。右側的字會之後才
  /// 讀到、或同一列會換成另一個標題時，設成 1 讓列高不跟著字變。
  final int? maxTitleLines;

  @override
  bool get hasLeading => leading != null;

  /// 標題與右側數值的字樣、副標的字樣；骨架照同一份排。
  Widget _withMark(Widget title) {
    final mark = titleMark;
    if (mark == null) return title;
    return Row(
      children: [
        Flexible(child: title),
        const SizedBox(width: AppSpacing.sm),
        mark,
      ],
    );
  }

  FontWeight get _titleWeight => heading
      ? FontWeight.w600
      : accent
      ? FontWeight.w500
      : FontWeight.w400;

  static final TextStyle _textStyle = AppTextStyles.bodyBase.copyWith(
    height: 1.3,
  );
  static final TextStyle _subtitleStyle = AppTextStyles.bodySm.copyWith(
    height: 1.3,
  );
  static const double _subtitleGap = 2;
  static const double _chevronSize = 22;

  /// 右側數值最寬佔螢幕的四成，再長以「…」截斷、靠右對齊。
  static double _valueMaxWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width * 0.4;

  /// 這一列放在 [width] 寬的卡片裡的樣子：照 build 的同一份內距、字樣與
  /// 元件尺寸，由右往左排箭頭、右側控件與數值，標題與副標照剩下的寬度真的
  /// 排（字大時標題會換行），整列垂直置中。列首與右側控件見
  /// [groupedPartShape]。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    // 每一塊左緣的位置與樣子；垂直位置等列高算出來再置中。
    final parts = <(double, GroupedItemShape)>[];
    var right = width - AppGrouped.rowPadding;
    if (showChevron ?? (onTap != null && trailing == null)) {
      right -= _chevronSize;
      parts.add((right, groupedGlyphShape(_chevronSize)));
      right -= AppSpacing.sm;
    }
    if (trailing case final trailing?) {
      final shape = groupedPartShape(trailing, context);
      right -= shape.width!;
      parts.add((right, shape));
      right -= AppSpacing.md;
    }
    if (value case final value?) {
      final shape = GroupedItemShape.text(
        context,
        value,
        style: _textStyle,
        width: _valueMaxWidth(context),
        maxLines: 1,
        textAlign: TextAlign.end,
      );
      right -= shape.width!;
      parts.add((right, shape));
      right -= AppSpacing.md;
    }
    var textLeft = AppGrouped.rowPadding;
    if (leading case final leading?) {
      final shape = groupedPartShape(leading, context);
      parts.add((textLeft, shape));
      textLeft += shape.width! + AppGrouped.iconGap;
    }
    // 自訂的標題（目錄的章名：粗細、縮排不同）認得出來時照它畫的字排。
    final title =
        (titleWidget == null
            ? null
            : GroupedItemShape.maybeOf(
                titleWidget!,
                context: context,
                width: right - textLeft,
              )) ??
        GroupedItemShape.text(
          context,
          this.title,
          style: _textStyle.copyWith(fontWeight: _titleWeight),
          width: right - textLeft,
          maxLines: maxTitleLines,
        );
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    final subtitleShape = hasSubtitle
        ? GroupedItemShape.text(
            context,
            subtitle!,
            style: _subtitleStyle,
            width: right - textLeft,
            maxLines: maxSubtitleLines,
          )
        : null;
    final text = switch (subtitleShape) {
      final subtitle? => title.height + _subtitleGap + subtitle.height,
      null => title.height,
    };
    final content = parts.fold(
      text,
      (height, part) => math.max(height, part.$2.height),
    );
    final height = math.max(
      hasSubtitle ? AppGrouped.rowTallMinHeight : AppGrouped.rowMinHeight,
      content + AppSpacing.md * 2,
    );
    final textTop = (height - text) / 2;
    return GroupedItemShape(
      height,
      marks: [
        for (final (left, part) in parts)
          ...part.marksAt(Offset(left, (height - part.height) / 2)),
        ...title.marksAt(Offset(textLeft, textTop)),
        ...?subtitleShape?.marksAt(
          Offset(textLeft, textTop + title.height + _subtitleGap),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    // 停用的列整列降到 [AppDisabled.opacity]，標題的危險色、強調色先換回
    // 一般字色，和停用的選單項目同一種灰。
    final titleColor = !enabled
        ? scheme.onSurface
        : destructive
        ? (Theme.of(context).brightness == Brightness.dark
              ? AppPalette.rustDark
              : AppPalette.rust)
        : accent
        ? scheme.primary
        : scheme.onSurface;
    final chevron = showChevron ?? (onTap != null && trailing == null);
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;

    Widget row = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: hasSubtitle
            ? AppGrouped.rowTallMinHeight
            : AppGrouped.rowMinHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppGrouped.rowPadding,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              // 停用的列首（圖示方塊的顏料色）去色，和標題一起變中性灰。
              enabled
                  ? leading!
                  : ColorFiltered(colorFilter: _greyscale, child: leading!),
              const SizedBox(width: AppGrouped.iconGap),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  titleWidget ??
                      _withMark(
                        DragOverflowText(
                          child: UiText(
                            title,
                            translate: translateTitle,
                            maxLines: maxTitleLines,
                            style: _textStyle.copyWith(
                              color: titleColor,
                              fontWeight: _titleWeight,
                            ),
                          ),
                        ),
                      ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: _subtitleGap),
                    DragOverflowText(
                      child: UiText(
                        subtitle!,
                        translate: translateSubtitle,
                        maxLines: maxSubtitleLines,
                        style: _subtitleStyle.copyWith(
                          color: chrome.sectionText,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: AppSpacing.md),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _valueMaxWidth(context)),
                child: DragOverflowText(
                  child: UiText(
                    value!,
                    translate: translateValue,
                    maxLines: 1,
                    textAlign: TextAlign.end,
                    style: _textStyle.copyWith(color: chrome.sectionText),
                  ),
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.md),
              trailing!,
            ],
            if (chevron) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.chevron_right_rounded,
                size: _chevronSize,
                color: chrome.sectionText.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
      ),
    );

    if (!enabled) {
      row = Opacity(opacity: AppDisabled.opacity, child: row);
    }
    if (onTap == null && onLongPress == null) {
      // 標題文字本來就會併進這個節點，再設 label 讀屏會念成「標題、標題、值」。
      // 卡片第一列的粗字資料在讀屏裡是標題，可以照組跳。
      return Semantics(container: true, header: heading, child: row);
    }
    return TransitionSource(
      child: PressInk(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        child: row,
      ),
    );
  }
}

/// 去掉顏色、只留明暗（照 Rec. 709 的亮度）。
const ColorFilter _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// 列首上色圓角圖示方塊（Telegram 設定頁的彩色圖示）。
class GroupedIconTile extends StatelessWidget {
  const GroupedIconTile(this.icon, {super.key, this.tint = AppTint.cinnabar});

  final IconData icon;
  final AppTint tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppGrouped.iconTile,
      height: AppGrouped.iconTile,
      decoration: BoxDecoration(
        color: tint.color,
        borderRadius: BorderRadius.circular(AppGrouped.iconTileRadius),
      ),
      child: Icon(icon, size: 18, color: AppPalette.paper50),
    );
  }
}

/// 分組清單的開關：40×24 的膠囊軌道、20 的紙色滑塊，不畫陰影或外框。
///
/// 尺寸與 44 高的列、17 號字相稱：軌道高約是列高的一半、比 17 號字的行高
/// 略高，寬高比沿用 iOS 開關（51×31）的 5:3。
class GroupedSwitch extends StatelessWidget {
  const GroupedSwitch({super.key, required this.value, this.onChanged});

  static const double trackWidth = 40;
  static const double trackHeight = 24;
  static const double _thumbInset = 2;
  static const double _thumbSize = trackHeight - _thumbInset * 2;

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// 切換開關並給一聲選擇回饋；[GroupedSwitchRow] 點整列時也走這裡。
  static void toggle(bool value, ValueChanged<bool> onChanged) {
    AppHaptics.select();
    onChanged(!value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    final light = Theme.of(context).brightness == Brightness.light;
    final enabled = onChanged != null;
    // 關閉時的軌道取次要文字色的淡色：淺色約 1.6:1、深色約 1.9:1，
    // 看得出軌道但不搶眼。
    final offTrack = chrome.sectionText.withValues(alpha: light ? 0.3 : 0.4);

    final track = AnimatedContainer(
      duration: AppMotion.menu,
      curve: AppMotion.menuCurve,
      width: trackWidth,
      height: trackHeight,
      padding: const EdgeInsets.all(_thumbInset),
      decoration: BoxDecoration(
        color: value ? scheme.primary : offTrack,
        borderRadius: AppRadius.pillShape,
      ),
      child: AnimatedAlign(
        duration: AppMotion.spring,
        curve: AppMotion.springCurve,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: const SizedBox.square(
          dimension: _thumbSize,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppPalette.paper50,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );

    return Semantics(
      toggled: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => toggle(value, onChanged!) : null,
        // 開關的開或關是狀態，停用時軌道顏色留著，只降透明度。
        child: Opacity(
          opacity: enabled ? 1 : AppDisabled.opacity,
          child: track,
        ),
      ),
    );
  }
}

/// 帶開關的列；點整列也會切換。
class GroupedSwitchRow extends StatelessWidget
    implements GroupedRowLike, GroupedSkeletonItem {
  const GroupedSwitchRow({
    super.key,
    required this.title,
    this.leading,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  bool get hasLeading => leading != null;

  GroupedRow get _row {
    final active = enabled && onChanged != null;
    return GroupedRow(
      title: title,
      leading: leading,
      enabled: enabled,
      showChevron: false,
      onTap: active ? () => GroupedSwitch.toggle(value, onChanged!) : null,
      trailing: GroupedSwitch(
        value: value,
        onChanged: active ? onChanged : null,
      ),
    );
  }

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => _row.skeletonShape(context, width: width);

  @override
  Widget build(BuildContext context) => MergeSemantics(child: _row);
}

/// 單選清單的一列：選中時右側打勾（取代 Radio）。
class GroupedCheckRow extends StatelessWidget
    implements GroupedRowLike, GroupedSkeletonItem {
  const GroupedCheckRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.translate = true,
    this.exclusive = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// 單選（一組裡只勾一個）；可複選的清單給 false。
  final bool exclusive;

  /// 標題與副標是書源名稱、網址這類資料時給 false，不跟介面語言轉換
  /// （ADR 0066）。
  final bool translate;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  bool get hasLeading => leading != null;

  static const double _checkSize = 22;

  GroupedRow _row(BuildContext context) => GroupedRow(
    title: title,
    subtitle: subtitle,
    translateTitle: translate,
    translateSubtitle: translate,
    leading: leading,
    enabled: enabled,
    showChevron: false,
    onTap: onTap,
    trailing: SizedBox(
      width: _checkSize,
      height: selected ? _checkSize : null,
      child: selected
          ? Icon(
              Icons.check_rounded,
              size: _checkSize,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
    ),
  );

  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) => _row(context).skeletonShape(context, width: width);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: exclusive ? selected : null,
      checked: exclusive ? null : selected,
      inMutuallyExclusiveGroup: exclusive,
      child: _row(context),
    );
  }
}

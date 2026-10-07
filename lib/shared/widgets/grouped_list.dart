import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';

import '../theme/app_chrome.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';

/// Telegram 式分組清單的一組：上方組標題、圓角卡片、下方說明文字。
///
/// 列與列之間自動插入髮絲分隔線；有任一 [GroupedRow] 帶列首圖示時，
/// 分隔線從文字起點開始。分組本身帶上方間距，連續排列即可。
class GroupedSection extends StatelessWidget {
  const GroupedSection({
    super.key,
    this.header,
    this.headerTrailing,
    this.footer,
    this.footerWidget,
    required this.children,
    this.separatorIndent,
    this.margin,
    this.topGap = AppGrouped.sectionGap,
  });

  final String? header;

  /// 組標題右側的動作（例如「全部清除」）。
  final Widget? headerTrailing;

  /// 卡片下方的說明文字。
  final String? footer;
  final Widget? footerWidget;
  final List<Widget> children;

  /// 覆寫分隔線左縮排。
  final double? separatorIndent;

  /// 覆寫卡片外距；預設左右 [AppGrouped.margin]。
  final EdgeInsetsGeometry? margin;

  /// 組上方間距；清單第一組可傳較小值。
  final double topGap;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final indent =
        separatorIndent ??
        (children.any((c) => c is GroupedRow && c.leading != null)
            ? AppGrouped.separatorIndentWithIcon
            : AppGrouped.rowPadding);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Padding(
            padding: EdgeInsetsDirectional.only(start: indent),
            child: Container(height: AppGlass.hairline, color: chrome.separator),
          ),
        );
      }
      rows.add(children[i]);
    }
    final effectiveMargin =
        margin ??
        const EdgeInsets.symmetric(horizontal: AppGrouped.margin);

    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null || headerTrailing != null)
            Padding(
              padding: effectiveMargin.add(
                const EdgeInsets.fromLTRB(
                  AppGrouped.rowPadding,
                  0,
                  AppGrouped.rowPadding,
                  AppSpacing.sm,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: GroupedSectionHeader(header ?? '')),
                  if (headerTrailing != null) headerTrailing!,
                ],
              ),
            ),
          Padding(
            padding: effectiveMargin,
            child: ClipRRect(
              borderRadius: AppGrouped.cardRadius,
              child: Material(
                color: chrome.groupedSurface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: rows,
                ),
              ),
            ),
          ),
          if (footer != null || footerWidget != null)
            Padding(
              padding: effectiveMargin.add(
                const EdgeInsets.fromLTRB(
                  AppGrouped.rowPadding,
                  AppSpacing.sm,
                  AppGrouped.rowPadding,
                  0,
                ),
              ),
              child:
                  footerWidget ??
                  Text(
                    footer!,
                    style: AppTextStyles.bodySm.copyWith(
                      color: chrome.sectionText,
                    ),
                  ),
            ),
        ],
      ),
    );
  }
}

/// 組標題文字；也可單獨用在非卡片內容（例如格狀選項）上方。
class GroupedSectionHeader extends StatelessWidget {
  const GroupedSectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: AppTextStyles.uiSm.copyWith(
          color: AppChrome.of(context).sectionText,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

/// 分組清單頁面的捲動容器：分組底色、底部讓出系統區與浮動分頁列。
///
/// 頁面搭配 [GlassNavHeader] 與 `extendBodyBehindAppBar: true` 時，上方
/// 內距會包含頁首高度。
class GroupedListView extends StatelessWidget {
  const GroupedListView({
    super.key,
    required this.children,
    this.controller,
    this.bottomPadding = AppSpacing.xxxl,
    this.physics,
  });

  final List<Widget> children;
  final ScrollController? controller;
  final double bottomPadding;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: AppChrome.of(context).groupedBackground,
      child: ListView(
        controller: controller,
        physics: physics,
        padding: EdgeInsets.only(
          top: padding.top,
          bottom: padding.bottom + bottomPadding,
        ),
        children: children,
      ),
    );
  }
}

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

/// 分組清單的一列：列首（圖示方塊或任意 widget）、標題、副標、右側數值、
/// 右側控件與箭頭。按下時整列高亮，不畫水波紋。
class GroupedRow extends StatelessWidget {
  const GroupedRow({
    super.key,
    required this.title,
    this.titleWidget,
    this.subtitle,
    this.leading,
    this.value,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.showChevron,
    this.destructive = false,
    this.accent = false,
    this.enabled = true,
    this.maxSubtitleLines = 2,
  });

  final String title;

  /// 覆寫標題（例如帶徽章）；[title] 仍作為語意標籤。
  final Widget? titleWidget;
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    final titleColor =
        destructive
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
        minHeight:
            hasSubtitle ? AppGrouped.rowTallMinHeight : AppGrouped.rowMinHeight,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppGrouped.rowPadding,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppGrouped.iconGap),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  titleWidget ??
                      Text(
                        title,
                        style: AppTextStyles.bodyBase.copyWith(
                          height: 1.3,
                          color: titleColor,
                          fontWeight:
                              accent ? FontWeight.w500 : FontWeight.w400,
                        ),
                      ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: maxSubtitleLines,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySm.copyWith(
                        height: 1.3,
                        color: chrome.sectionText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: AppSpacing.md),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                ),
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppTextStyles.bodyBase.copyWith(
                    height: 1.3,
                    color: chrome.sectionText,
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
                size: 22,
                color: chrome.sectionText.withValues(alpha: 0.6),
              ),
            ],
          ],
        ),
      ),
    );

    if (!enabled) {
      row = Opacity(opacity: 0.45, child: row);
    }
    if (onTap == null && onLongPress == null) {
      return Semantics(container: true, label: title, child: row);
    }
    return InkWell(
      onTap: enabled ? onTap : null,
      onLongPress: enabled ? onLongPress : null,
      child: row,
    );
  }
}

/// iOS 樣式開關，開啟色為主色。
class GroupedSwitch extends StatelessWidget {
  const GroupedSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CupertinoSwitch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: AppChrome.of(context).separator,
    );
  }
}

/// 帶開關的列；點整列也會切換。
class GroupedSwitchRow extends StatelessWidget {
  const GroupedSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onChanged != null;
    return MergeSemantics(
      child: GroupedRow(
        title: title,
        subtitle: subtitle,
        leading: leading,
        enabled: enabled,
        showChevron: false,
        onTap: active ? () => onChanged!(!value) : null,
        trailing: GroupedSwitch(
          value: value,
          onChanged: active ? onChanged : null,
        ),
      ),
    );
  }
}

/// 單選清單的一列：選中時右側打勾（取代 Radio）。
class GroupedCheckRow extends StatelessWidget {
  const GroupedCheckRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: GroupedRow(
        title: title,
        subtitle: subtitle,
        leading: leading,
        enabled: enabled,
        showChevron: false,
        onTap: onTap,
        trailing: SizedBox(
          width: 22,
          child:
              selected
                  ? Icon(
                    Icons.check_rounded,
                    size: 22,
                    color: Theme.of(context).colorScheme.primary,
                  )
                  : null,
        ),
      ),
    );
  }
}

/// 卡片內的自由內容（數值步進器、色票、預覽等），套用列的內距。
class GroupedContent extends StatelessWidget {
  const GroupedContent({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppGrouped.rowPadding,
      vertical: AppSpacing.md,
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: padding, child: child);
  }
}

/// 分組卡片內的單行輸入列（Telegram ItemListSingleLineInputItem）。
class GroupedTextFieldRow extends StatelessWidget {
  const GroupedTextFieldRow({
    super.key,
    this.label,
    this.controller,
    this.hintText,
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.style,
    this.autofocus = false,
    this.obscureText = false,
    this.suffix,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  /// 左側固定標籤；為 null 時輸入框佔滿整列。
  final String? label;
  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int? maxLines;
  final int? minLines;
  final TextStyle? style;
  final bool autofocus;
  final bool obscureText;
  final Widget? suffix;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final scheme = Theme.of(context).colorScheme;
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      autofocus: autofocus,
      obscureText: obscureText,
      style:
          style ??
          AppTextStyles.bodyBase.copyWith(height: 1.3, color: scheme.onSurface),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        hintText: hintText,
        hintStyle: AppTextStyles.bodyBase.copyWith(
          height: 1.3,
          color: chrome.sectionText.withValues(alpha: 0.7),
        ),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(
          minWidth: AppGrouped.rowMinHeight,
          minHeight: AppGrouped.rowMinHeight,
        ),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppGrouped.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppGrouped.rowPadding),
        child:
            label == null
                ? field
                : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: SizedBox(
                        width: 96,
                        child: Text(
                          label!,
                          style: AppTextStyles.bodyBase.copyWith(
                            height: 1.3,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: field),
                  ],
                ),
      ),
    );
  }
}

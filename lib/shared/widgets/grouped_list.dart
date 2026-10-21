import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../navigation/app_page_transition.dart';
import '../navigation/transition_settled.dart';
import '../theme/app_chrome.dart';
import '../theme/app_haptics.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_tokens.dart';
import 'cover_reveal.dart';
import 'grouped_list_skeleton.dart';
import 'press_ink.dart';
import 'skeleton.dart';
import 'swipe_actions.dart';

/// Telegram 式分組清單的一組：上方組標題、圓角卡片、下方附註。
///
/// 列與列之間自動插入髮絲分隔線；有任一列（[GroupedRowLike]，可包在
/// [SwipeActions]、[KeyedSubtree] 或單子元件的外框內）帶列首圖示時，分隔線
/// 從文字起點開始。分組本身帶上方間距，連續排列即可。
class GroupedSection extends StatelessWidget {
  const GroupedSection({
    super.key,
    this.header,
    this.headerTrailing,
    this.footer,
    required this.children,
    this.separatorIndent,
    this.margin,
    this.topGap = AppGrouped.sectionGap,
  });

  final String? header;

  /// 組標題右側的動作（例如「全部清除」）。
  final Widget? headerTrailing;

  /// 卡片下方的附註，只放狀態或數值（例如最近更新時間），不放功能說明（ADR 0009）。
  final String? footer;
  final List<Widget> children;

  /// 覆寫分隔線左縮排（列首不是 [GroupedIconTile] 寬度時使用）。
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
        (children.any(groupedRowHasLeading)
            ? AppGrouped.separatorIndentWithIcon
            : AppGrouped.rowPadding);
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(InsetSeparator(indent: indent));
      rows.add(children[i]);
    }
    final effectiveMargin =
        margin ?? const EdgeInsets.symmetric(horizontal: AppGrouped.margin);

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
                  ?headerTrailing,
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
          if (footer case final footer?)
            Padding(
              padding: effectiveMargin.add(
                const EdgeInsets.fromLTRB(
                  AppGrouped.rowPadding,
                  AppSpacing.sm,
                  AppGrouped.rowPadding,
                  0,
                ),
              ),
              child: Text(
                footer,
                style: AppTextStyles.bodySm.copyWith(color: chrome.sectionText),
              ),
            ),
        ],
      ),
    );
  }
}

/// 惰性清單中的一列分組卡片切片。
///
/// [GroupedSection] 一次建出所有列；書源、章節這類可能上百列的清單改由
/// builder 逐列建立，每列自己畫出卡片的對應段落：第一列帶上圓角、最後一列
/// 帶下圓角，其餘列上方畫髮絲分隔線；連起來與 [GroupedSection] 的卡片一致。
class GroupedSliceItem extends StatelessWidget {
  const GroupedSliceItem({
    super.key,
    required this.index,
    required this.count,
    required this.child,
    this.separatorIndent = AppGrouped.rowPadding,
  });

  final int index;
  final int count;
  final Widget child;
  final double separatorIndent;

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final first = index == 0;
    final last = index == count - 1;
    const corner = Radius.circular(AppGrouped.radius);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppGrouped.margin),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: first ? corner : Radius.zero,
          bottom: last ? corner : Radius.zero,
        ),
        child: Material(
          color: chrome.groupedSurface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!first) InsetSeparator(indent: separatorIndent),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// 從 [indent] 起畫的髮絲分隔線；分組卡片與平鋪清單（搜尋結果、發現書籍）
/// 的列間共用。
class InsetSeparator extends StatelessWidget {
  const InsetSeparator({super.key, required this.indent});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: Container(
        height: AppGlass.hairline,
        color: AppChrome.of(context).separator,
      ),
    );
  }
}

/// 分組卡片內的一列；[GroupedSection] 依 [hasLeading] 決定分隔線縮排。
/// 包裝 [GroupedRow] 的元件（開關列、勾選列、頁面私有的列）實作此介面。
abstract interface class GroupedRowLike {
  /// 是否帶列首圖示。
  bool get hasLeading;
}

/// 穿過常見外框（滑動動作、key、單子元件）找出列本身，判斷是否帶列首圖示。
bool groupedRowHasLeading(Widget widget) => switch (widget) {
  GroupedRowLike row => row.hasLeading,
  SwipeActions(:final child) => groupedRowHasLeading(child),
  KeyedSubtree(:final child) => groupedRowHasLeading(child),
  ProxyWidget(:final child) => groupedRowHasLeading(child),
  SingleChildRenderObjectWidget(:final child?) => groupedRowHasLeading(child),
  _ => false,
};

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
///
/// 每個子元件（通常是一組 [GroupedSection]）是清單的一項，捲到才建。
///
/// 掛上時頁面還在進場（推入的頁面），先只畫骨架（[GroupedListSkeleton]，
/// 整個畫面一個元件），換頁的第一格不建任何一列；進場播完的下一格才在骨架
/// 底下一格建一組（[CoverRevealSlot]），都建好再照骨架換場換成內容
/// （ADR 0029）。不是在進場中掛上的（分頁、已經在畫面上的頁面）直接建內容。
class GroupedListView extends StatefulWidget {
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
  State<GroupedListView> createState() => _GroupedListViewState();
}

class _GroupedListViewState extends State<GroupedListView> {
  /// 掛上時所在的頁面還在進場；之後一直走骨架這條路（換掉會讓內容重建）。
  bool? _entering;

  /// 進場播完的下一格才變 false。
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entering != null) return;
    final route = pageRouteOf(context);
    final entering = _entering =
        route != null &&
        (route.offstage || !(route.animation?.isCompleted ?? true));
    if (!entering) return;
    TransitionSettled.entered(context).then((_) async {
      // 進場最後一格之後再開始建內容，不和換頁擠在同一格。
      await SchedulerBinding.instance.endOfFrame;
      if (mounted) setState(() => _loading = false);
    });
  }

  /// 這一頁的版面紀錄 key 與每一項的樣子（記下的，沒有就估）。
  (String, List<GroupedItemShape>) _shapes() {
    final scaler = MediaQuery.textScalerOf(context);
    final key = GroupedListLayouts.keyOf(
      widget.children,
      MediaQuery.sizeOf(context).width,
      scaler,
    );
    final known = GroupedListLayouts.of(key);
    final width = MediaQuery.sizeOf(context).width;
    final direction = Directionality.of(context);
    return (
      key,
      [
        for (var i = 0; i < widget.children.length; i++)
          (known != null && i < known.length ? known[i] : null) ??
              GroupedItemShape.estimate(
                widget.children[i],
                width: width,
                scaler: scaler,
                direction: direction,
              ),
      ],
    );
  }

  /// 換成內容時記下畫面上各項排好的樣子，下次進這一頁的骨架照它畫。
  void _remember(String key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final shapes = List<GroupedItemShape?>.of(
        GroupedListLayouts.of(key) ??
            List<GroupedItemShape?>.filled(widget.children.length, null),
      );
      if (shapes.length != widget.children.length) return;
      void visit(Element element) {
        if (element.widget case _GroupedListSlot(:final index, :final item)) {
          if (index < shapes.length) {
            shapes[index] =
                GroupedItemShape.measure(element, item) ?? shapes[index];
          }
          return;
        }
        element.visitChildren(visit);
      }

      (context as Element).visitChildren(visit);
      GroupedListLayouts.remember(key, shapes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final padding = EdgeInsets.only(
      top: mediaPadding.top,
      bottom: mediaPadding.bottom + widget.bottomPadding,
    );
    final chrome = AppChrome.of(context);
    final background = chrome.groupedBackground;
    if (_entering != true) {
      return ColoredBox(
        color: background,
        child: ListView(
          controller: widget.controller,
          physics: widget.physics,
          padding: padding,
          children: widget.children,
        ),
      );
    }
    final (key, shapes) = _shapes();
    return ColoredBox(
      color: background,
      child: SkeletonSwitcher(
        loading: _loading,
        waitForCovers: true,
        backdrop: background,
        onRevealed: () => _remember(key),
        skeleton: GroupedListSkeleton(
          shapes: shapes,
          top: padding.top,
          cardFill: chrome.groupedSurface,
        ),
        builder: (context) => ListView(
          controller: widget.controller,
          physics: widget.physics,
          padding: padding,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              _GroupedListSlot(
                key: _slotKey(widget.children[i]),
                index: i,
                shape: shapes[i],
                item: widget.children[i],
              ),
          ],
        ),
      ),
    );
  }
}

/// 清單的一項：骨架底下輪到才建，之前佔著記下或估計的高度。一組分組卡片
/// 以列為單位排隊（組標題文字與卡片外框先建），一格建一列：像「排版」這樣一組
/// 八列步進的組整組一起建，在電腦的 debug 模式要 50ms 以上。
class _GroupedListSlot extends StatelessWidget {
  const _GroupedListSlot({
    super.key,
    required this.index,
    required this.shape,
    required this.item,
  });

  final int index;
  final GroupedItemShape shape;
  final Widget item;

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    final rows = shape.rowHeights;
    if (item is! GroupedSection ||
        rows == null ||
        rows.length != item.children.length) {
      return CoverRevealSlot(
        placeholder: SizedBox(height: shape.height),
        child: item,
      );
    }
    return GroupedSection(
      key: item.key,
      header: item.header,
      // 組標題右側的按鈕（「恢復預設」）也排隊，不和卡片外框擠在同一格。
      headerTrailing: switch (item.headerTrailing) {
        final trailing? => CoverRevealSlot(child: trailing),
        null => null,
      },
      footer: item.footer,
      // 列包了一層，自動判斷列首圖示看不到列本身，先照原本的列算好。
      separatorIndent:
          item.separatorIndent ??
          (item.children.any(groupedRowHasLeading)
              ? AppGrouped.separatorIndentWithIcon
              : AppGrouped.rowPadding),
      margin: item.margin,
      topGap: item.topGap,
      children: [
        for (var i = 0; i < rows.length; i++)
          CoverRevealSlot(
            key: _slotKey(item.children[i]),
            placeholder: SizedBox(height: rows[i]),
            child: item.children[i],
          ),
      ],
    );
  }
}

/// 包著 [child] 的那一層沿用它的 key（列有 key 時，增刪重排照樣對得上）；
/// 包一層 [ValueKey]，[GlobalKey] 才不會用到兩次。
Key? _slotKey(Widget child) => switch (child.key) {
  final key? => ValueKey<Key>(key),
  null => null,
};

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
class GroupedRow extends StatelessWidget implements GroupedRowLike {
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

  @override
  bool get hasLeading => leading != null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = AppChrome.of(context);
    final titleColor = destructive
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
                          fontWeight: accent
                              ? FontWeight.w500
                              : FontWeight.w400,
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
      // 標題文字本來就會併進這個節點，再設 label 讀屏會念成「標題、標題、值」。
      return Semantics(container: true, child: row);
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
        child: Opacity(opacity: enabled ? 1 : 0.38, child: track),
      ),
    );
  }
}

/// 帶開關的列；點整列也會切換。
class GroupedSwitchRow extends StatelessWidget implements GroupedRowLike {
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

  @override
  Widget build(BuildContext context) {
    final active = enabled && onChanged != null;
    return MergeSemantics(
      child: GroupedRow(
        title: title,
        leading: leading,
        enabled: enabled,
        showChevron: false,
        onTap: active ? () => GroupedSwitch.toggle(value, onChanged!) : null,
        trailing: GroupedSwitch(
          value: value,
          onChanged: active ? onChanged : null,
        ),
      ),
    );
  }
}

/// 單選清單的一列：選中時右側打勾（取代 Radio）。
class GroupedCheckRow extends StatelessWidget implements GroupedRowLike {
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
  bool get hasLeading => leading != null;

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
          child: selected
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
    this.labelWidth = 96,
    this.validator,
    this.errorText,
  });

  /// 左側固定標籤；為 null 時輸入框佔滿整列。
  final String? label;

  /// 標籤欄寬度。
  final double labelWidth;

  /// 放在 [Form] 內時的驗證；提供時改用 [TextFormField]，錯誤文字顯示在
  /// 輸入框下方。
  final FormFieldValidator<String>? validator;

  /// 外部指定的錯誤文字（不經 [Form] 驗證時使用）。
  final String? errorText;
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
    final decoration = InputDecoration(
      isDense: true,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      errorText: errorText,
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
    );
    final effectiveStyle =
        style ??
        AppTextStyles.bodyBase.copyWith(height: 1.3, color: scheme.onSurface);
    final effectiveMaxLines = obscureText ? 1 : maxLines;
    final field = validator == null
        ? TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            maxLines: effectiveMaxLines,
            minLines: minLines,
            autofocus: autofocus,
            obscureText: obscureText,
            style: effectiveStyle,
            decoration: decoration,
          )
        : TextFormField(
            controller: controller,
            focusNode: focusNode,
            validator: validator,
            onChanged: onChanged,
            onFieldSubmitted: onSubmitted,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            maxLines: effectiveMaxLines,
            minLines: minLines,
            autofocus: autofocus,
            obscureText: obscureText,
            style: effectiveStyle,
            decoration: decoration,
          );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppGrouped.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppGrouped.rowPadding),
        child: label == null
            ? field
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: SizedBox(
                      width: labelWidth,
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

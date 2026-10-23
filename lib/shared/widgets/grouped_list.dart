import 'dart:math' as math;

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

  /// 組標題的字樣；骨架照同一份字樣量組標題的高度。
  static TextStyle textStyle(BuildContext context) =>
      AppTextStyles.uiSm.copyWith(
        color: AppChrome.of(context).sectionText,
        fontWeight: FontWeight.w400,
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(text, style: textStyle(context)),
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
    final mediaPadding = MediaQuery.paddingOf(context);
    final padding = EdgeInsets.only(
      top: mediaPadding.top,
      bottom: mediaPadding.bottom + bottomPadding,
    );
    return _GroupedEntrance(
      items: children,
      padding: padding,
      background: AppChrome.of(context).groupedBackground,
      builder: (context, items) => ListView(
        controller: controller,
        physics: physics,
        padding: padding,
        children: items,
      ),
    );
  }
}

/// 頁面與面板共用的進場：先骨架、進場播完才在骨架底下逐列建立，再一次
/// 換成內容。[builder] 照原本的捲動方式與內距排 [items]（還在排隊的項目
/// 換成佔位）；面板以 [StackFit.loose] 照內容的高度收縮。
class _GroupedEntrance extends StatefulWidget {
  const _GroupedEntrance({
    required this.items,
    required this.padding,
    required this.background,
    required this.builder,
    this.fit = StackFit.expand,
  });

  final List<Widget> items;
  final EdgeInsets padding;
  final Color background;
  final Widget Function(BuildContext context, List<Widget> items) builder;
  final StackFit fit;

  @override
  State<_GroupedEntrance> createState() => _GroupedEntranceState();
}

/// 閱讀器面板這類照內容收縮的底部面板的捲動內容：和 [GroupedListView]
/// 一樣滑入時先只畫骨架，滑到位才逐列建立；骨架的高度照每一項的樣子算
/// （[GroupedItemShape.of]），換成內容時面板高度不變。
class GroupedSheetContent extends StatelessWidget {
  const GroupedSheetContent({
    super.key,
    required this.children,
    required this.padding,
    required this.background,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final Color background;

  @override
  Widget build(BuildContext context) => _GroupedEntrance(
    items: children,
    padding: padding,
    background: background,
    fit: StackFit.loose,
    builder: (context, items) => SingleChildScrollView(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items,
      ),
    ),
  );
}

class _GroupedEntranceState extends State<_GroupedEntrance> {
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

  /// 換成內容的那一刻；之後骨架用不到，樣子不再重算。
  bool _revealed = false;

  /// 上一次算好的樣子，以及算的時候的寬度、字級與項目。
  List<GroupedItemShape>? _cached;
  (double, double, List<Widget>)? _cachedFor;

  /// 每一項的樣子（[GroupedItemShape.of]）。骨架還在時，寬度、字級或項目
  /// 變了才重算；換成內容後只有項目數變了（例如多出測試結果）才補算，
  /// 鍵盤升降、面板重建都不再重排骨架的字。面板的高度就是骨架的高度，
  /// 每一項照它本身算，第一次打開就是換上內容後的高度。
  List<GroupedItemShape> _shapes(double width) {
    final items = widget.items;
    final scale = MediaQuery.textScalerOf(context).scale(100);
    final cached = _cached;
    if (cached != null) {
      final (cachedWidth, cachedScale, cachedItems) = _cachedFor!;
      final same = _revealed
          ? cached.length == items.length
          : cachedWidth == width &&
                cachedScale == scale &&
                identical(cachedItems, items);
      if (same) return cached;
    }
    _cachedFor = (width, scale, items);
    return _cached = [
      for (final item in items)
        GroupedItemShape.of(item, context: context, width: width),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AppChrome.of(context);
    final background = widget.background;
    if (_entering != true) {
      return ColoredBox(
        color: background,
        child: widget.builder(context, widget.items),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = widget.padding;
        final shapes = _shapes(constraints.maxWidth - padding.horizontal);
        // 只有實際視窗裡的列排隊；面板不能借用整個螢幕的高度。
        final visible = <double>[];
        var height = padding.top;
        for (final shape in shapes) {
          visible.add(constraints.maxHeight - height);
          height += shape.height;
        }
        height += padding.bottom;
        Widget skeleton = Padding(
          padding: EdgeInsets.only(left: padding.left, right: padding.right),
          child: GroupedListSkeleton(
            shapes: shapes,
            top: padding.top,
            cardFill: chrome.groupedSurface,
          ),
        );
        if (widget.fit == StackFit.loose) {
          skeleton = SizedBox(height: height, child: skeleton);
        }
        return ColoredBox(
          color: background,
          child: SkeletonSwitcher(
            fit: widget.fit,
            loading: _loading,
            waitForCovers: CoverWait.brief,
            backdrop: background,
            onRevealed: () => _revealed = true,
            skeleton: skeleton,
            builder: (context) => widget.builder(context, [
              for (final (i, item) in widget.items.indexed)
                _GroupedListSlot(
                  key: _slotKey(item),
                  index: i,
                  shape: shapes[i],
                  visible: visible[i],
                  item: item,
                ),
            ]),
          ),
        );
      },
    );
  }
}

/// 清單的一項：骨架底下輪到才建，之前佔著骨架算好的高度。一組分組卡片
/// 以列為單位排隊（組標題文字與卡片外框先建），一格建一列：像「排版」這樣一組
/// 八列步進的組整組一起建，在電腦的 debug 模式要 50ms 以上。只有第一個畫面
/// 裡的列排隊；畫面外的列（替換規則、下載佇列這類上百列的組）和組一起建、
/// 換場不等它們，不然一列一格，兩百列要等三秒以上。
class _GroupedListSlot extends StatelessWidget {
  const _GroupedListSlot({
    super.key,
    required this.index,
    required this.shape,
    required this.visible,
    required this.item,
  });

  final int index;
  final GroupedItemShape shape;

  /// 這一項上緣到畫面底的距離；不到 0 時整項都在畫面外。
  final double visible;
  final Widget item;

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    final rows = shape.rowHeights;
    if (item is! GroupedSection ||
        rows == null ||
        rows.length != item.children.length) {
      return CoverRevealSlot(
        wait: visible > 0,
        placeholder: SizedBox(height: shape.height),
        child: item,
      );
    }
    return GroupedSection(
      key: item.key,
      header: item.header,
      // 組標題右側的按鈕（「恢復預設」）也排隊，不和卡片外框擠在同一格。
      headerTrailing: switch (item.headerTrailing) {
        final trailing? => CoverRevealSlot(wait: visible > 0, child: trailing),
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
      children: _rows(item.children, rows),
    );
  }

  List<Widget> _rows(List<Widget> children, List<double> heights) {
    final out = <Widget>[];
    var top = shape.card?.top ?? 0;
    for (var i = 0; i < children.length; i++) {
      out.add(
        CoverRevealSlot(
          key: _slotKey(children[i]),
          placeholder: SizedBox(height: heights[i]),
          wait: top < visible,
          child: children[i],
        ),
      );
      top += heights[i] + AppGlass.hairline;
    }
    return out;
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
class GroupedRow extends StatelessWidget
    implements GroupedRowLike, GroupedSkeletonItem {
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
    this.maxTitleLines,
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

  /// 標題最多幾行，超過以「…」截斷；null 時照寬度換行。右側的字會之後才
  /// 讀到、或同一列會換成另一個標題時，設成 1 讓列高不跟著字變。
  final int? maxTitleLines;

  @override
  bool get hasLeading => leading != null;

  /// 標題與右側數值的字樣、副標的字樣；骨架照同一份排。
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
      parts.add((right, _glyphShape(_chevronSize)));
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
    final title = GroupedItemShape.text(
      context,
      this.title,
      style: _textStyle.copyWith(
        fontWeight: accent ? FontWeight.w500 : FontWeight.w400,
      ),
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
                        maxLines: maxTitleLines,
                        overflow: maxTitleLines == null
                            ? null
                            : TextOverflow.ellipsis,
                        style: _textStyle.copyWith(
                          color: titleColor,
                          fontWeight: accent
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: _subtitleGap),
                    Text(
                      subtitle!,
                      maxLines: maxSubtitleLines,
                      overflow: TextOverflow.ellipsis,
                      style: _subtitleStyle.copyWith(color: chrome.sectionText),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: AppSpacing.md),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _valueMaxWidth(context)),
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: _textStyle.copyWith(color: chrome.sectionText),
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

/// 列首、右側控件與組標題右側按鈕這類不撐滿的小元件的骨架，
/// [GroupedItemShape.width] 是它佔的寬：圖示方塊、開關整塊，圖示是和字形
/// 一樣大的方塊，定了大小的 [SizedBox] 照它的大小、裡面的圖示或色塊置中；
/// 其他的元件實作 [GroupedSkeletonItem] 並給出寬度。
GroupedItemShape groupedPartShape(Widget widget, BuildContext context) {
  GroupedItemShape box(Size size, BorderRadius radius) => GroupedItemShape(
    size.height,
    width: size.width,
    marks: [SkeletonShape(Offset.zero & size, radius: radius)],
  );
  switch (widget) {
    case final GroupedSkeletonItem shaped:
      final shape = shaped.skeletonShape(context, width: double.infinity);
      if (shape.width != null) return shape;
    case GroupedIconTile():
      return box(
        const Size.square(AppGrouped.iconTile),
        BorderRadius.circular(AppGrouped.iconTileRadius),
      );
    case GroupedSwitch():
      return box(
        const Size(GroupedSwitch.trackWidth, GroupedSwitch.trackHeight),
        AppRadius.pillShape,
      );
    case Icon(:final size):
      return _glyphShape(size ?? IconTheme.of(context).size ?? 24);
    case Text(:final data?, :final style, :final maxLines):
      return GroupedItemShape.text(
        context,
        data,
        style: style ?? const TextStyle(),
        width: double.infinity,
        maxLines: maxLines,
      );
    // 限寬的字（右側的狀態文字）照最寬的寬度排。
    case ConstrainedBox(
      :final constraints,
      child: Text(:final data?, :final style, :final maxLines),
    ):
      return GroupedItemShape.text(
        context,
        data,
        style: style ?? const TextStyle(),
        width: constraints.maxWidth,
        maxLines: maxLines,
      );
    case CircularProgressIndicator():
      return box(
        const Size.square(_spinnerSize),
        BorderRadius.circular(_spinnerSize / 2),
      );
    case SizedBox(:final width?, :final height, :final child):
      final inner = switch (child) {
        null => null,
        DecoratedBox(:final BoxDecoration decoration)
            when decoration.color != null =>
          box(
            Size(width, height ?? 0),
            decoration.shape == BoxShape.circle
                ? BorderRadius.circular(math.min(width, height ?? 0) / 2)
                : decoration.borderRadius?.resolve(
                        Directionality.of(context),
                      ) ??
                      BorderRadius.zero,
          ),
        _ => groupedPartShape(child, context),
      };
      final size = Size(width, height ?? inner?.height ?? 0);
      return GroupedItemShape(
        size.height,
        width: size.width,
        marks: [
          ...?inner?.marksAt(
            Offset(
              (size.width - inner.width!) / 2,
              (size.height - inner.height) / 2,
            ),
          ),
        ],
      );
    default:
  }
  assert(
    false,
    '${widget.runtimeType} 算不出骨架：讓它實作 GroupedSkeletonItem 並給出寬度'
    '（ADR 0029）',
  );
  return const GroupedItemShape(0, width: 0);
}

/// [CircularProgressIndicator] 沒給大小時的直徑（Material 的最小尺寸）。
const double _spinnerSize = 36;

/// [Icon] 的骨架：字形撐滿 [size] 見方（[Icon] 的行高是 1），畫成和字條
/// 一樣圓角的方塊。
GroupedItemShape _glyphShape(double size) => GroupedItemShape(
  size,
  width: size,
  marks: [
    SkeletonShape(
      Rect.fromLTWH(0, 0, size, size),
      radius: BorderRadius.circular(size / 4),
    ),
  ],
);

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
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  bool get hasLeading => leading != null;

  static const double _checkSize = 22;

  GroupedRow _row(BuildContext context) => GroupedRow(
    title: title,
    subtitle: subtitle,
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
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: _row(context),
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

/// [TextField] 實際用的字樣：先合併 Material 的輸入字體再套 [style]；骨架
/// 也從這份字體量行高，不能只用字號乘行高（不同字體的 strut 會得到不同
/// 整數行高）。
TextStyle groupedInputStyle(BuildContext context, TextStyle style) {
  final theme = Theme.of(context);
  return (theme.useMaterial3
          ? theme.textTheme.bodyLarge!
          : theme.textTheme.titleMedium!)
      .merge(style);
}

/// 輸入框裡字的那一塊（不含輸入框的內距）。行數固定（最少與最多一樣）的
/// 框只看行數，每一行撐滿一條：字可能之後才填進來；行數會變的框照現在的
/// 字 [text] 排，畫框裡會顯示的字（沒字時是提示字 [hint]）。[style] 是
/// [groupedInputStyle] 合併過的字樣。
GroupedItemShape groupedTextFieldShape(
  BuildContext context, {
  required TextStyle style,
  required double width,
  required String text,
  String? hint,
  TextStyle? hintStyle,
  int? maxLines,
  int? minLines,
}) {
  final scaler = MediaQuery.textScalerOf(context);
  final fixed = maxLines != null && (minLines ?? 1) == maxLines;
  final painter = TextPainter(
    text: TextSpan(text: fixed ? '' : text, style: style),
    strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
    textScaler: scaler,
    textDirection: Directionality.of(context),
  )..layout(maxWidth: math.max(0, width));
  final line = painter.preferredLineHeight;
  final fontSize = scaler.scale(
    style.fontSize ?? AppTextStyles.bodyBase.fontSize!,
  );
  final lower = line * (minLines ?? maxLines ?? 1);
  final upper = maxLines == null ? double.infinity : line * maxLines;
  final height = fixed ? line * maxLines : painter.height.clamp(lower, upper);
  painter.dispose();
  if (fixed && minLines != null) {
    // 指定了固定行數的框，字之後才填進來：每一行撐滿一條。
    return GroupedItemShape(
      height,
      marks: [
        for (var i = 0; i < maxLines; i++)
          SkeletonShape(
            Rect.fromLTWH(0, i * line + (line - fontSize) / 2, width, fontSize),
          ),
      ],
    );
  }
  // 照框裡會顯示的字畫：有字畫字，沒字畫提示字（提示字的行高不同，置中在
  // 輸入的那一行上）。
  final shown = switch ((text, hint)) {
    (final text, _) when text.isNotEmpty => GroupedItemShape.text(
      context,
      text,
      style: style,
      width: width,
      maxLines: maxLines,
      strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
    ),
    (_, final hint?) when hint.isNotEmpty => () {
      final shape = GroupedItemShape.text(
        context,
        hint,
        style: style.merge(hintStyle),
        width: width,
        maxLines: maxLines,
      );
      return GroupedItemShape(
        shape.height,
        marks: shape.marksAt(Offset(0, (line - shape.height) / 2)),
      );
    }(),
    _ => null,
  };
  return GroupedItemShape(height, marks: shown?.marks ?? const []);
}

/// 分組卡片內的單行輸入列（Telegram ItemListSingleLineInputItem）。
class GroupedTextFieldRow extends StatelessWidget
    implements GroupedSkeletonItem {
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

  static final TextStyle _labelStyle = AppTextStyles.bodyBase.copyWith(
    height: 1.3,
  );

  static final TextStyle _hintStyle = AppTextStyles.bodyBase.copyWith(
    height: 1.3,
  );

  /// 標籤照字排在左欄，輸入框見 [groupedTextFieldShape]。
  @override
  GroupedItemShape skeletonShape(
    BuildContext context, {
    required double width,
  }) {
    final labelWidth = this.label == null ? 0.0 : this.labelWidth;
    final field = groupedTextFieldShape(
      context,
      style: _textStyle(context),
      width: width - AppGrouped.rowPadding * 2 - labelWidth,
      text: controller?.text ?? '',
      hint: hintText,
      hintStyle: _hintStyle,
      maxLines: _maxLines,
      minLines: minLines,
    );
    final label = switch (this.label) {
      final text? => GroupedItemShape.text(
        context,
        text,
        style: _labelStyle,
        width: labelWidth,
      ),
      null => null,
    };
    // 標籤只有上方內距，輸入框上下都有。
    final height = math.max(
      AppGrouped.rowMinHeight,
      math.max(
        field.height + AppSpacing.md * 2,
        AppSpacing.md + (label?.height ?? 0),
      ),
    );
    return GroupedItemShape(
      height,
      marks: [
        ...?label?.marksAt(const Offset(AppGrouped.rowPadding, AppSpacing.md)),
        ...field.marksAt(
          Offset(AppGrouped.rowPadding + labelWidth, AppSpacing.md),
        ),
      ],
    );
  }

  /// 輸入框實際的最多行數（密碼只有一行）；骨架與 build 共用。
  int? get _maxLines => obscureText ? 1 : maxLines;

  TextStyle _textStyle(BuildContext context) => groupedInputStyle(
    context,
    style ??
        AppTextStyles.bodyBase.copyWith(
          height: 1.3,
          color: Theme.of(context).colorScheme.onSurface,
        ),
  );

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
      hintStyle: _hintStyle.copyWith(
        color: chrome.sectionText.withValues(alpha: 0.7),
      ),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(
        minWidth: AppGrouped.rowMinHeight,
        minHeight: AppGrouped.rowMinHeight,
      ),
    );
    final effectiveStyle = _textStyle(context);
    final effectiveMaxLines = _maxLines;
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
                        style: _labelStyle.copyWith(color: scheme.onSurface),
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

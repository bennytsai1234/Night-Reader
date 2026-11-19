/// @docImport '../glass/glass.dart';
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/scheduler.dart';

import '../../../core/chinese/ui_language.dart';
import '../../layout/readable_width.dart';
import '../../navigation/app_page_transition.dart';
import '../../navigation/transition_origin.dart';
import '../../navigation/transition_settled.dart';
import '../../theme/app_chrome.dart';
import '../../theme/app_tokens.dart';
import '../skeleton/cover_reveal.dart';
import '../skeleton/grouped_list_skeleton.dart';
import '../skeleton/skeleton.dart';
import 'grouped_section.dart';

export 'grouped_row.dart';
export 'grouped_section.dart';
export 'grouped_text_field_row.dart';

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
    this.ready = true,
    this.loadingLabel,
  });

  final List<Widget> children;

  /// 資料還沒準備好時，進場骨架繼續顯示；資料到了才用最後的列形狀換場。
  /// 只影響推入頁面的進場，已在畫面上的清單直接顯示內容。資料到了要沿用
  /// 同一個 [GroupedListView]（只改 ready 與 [children]）：換成別的元件，
  /// 進場骨架會整個重建、不換場。
  final bool ready;

  /// 還沒 [ready] 時螢幕閱讀器讀的話（例如「正在載入更新紀錄」）。給了的話
  /// 這段期間 [children] 是只給骨架量形狀的佔位，不讀出來。
  final String? loadingLabel;
  final ScrollController? controller;
  final double bottomPadding;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final padding =
        EdgeInsets.only(
          top: mediaPadding.top,
          bottom: mediaPadding.bottom + bottomPadding,
        ) +
        ReadableWidth.insetOf(context);
    final placeholder = !ready && loadingLabel != null;
    // 準備好前後都是同一串元件，只改屬性，進場的狀態才留得住。
    return Semantics(
      liveRegion: placeholder,
      label: placeholder
          ? UiLanguageText.convertNullable(context, loadingLabel)
          : null,
      child: ExcludeSemantics(
        excluding: placeholder,
        child: _GroupedEntrance(
          items: children,
          ready: ready,
          padding: padding,
          background: AppChrome.of(context).groupedBackground,
          builder: (context, items) => ListView(
            controller: controller,
            physics: physics,
            padding: padding,
            children: items,
          ),
        ),
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
    this.ready = true,
    this.fit = StackFit.expand,
  });

  final List<Widget> items;
  final bool ready;
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

  /// 進場播完的下一格才允許換場；若資料仍未就緒，骨架繼續顯示。
  bool _entranceFinished = false;

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
      if (mounted) setState(() => _entranceFinished = true);
    });
  }

  /// 換成內容的那一刻；之後骨架用不到，樣子不再重算。
  bool _revealed = false;

  /// 上一次算好的樣子，以及算的時候的寬度、字級與項目。
  List<GroupedItemShape>? _cached;
  (double, double, double, List<Widget>)? _cachedFor;

  /// 每一項的樣子（[GroupedItemShape.of]）。骨架還在時，寬度、高度、字級或
  /// 項目變了才重算；換成內容後只有項目數變了（例如多出測試結果）才補算，
  /// 鍵盤升降、面板重建都不再重排骨架的字。面板的高度就是骨架的高度，
  /// 每一項照它本身算，第一次打開就是換上內容後的高度。撐滿畫面的頁面只算
  /// 到畫面底（[bottom]，從清單頂端算起）：再下面的骨架畫不到，那些項目也
  /// 不排隊等，和第一個畫面一起建，高度記 0。
  List<GroupedItemShape> _shapes(double width, double top, double bottom) {
    final items = widget.items;
    final scale = MediaQuery.textScalerOf(context).scale(100);
    final cached = _cached;
    if (cached != null) {
      final (cachedWidth, cachedBottom, cachedScale, cachedItems) = _cachedFor!;
      final same = _revealed
          ? cached.length == items.length
          : cachedWidth == width &&
                cachedBottom == bottom &&
                cachedScale == scale &&
                identical(cachedItems, items);
      if (same) return cached;
    }
    _cachedFor = (width, bottom, scale, items);
    final fill = widget.fit != StackFit.loose;
    final shapes = <GroupedItemShape>[];
    var y = top;
    for (final item in items) {
      if (fill && y >= bottom) {
        shapes.add(const GroupedItemShape(0));
        continue;
      }
      final shape = GroupedItemShape.of(
        item,
        context: context,
        width: width,
        until: fill ? bottom - y : double.infinity,
      );
      shapes.add(shape);
      y += shape.height;
    }
    return _cached = shapes;
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
        final shapes = _shapes(
          constraints.maxWidth - padding.horizontal,
          padding.top,
          constraints.maxHeight,
        );
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
            loading: !_entranceFinished || !widget.ready,
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
/// 八列步進的組整組一起建，在電腦的 debug 模式要 50ms 以上。第一個畫面裡
/// 的列，加上畫面底下清單本來就會先建好的那一段放得下的列數（[_queuedBelow]）
/// 排隊：一組跨在畫面底邊時，緊接在下面的幾列不和露出來的那一列擠在同一格。
/// 再往下的列（替換規則、下載佇列這類上百列的組）和組一起建、換場不等它們，
/// 不然一列一格，兩百列要等三秒以上。
class _GroupedListSlot extends StatelessWidget {
  /// 跨在畫面底邊的組，畫面外還排隊的列數：清單在畫面底下先建好的那一段
  /// （[RenderAbstractViewport.defaultCacheExtent]）放得下幾列最矮的列。
  static final int _queuedBelow =
      (RenderAbstractViewport.defaultCacheExtent / AppGrouped.rowMinHeight)
          .ceil();

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
    return item.withRows(
      _rows(item.children, rows),
      // 組標題右側的按鈕（「恢復預設」）也排隊，不和卡片外框擠在同一格。
      headerTrailing: switch (item.headerTrailing) {
        final trailing? => CoverRevealSlot(wait: visible > 0, child: trailing),
        null => null,
      },
    );
  }

  List<Widget> _rows(List<Widget> children, List<double> heights) {
    final out = <Widget>[];
    var top = shape.card?.top ?? 0;
    var below = 0;
    for (var i = 0; i < children.length; i++) {
      // 骨架只量到畫面底，再往下的列高度不知道，照列數算。
      final wait = top < visible || below++ < _queuedBelow;
      out.add(
        CoverRevealSlot(
          key: _slotKey(children[i]),
          placeholder: SizedBox(height: heights[i]),
          wait: wait,
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

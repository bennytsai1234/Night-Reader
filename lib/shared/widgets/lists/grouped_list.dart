import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, ScrollCacheExtent;
import 'package:flutter/scheduler.dart';

import '../../../core/chinese/ui_language.dart';
import '../../layout/readable_width.dart';
import '../../navigation/app_page_transition.dart';
import '../../navigation/transition_settled.dart';
import '../../theme/app_chrome.dart';
import '../../theme/app_tokens.dart';
import '../glass/glass.dart';
import '../skeleton/cover_reveal.dart';
import '../skeleton/grouped_list_skeleton.dart';
import '../skeleton/skeleton.dart';
import 'grouped_section.dart';

export 'grouped_help_row.dart';
export 'grouped_row.dart';
export 'grouped_section.dart';
export 'grouped_text_field_row.dart';

/// 分組清單頁面的捲動容器：分組底色、底部讓出系統區與浮動分頁列。
///
/// 第一項從哪裡開始見 [topOf]，第一組的上方間距見 [itemsOf]；各頁不用替
/// 第一組另給 `topGap`。自己畫骨架的頁面（例如書源登入）也照這兩個排。
///
/// 每個子元件（通常是一組 [GroupedSection]）是清單的一項，捲到才建。
///
/// 掛上時頁面還在進場（推入的頁面），先只畫骨架（[GroupedListSkeleton]，
/// 整個畫面一個元件），換頁的第一格不建任何一列；進場播完的下一格才在骨架
/// 底下建：組標題與卡片外框先建，畫面裡的列一格一列（[CoverRevealSlot]），
/// 都建好再照骨架換場換成內容
/// （ADR 0029）。畫面下面三個畫面以內的列，換場播完的下一格趁畫面靜止一次
/// 建好、留著（[_Prebuild]），手指捲過去時不必在那一幀整組建出來（ADR 0037
/// 策略四）。不是在進場中掛上的（分頁、已經在畫面上的頁面）直接建內容。
class GroupedListView extends StatelessWidget {
  const GroupedListView({
    super.key,
    required this.children,
    this.controller,
    this.bottomPadding = AppGrouped.sectionGap,
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

  /// 清單第一項的上緣，從清單頂端算：系統留的上方內距。頁面的內容延伸到
  /// [GlassNavHeader] 底下時，這段內距已經包含頁首與它下緣的淡出，第一項
  /// 剛好接在淡出的下面（docs/design/components.md「導航頁首」）。
  static double topOf(BuildContext context) =>
      MediaQuery.paddingOf(context).top;

  /// 清單的項目：第一項是一組時換成上方間距 0 的同一組，頁首到第一組只有
  /// [topOf] 那一段；骨架與內容都照換過的項目排。
  static List<Widget> itemsOf(List<Widget> children) => [
    for (final (i, child) in children.indexed)
      i == 0 && child is GroupedSection ? child.withTopGap(0) : child,
  ];

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final padding =
        EdgeInsets.only(
          top: topOf(context),
          bottom: mediaPadding.bottom + bottomPadding,
        ) +
        ReadableWidth.insetOf(context);
    final items = itemsOf(children);
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
          items: items,
          ready: ready,
          padding: padding,
          background: AppChrome.of(context).groupedBackground,
          // 包一層重畫邊界：畫面外的列建好時清單重新排版，畫面上的圖層照舊
          // （[_Prebuild]）。
          builder: (context, items) => RepaintBoundary(
            child: _PrebuildCacheExtent(
              builder: (context, cacheExtent) => ListView(
                controller: controller,
                physics: physics,
                padding: padding,
                scrollCacheExtent: cacheExtent,
                children: items,
              ),
            ),
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
    items: GroupedListView.itemsOf(children),
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

/// 分組清單的進場在哪一段（`docs/state-machines.md`「分組清單的進場」）。
enum _EntranceStage {
  /// 不是在進場中掛上的：直接畫內容。
  direct,

  /// 掛上時所在的頁面還在進場：只畫骨架，不建任何一列。
  entering,

  /// 進場播完的下一格起：資料好了就在骨架底下建好、換場；沒好骨架照舊。
  entered,

  /// 骨架換成內容了：骨架用不到，樣子不再照寬度、字級重算。
  revealed,
}

class _GroupedEntranceState extends State<_GroupedEntrance> {
  /// 第一次 [didChangeDependencies] 定下；走過骨架這條路的之後一直走它
  /// （換掉會讓內容重建）。
  _EntranceStage? _stage;

  /// 整組在畫面外的列，換場播完才建。
  final _Prebuild _prebuild = _Prebuild();

  @override
  void dispose() {
    _prebuild.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_stage != null) return;
    final route = pageRouteOf(context);
    final entering =
        route != null &&
        (route.offstage || !(route.animation?.isCompleted ?? true));
    _stage = entering ? _EntranceStage.entering : _EntranceStage.direct;
    if (!entering) return;
    TransitionSettled.entered(context).then((_) async {
      // 進場最後一格之後再開始建內容，不和換頁擠在同一格。
      await SchedulerBinding.instance.endOfFrame;
      if (mounted) setState(() => _stage = _EntranceStage.entered);
    });
  }

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
      final same = _stage == _EntranceStage.revealed
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
    final stage = _stage!;
    if (stage == _EntranceStage.direct) {
      return ColoredBox(
        color: background,
        child: widget.builder(context, widget.items),
      );
    }
    final fill = widget.fit != StackFit.loose;
    final entrance = LayoutBuilder(
      builder: (context, constraints) {
        final padding = widget.padding;
        final shapes = _shapes(
          constraints.maxWidth - padding.horizontal,
          padding.top,
          constraints.maxHeight,
        );
        // 只有實際視窗裡的列排隊；面板不能借用整個螢幕的高度。
        final visible = <double>[];
        // 每一項的第一列是整份清單的第幾列，先建好的列數照它設上限。
        final firstRow = <int>[];
        var height = padding.top;
        var rows = 0;
        for (final (i, shape) in shapes.indexed) {
          visible.add(constraints.maxHeight - height);
          height += shape.height;
          firstRow.add(rows);
          final item = widget.items[i];
          rows += item is GroupedSection ? item.children.length : 1;
        }
        final prebuildRows = _Prebuild.rowsFor(constraints.maxHeight);
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
        final content = ColoredBox(
          color: background,
          child: _PrebuildScope(
            prebuild: _prebuild,
            child: SkeletonSwitcher(
              fit: widget.fit,
              loading: stage == _EntranceStage.entering || !widget.ready,
              waitForCovers: CoverWait.brief,
              backdrop: background,
              // 不重建：換成內容的這一格已經畫好，骨架的樣子下次才用得到。
              // 畫面外的列等換場收掉骨架的那一格畫完、畫面靜止了才建：
              // 和收掉骨架擠在同一格，那一格畫面在變。
              onRevealed: () {
                _stage = _EntranceStage.revealed;
                SchedulerBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _prebuild.release();
                  // 列建好的下一格，清單多建的範圍才縮回預設
                  // （[_PrebuildCacheExtent]）：同一格縮的話，捲出範圍
                  // 的項目先收起來，裡面的列要等捲回來才建。
                  SchedulerBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _prebuild.settle();
                  });
                });
              },
              skeleton: skeleton,
              builder: (context) => widget.builder(context, [
                for (final (i, item) in widget.items.indexed)
                  _GroupedListSlot(
                    key: _slotKey(item),
                    index: i,
                    shape: shapes[i],
                    visible: visible[i],
                    // 面板一次排好整個內容，沒有畫面外才建這回事。
                    prebuildRows: fill ? prebuildRows - firstRow[i] : 0,
                    keepAlive: fill,
                    item: item,
                  ),
              ]),
            ),
          ),
        );
        return fill ? RepaintBoundary(child: content) : content;
      },
    );
    if (!fill) return entrance;
    // 畫面外的列建好時，這裡的 LayoutBuilder 要重新排版（它底下的元件重建
    // 都經過它），一路往上排到頁面、整頁重畫一次：把頁面撐滿的這一塊隔成
    // 自己排版、自己重畫，底色另隔一層，清單之外的畫面一筆都不重畫
    // （[_Prebuild]）。
    return SizedBox.expand(child: RepaintBoundary(child: entrance));
  }
}

/// 清單的一項：骨架底下輪到才建，之前佔著骨架算好的高度。一組分組卡片
/// 以列為單位排隊（組標題文字與卡片外框先建），一格建一列：像「排版」這樣一組
/// 八列步進的組整組一起建，在電腦的 debug 模式要 50ms 以上。第一個畫面裡
/// 的列，加上畫面底下清單本來就會先建好的那一段放得下的列數（[_queuedBelow]）
/// 排隊：一組跨在畫面底邊時，緊接在下面的幾列不和露出來的那一列擠在同一格。
/// 再往下的列換場不等它們（不然一列一格，兩百列的替換規則要等三秒以上）：
/// 跨在畫面底邊的組和組一起建；整組在畫面外的，從清單頂端數 [prebuildRows]
/// 列以內的換場播完才建（[_Prebuild]），再往下的（上百列的組）和組一起建。
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
    required this.prebuildRows,
    required this.keepAlive,
    required this.item,
  });

  final int index;

  /// 頁面的清單：換場前掛上的項目捲出畫面也留著（[_KeepAlive]）。
  final bool keepAlive;
  final GroupedItemShape shape;

  /// 這一項上緣到畫面底的距離；不到 0 時整項都在畫面外。
  final double visible;

  /// 這一項從第一列算起，還有幾列換場播完才建（[_Prebuild]）；再往下的列
  /// 和組一起建。
  final int prebuildRows;
  final Widget item;

  @override
  Widget build(BuildContext context) {
    final slot = _slot();
    return keepAlive ? _KeepAlive(child: slot) : slot;
  }

  Widget _slot() {
    final item = this.item;
    if (item is! GroupedSection) {
      return _EntranceSlot(
        kind: visible > 0
            ? _EntranceKind.queued
            : prebuildRows > 0
            ? _EntranceKind.deferred
            : _EntranceKind.direct,
        height: shape.height,
        child: item,
      );
    }
    final children = item.children;
    // 骨架只量到畫面底：再往下的組沒有每一列的高度，先照最矮的列佔位，
    // 反正畫面上看不到。
    final measured = shape.rowHeights;
    final hasRows = measured != null && measured.length == children.length;
    final heights = hasRows
        ? measured
        : List.filled(children.length, AppGrouped.rowMinHeight);
    final out = <Widget>[];
    var top = shape.card?.top ?? 0;
    var below = 0;
    for (var i = 0; i < children.length; i++) {
      // 骨架只量到畫面底，再往下的列高度不知道，照列數算；沒量的組畫面上
      // 有它就整組排隊。
      final queued = hasRows
          ? top < visible || below++ < _queuedBelow
          : visible > 0;
      out.add(
        _EntranceSlot(
          key: _slotKey(children[i]),
          kind: queued
              ? _EntranceKind.queued
              : visible <= 0 && i < prebuildRows
              ? _EntranceKind.deferred
              : _EntranceKind.direct,
          height: heights[i],
          child: children[i],
        ),
      );
      top += heights[i] + AppGlass.hairline;
    }
    return item.withRows(out);
  }
}

/// 換場前掛上的清單項目捲出畫面也不拆掉：建好的列捲回來不必重建，一般的
/// 設定頁整頁都是這種。換場後才掛上的（捲到三個畫面外才建的）和以前一樣
/// 捲遠了就拆掉，上百項的清單不會整份一直留著。
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  late final bool _keep = !(_PrebuildScope.maybeOf(context)?.released ?? true);

  @override
  bool get wantKeepAlive => _keep;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// 進場中的一列（或不是分組卡片的一項）怎麼建；第一次建時定下，之後清單
/// 高度變了（鍵盤升降）也不換，列才不會被拆掉重建。
enum _EntranceKind {
  /// 換場前在骨架底下一格建一列（[CoverRevealSlot]）：畫面裡的列。
  queued,

  /// 換場播完的下一格才建（[_Prebuild]）：整組在畫面外的列。
  deferred,

  /// 直接建：換場後才掛上的，或在先建的列數上限之外的。
  direct,
}

class _EntranceSlot extends StatefulWidget {
  const _EntranceSlot({
    super.key,
    required this.kind,
    required this.height,
    required this.child,
  });

  /// 只看第一次建時的值。
  final _EntranceKind kind;

  /// 還沒建時佔的高度。
  final double height;
  final Widget child;

  @override
  State<_EntranceSlot> createState() => _EntranceSlotState();
}

class _EntranceSlotState extends State<_EntranceSlot> {
  late _EntranceKind _kind = widget.kind;

  /// 排著等換場播完的那一份。
  _Prebuild? _waitingOn;

  @override
  void initState() {
    super.initState();
    if (_kind != _EntranceKind.deferred) return;
    final prebuild = _PrebuildScope.maybeOf(context);
    if (prebuild == null || prebuild.released) {
      _kind = _EntranceKind.direct;
      return;
    }
    _waitingOn = prebuild..add(this);
  }

  @override
  void dispose() {
    _waitingOn?.remove(this);
    super.dispose();
  }

  void _release() {
    _waitingOn = null;
    if (mounted) setState(() => _kind = _EntranceKind.direct);
  }

  @override
  Widget build(BuildContext context) => switch (_kind) {
    _EntranceKind.queued => CoverRevealSlot(
      placeholder: SizedBox(height: widget.height),
      child: widget.child,
    ),
    _EntranceKind.deferred => SizedBox(height: widget.height),
    _EntranceKind.direct => widget.child,
  };
}

/// 整組在畫面外的列，換場播完的下一格一次建好（ADR 0037 策略一、四：手指
/// 動之前在靜止時先把會用到的列建好）。換場播完後畫面靜止，那一格再重也
/// 看不出來；清單整個包一層重畫邊界（[GroupedListView]），畫面外的列長出來時
/// 畫面上的圖層不變。換場前清單在畫面上下多建三個畫面的項目
/// （[_PrebuildCacheExtent]），建好的留著（[_KeepAlive]），一般的設定頁整頁建好就
/// 一直留著，捲過去、捲回來都不再建。換場後才出現的列（打開開關多出來的、
/// 捲到三個畫面外才建的）直接建，和以前一樣。
class _Prebuild {
  /// 清單在畫面上下各留幾個畫面的列。
  static const double _screens = 3;

  /// 換場播完才建的列數上限：畫面加上下面三個畫面放得下幾列最矮的列，從
  /// 清單頂端數。
  static int rowsFor(double viewport) =>
      ((_screens + 1) * viewport / AppGrouped.rowMinHeight).ceil();

  final Set<_EntranceSlotState> _waiting = {};
  bool _released = false;

  /// 列都建好了：清單多建的範圍縮回預設（[_PrebuildCacheExtent]）。
  final ValueNotifier<bool> _settled = ValueNotifier(false);

  void settle() => _settled.value = true;

  void dispose() => _settled.dispose();

  /// 換場播完了：之後掛上的列直接建。
  bool get released => _released;

  void add(_EntranceSlotState slot) => _waiting.add(slot);

  void remove(_EntranceSlotState slot) => _waiting.remove(slot);

  /// 換場播完：等著的列下一格一起建。
  void release() {
    if (_released) return;
    _released = true;
    final waiting = _waiting.toList();
    _waiting.clear();
    for (final slot in waiting) {
      slot._release();
    }
  }
}

/// 清單在畫面上下各建幾個畫面的項目：換場播完前多建三個畫面
/// （[_Prebuild._screens]），換場前掛上的項目才排得進來；列建好之後縮回
/// 預設，留著的項目在畫面外時不排版、不進無障礙樹，捲動每一幀的工作和以前
/// 一樣。縮回時只重建清單本身：從 [_GroupedEntranceState] 重建的話，頁面
/// 的 LayoutBuilder 會整頁重新排版、重畫。
class _PrebuildCacheExtent extends StatelessWidget {
  const _PrebuildCacheExtent({required this.builder});

  final Widget Function(BuildContext context, ScrollCacheExtent? cacheExtent)
  builder;

  @override
  Widget build(BuildContext context) {
    final prebuild = _PrebuildScope.maybeOf(context);
    if (prebuild == null) return builder(context, null);
    return ValueListenableBuilder<bool>(
      valueListenable: prebuild._settled,
      builder: (context, settled, _) => builder(
        context,
        settled ? null : const ScrollCacheExtent.viewport(_Prebuild._screens),
      ),
    );
  }
}

class _PrebuildScope extends InheritedWidget {
  const _PrebuildScope({required this.prebuild, required super.child});

  final _Prebuild prebuild;

  static _Prebuild? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_PrebuildScope>()?.prebuild;

  @override
  bool updateShouldNotify(_PrebuildScope oldWidget) =>
      !identical(prebuild, oldWidget.prebuild);
}

/// 包著 [child] 的那一層沿用它的 key（列有 key 時，增刪重排照樣對得上）；
/// 包一層 [ValueKey]，[GlobalKey] 才不會用到兩次。
Key? _slotKey(Widget child) => switch (child.key) {
  final key? => ValueKey<Key>(key),
  null => null,
};

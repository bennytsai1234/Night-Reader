import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:night_reader/shared/widgets/text/ui_text.dart';

import '../../layout/readable_width.dart';
import '../../theme/app_chrome.dart';
import '../../theme/app_haptics.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_tokens.dart';
import 'glass.dart';
import 'tab_bar_look.dart';
import '../skeleton/launch_entrance.dart';

import 'package:night_reader/core/chinese/ui_language.dart';

class FloatingTabItem {
  const FloatingTabItem({required this.icon, required this.label});

  /// 選中與未選都用同一個圖示（空心），只換顏色：選取膠囊滑過中點時圖示
  /// 的形狀不換。
  final IconData icon;
  final String label;
}

/// 主頁交給各分頁的開關：分頁進入整頁編輯（例如書架多選）時設為 true，
/// 浮動分頁列沉下、主頁鎖住左右換頁，由分頁自己的工具列佔用
/// [FloatingTabBar.slotOf] 的位置。
class FloatingTabBarScope extends InheritedWidget {
  const FloatingTabBarScope({
    super.key,
    required this.hidden,
    required super.child,
  });

  final ValueNotifier<bool> hidden;

  /// 分頁只寫入開關，不需要因開關變化而重建，因此不建立依賴。
  static ValueNotifier<bool>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FloatingTabBarScope>()?.hidden;

  @override
  bool updateShouldNotify(FloatingTabBarScope oldWidget) =>
      !identical(hidden, oldWidget.hidden);
}

/// 墊在浮動分頁列（或佔用它位置的編輯工具列）後方、由下往上的顏色漸隱帶，
/// 與頁首的漸隱對稱：從螢幕底緣到分頁島上緣再往上 [AppSpacing.sm]（分頁列自己的
/// 上內距）與 [AppGlass.tabBarFadeHeight] 是一整段漸層（[EdgeFade.chrome]），
/// 螢幕底緣實色、往上越來越淡，內容透到分頁島底下。只畫一段漸層，不模糊。
///
/// 貼齊底部放在延伸到分頁列底下（`extendBody: true`）的內容上方；高度取
/// `MediaQuery.paddingOf(context).bottom`，那段已含分頁列與系統手勢區。
/// [hidden] 時跟分頁列一樣沉下。
class FloatingTabBarFade extends StatelessWidget {
  const FloatingTabBarFade({
    super.key,
    required this.color,
    this.hidden = false,
  });

  /// 目前可見頁面的背景色。
  final Color color;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final height =
        MediaQuery.paddingOf(context).bottom + AppGlass.tabBarFadeHeight;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: hidden ? 0 : 1),
          duration: AppMotion.menu,
          curve: hidden ? Curves.easeInCubic : AppMotion.menuCurve,
          builder: (context, shown, _) {
            if (shown <= 0) return const SizedBox.shrink();
            // 跟分頁列一樣只滑動，不淡（ADR 0022）。
            return FractionalTranslation(
              translation: Offset(0, 1 - shown),
              child: EdgeFade.chrome(
                edge: AxisDirection.down,
                height: height,
                color: color,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Telegram iOS 26 式浮動膠囊分頁列，右側可附一顆圓形搜尋鈕。
///
/// 選取膠囊跟著 [controller] 的頁面位置連續移動（滑動切頁時同步）；手指
/// 在分頁列上橫向拖曳時膠囊跟手，膠囊中心一跨進別的分頁就選它
/// （[onSelect]），不等放開。放在
/// [Scaffold.bottomNavigationBar] 並搭配 `extendBody: true`，內容會延伸到
/// 分頁列底下，浮動 SnackBar 也會自動避開分頁列。
class FloatingTabBar extends StatefulWidget {
  const FloatingTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    ValueChanged<int>? onSelect,
    this.controller,
    this.onSearch,
    this.searchTooltip = '搜尋',
    this.hidden = false,
  }) : onSelect = onSelect ?? onTap;

  final List<FloatingTabItem> items;
  final int currentIndex;

  /// 點了某個分頁（含點目前的分頁，例如連點兩下回頂端）。
  final ValueChanged<int> onTap;

  /// 拖曳膠囊時跨進了別的分頁；沒給時同 [onTap]。
  final ValueChanged<int> onSelect;

  /// 主頁的 [PageController]；提供時選取膠囊跟著頁面捲動位置。
  final PageController? controller;

  /// 點右側搜尋鈕。
  final VoidCallback? onSearch;
  final String searchTooltip;

  /// 沉到畫面外並停止接收點擊；佔用的高度不變，內容不會跟著跳動。
  final bool hidden;

  /// 分頁列在延伸到其下方的頁面（`extendBody: true`）裡的位置，給取代
  /// 分頁列的工具列與底部浮動膠囊對齊用：左右和清單的卡片切齊（平板上
  /// 收在內容欄裡，[ReadableWidth.cardInsetOf]）。
  ///
  /// 底部系統區直接取螢幕（[View]）的值：有底部列的 Scaffold 會把頁面的
  /// padding 與 viewPadding 底部都扣掉、再只把 padding 加回列的高度，頁面裡
  /// 讀到的 viewPadding 底部是 0，用它會比分頁列低一個系統區。
  static EdgeInsets slotOf(BuildContext context) {
    // 系統區改變時（旋轉、切換手勢導覽）跟著重建：View 本身不通知，頁面裡
    // 的 viewPadding 底部前後都是 0；padding 底部在分頁列裡是系統區、在頁面
    // 裡是含系統區的列高，兩邊都會跟著變。
    MediaQuery.paddingOf(context);
    final view = View.of(context);
    final systemBottom = view.viewPadding.bottom / view.devicePixelRatio;
    return ReadableWidth.cardInsetOf(context)
        .copyWith(bottom: systemBottom + AppGlass.tabBarBottomGap);
  }

  /// 分頁列整列（分頁列與搜尋鈕）上方留的空白：頁面的底部內距是這一段
  /// 加整列高度、底下的距離與系統區。
  static const double topInset = AppSpacing.sm;

  /// 取代分頁列、和它一樣高的工具列（書架多選）放的位置：照 [slotOf]，
  /// 底下再加整列比分頁列高出的一半（搜尋鈕比分頁列大時兩者垂直置中），
  /// 工具列才和被取代的分頁列在同一個位置。
  static EdgeInsets toolbarSlotOf(BuildContext context) {
    final look = TabBarLook.current.value;
    final slot = slotOf(context);
    return slot.copyWith(
      bottom: slot.bottom + (look.rowHeight - look.barHeight) / 2,
    );
  }

  /// 分頁列的寬度：和卡片左右切齊、扣掉右側搜尋鈕。選了置中的樣子
  /// （[TabBarLook.isCentered]）時每個分頁 [TabBarLook.centeredTabWidth] 寬，
  /// 放不下（很窄的分割視窗）就照切齊時的寬度。
  static double barWidthOf(
    BuildContext context, {
    required int count,
    required bool search,
  }) {
    final look = TabBarLook.current.value;
    final inset = ReadableWidth.cardInsetOf(context);
    final searchWidth = search ? look.searchSize + AppGlass.tabBarGap : 0;
    final full = math.max(
      0.0,
      MediaQuery.sizeOf(context).width - inset.left - inset.right - searchWidth,
    );
    if (!look.isCentered) return full;
    return math.min(
      full,
      TabBarLook.centeredTabWidth * count + AppGlass.tabInnerInset * 2,
    );
  }

  /// 搜尋鈕右緣離螢幕右邊多遠（收聽圓鈕疊在它正上方）。
  static double searchRightOf(BuildContext context, {required int tabCount}) {
    final look = TabBarLook.current.value;
    final side = ReadableWidth.cardInsetOf(context).right;
    if (!look.isCentered) return side;
    final group =
        barWidthOf(context, count: tabCount, search: true) +
        AppGlass.tabBarGap +
        look.searchSize;
    final width = MediaQuery.sizeOf(context).width;
    return math.max(side, (width - group) / 2);
  }

  @override
  State<FloatingTabBar> createState() => _FloatingTabBarState();
}

class _FloatingTabBarState extends State<FloatingTabBar> {
  /// 拖曳中的膠囊位置（以分頁索引為單位）；null 表示跟隨頁面。
  double? _dragPosition;

  /// 放開拖曳後膠囊正用彈簧滑回分頁：放回原本的分頁時頁面沒有動，跟頁
  /// 的膠囊不會自己過去，沒有這段會從手指的位置一幀跳回去。
  bool _settling = false;

  /// 這次拖曳最後選的分頁。同一幀可能收到好幾筆移動，[FloatingTabBar.currentIndex]
  /// 要等主頁重建才跟上，拿它判斷有沒有跨格會漏掉跨過去又拖回來的那一下。
  int? _dragSelected;

  @override
  void initState() {
    super.initState();
    TabBarLook.current.addListener(_onLookChanged);
  }

  @override
  void dispose() {
    TabBarLook.current.removeListener(_onLookChanged);
    super.dispose();
  }

  void _onLookChanged() => setState(() {});

  double _pagePosition() {
    final controller = widget.controller;
    if (controller != null &&
        controller.hasClients &&
        controller.position.hasContentDimensions) {
      return controller.page ?? widget.currentIndex.toDouble();
    }
    return widget.currentIndex.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final look = TabBarLook.current.value;
    // 分頁列加搜尋鈕的左右和清單的卡片切齊（平板上收在內容欄裡）。
    final side = ReadableWidth.cardInsetOf(context).left;
    final barWidth = FloatingTabBar.barWidthOf(
      context,
      count: widget.items.length,
      search: widget.onSearch != null,
    );

    final bar = Padding(
      padding: EdgeInsets.fromLTRB(
        side,
        FloatingTabBar.topInset,
        side,
        bottom + AppGlass.tabBarBottomGap,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 開 App 時先是骨架，跟書架一起換成玻璃（LaunchEntrance）。
          LaunchSkeleton(
            child: SizedBox(
              width: barWidth,
              height: look.barHeight,
              child: _buildBar(context, barWidth),
            ),
          ),
          if (widget.onSearch != null) ...[
            const SizedBox(width: AppGlass.tabBarGap),
            LaunchSkeleton(
              child: Semantics(
                button: true,
                label: UiLanguageText.convertNullable(
                  context,
                  widget.searchTooltip,
                ),
                child: PressScale(
                  onTap: widget.onSearch,
                  child: SizedBox.square(
                    dimension: look.searchSize,
                    child: GlassSurface(
                      shape: BoxShape.circle,
                      child: Icon(
                        Icons.search_rounded,
                        size: look.searchIconSize,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    // 只滑動不淡（ADR 0022）；bar 本身已含到螢幕底緣的內距。
    return IgnorePointer(
      ignoring: widget.hidden,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: widget.hidden ? 0 : 1),
        duration: AppMotion.menu,
        curve: widget.hidden ? Curves.easeInCubic : AppMotion.menuCurve,
        child: bar,
        builder: (context, shown, child) =>
            GlassSlide(shown: shown, edge: AxisDirection.down, child: child!),
      ),
    );
  }

  Widget _buildBar(BuildContext context, double barWidth) {
    final chrome = AppChrome.of(context);
    final count = widget.items.length;
    final itemWidth = (barWidth - AppGlass.tabInnerInset * 2) / count;

    int indexAt(double dx) =>
        ((dx - AppGlass.tabInnerInset) / itemWidth).floor().clamp(0, count - 1);

    // 每個分頁的圖示與字在這裡建好一次（未選的用未選色、選取的用選取色），
    // 膠囊滑動的每一幀沿用同一份，只換染色（[_TabItem]）。
    final scheme = Theme.of(context).colorScheme;
    final glyphs = [
      for (final item in widget.items)
        (
          idle: _TabGlyph(
            icon: item.icon,
            label: item.label,
            color: scheme.onSurfaceVariant,
          ),
          selected: _TabGlyph(
            icon: item.icon,
            label: item.label,
            color: scheme.primary,
          ),
        ),
    ];

    // 拖曳中膠囊中心跨進別的分頁就換過去，頁面跟著手指換，不等放開。
    void updateDrag(double dx) {
      final position = ((dx - AppGlass.tabInnerInset) / itemWidth - 0.5).clamp(
        0.0,
        (count - 1).toDouble(),
      );
      setState(() {
        _dragPosition = position;
        _settling = false;
      });
      final index = position.round();
      if (index != (_dragSelected ?? widget.currentIndex)) {
        _dragSelected = index;
        AppHaptics.select();
        widget.onSelect(index);
      }
    }

    // 放開時頁面已經在手指下的分頁，膠囊從手指的位置用彈簧滑回分頁中央。
    void endDrag() {
      _dragSelected = null;
      if (_dragPosition == null) return;
      setState(() {
        _dragPosition = null;
        _settling = true;
      });
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 讀屏的點擊沒有位置，交給各分頁自己的語意動作。
      excludeFromSemantics: true,
      onTapUp: (d) => widget.onTap(indexAt(d.localPosition.dx)),
      onHorizontalDragStart: (d) => updateDrag(d.localPosition.dx),
      onHorizontalDragUpdate: (d) => updateDrag(d.localPosition.dx),
      onHorizontalDragEnd: (_) => endDrag(),
      onHorizontalDragCancel: endDrag,
      child: GlassSurface(
        borderRadius: AppRadius.pillShape,
        child: AnimatedBuilder(
          animation: widget.controller ?? const AlwaysStoppedAnimation(0),
          builder: (context, _) {
            final target = _dragPosition ?? _pagePosition();
            return TweenAnimationBuilder<double>(
              tween: Tween(end: target),
              // 拖曳與跟頁時直接跟手；跳轉（例如無 controller）與放開拖曳
              // 後滑到分頁時用彈簧，放回原分頁也一樣滑回去。
              duration:
                  _dragPosition == null &&
                      (widget.controller == null || _settling) &&
                      !MediaQuery.disableAnimationsOf(context)
                  ? AppMotion.spring
                  : Duration.zero,
              curve: AppMotion.springCurve,
              onEnd: () {
                if (_settling) setState(() => _settling = false);
              },
              builder: (context, position, _) {
                return Stack(
                  children: [
                    Positioned(
                      left: AppGlass.tabInnerInset + position * itemWidth,
                      top: AppGlass.tabInnerInset,
                      width: itemWidth,
                      height: TabBarLook.current.value.tabItemHeight,
                      child: AnimatedScale(
                        scale: _dragPosition != null ? 1.06 : 1,
                        duration: AppMotion.menu,
                        curve: AppMotion.springCurve,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: chrome.selectionLens,
                            borderRadius: AppRadius.pillShape,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      left: AppGlass.tabInnerInset,
                      right: AppGlass.tabInnerInset,
                      top: AppGlass.tabInnerInset,
                      bottom: AppGlass.tabInnerInset,
                      child: Row(
                        children: [
                          for (var i = 0; i < count; i++)
                            Expanded(
                              child: _TabItem(
                                // 依膠囊距離漸變選取色，滑頁時顏色跟著過渡。
                                selection: (1 - (position - i).abs()).clamp(
                                  0.0,
                                  1.0,
                                ),
                                selected: i == widget.currentIndex,
                                label: widget.items[i].label,
                                glyph: glyphs[i],
                                onActivate: () => widget.onTap(i),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.selection,
    required this.selected,
    required this.label,
    required this.glyph,
    required this.onActivate,
  });

  final double selection;
  final bool selected;
  final String label;
  final ({_TabGlyph idle, _TabGlyph selected}) glyph;

  /// 讀屏的點擊動作；手指點擊由外層依位置判斷，讀屏沒有位置可用。
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = Color.lerp(
      scheme.onSurfaceVariant,
      scheme.primary,
      selection,
    )!;
    return Semantics(
      button: true,
      selected: selected,
      label: UiLanguageText.convert(context, label),
      onTap: onActivate,
      excludeSemantics: true,
      // 圖示與字照字形的透明度染成 [color]；換顏色只重畫這一層，圖示與字
      // 不重建。染的是用未選色或選取色畫好的那一份：字的反鋸齒照字的顏色調
      // （白字的邊比深色字實，染回深色後看起來變粗），用端點的顏色畫，靜止時
      // 染回同一個顏色，和直接用那個顏色畫的一模一樣。
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        child: selection > 0.5 ? glyph.selected : glyph.idle,
      ),
    );
  }
}

/// 分頁的圖示與名稱，用 [color] 畫。
class _TabGlyph extends StatelessWidget {
  const _TabGlyph({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  // 系統字級很大時（例如 200%）圖示加字會比分頁高，整組等比縮小放進去，
  // 不裁字。
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: TabBarLook.current.value.tabIconSize, color: color),
        const SizedBox(height: 2),
        UiText(
          label,
          maxLines: 1,
          style: AppTextStyles.micro.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

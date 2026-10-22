import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_constants.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness_bar.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_entrance.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_palette.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_top_menu.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_sleep_timer.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_device_channel.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

/// 閱讀頁面框架的垂直幾何：頁首、正文、頁尾各佔的高度。
///
/// 頁首佔用狀態列（或隱藏狀態列後剩下的鏡頭挖孔區）；有資訊時，
/// 狀態列顯示中會在其下方多一條資訊列，隱藏時則直接把資訊放進該區。
/// 上邊距是正文與頁首之間的距離；下邊距是正文與頁尾資訊列（沒有頁尾時
/// 為畫面底部的系統內距）之間的距離。
///
/// 隱藏狀態列時，頁首只依 topCutoutExtent（鏡頭挖孔與曲面邊緣佔掉的
/// 高度）決定，不看狀態列當下的內距：從後台回到前台時系統會先把狀態列
/// 叫回來、再由 App 收起，這段期間的內距變動不得推動正文。
@immutable
final class ReaderV2PageChromeLayout {
  const ReaderV2PageChromeLayout._({
    required this.headerExtent,
    required this.headerRowTop,
    required this.footerExtent,
    required this.footerRowBottom,
    required this.contentTop,
    required this.contentBottom,
    required this.showHeaderInfo,
    required this.showFooterInfo,
  });

  /// [topCutoutExtent] 為 null 表示尚未取得挖孔高度，暫以系統內距代替。
  /// [footerOffset] 為頁尾資訊列底部到畫面底部的距離。
  factory ReaderV2PageChromeLayout.resolve({
    required EdgeInsets mediaPadding,
    double? topCutoutExtent,
    required bool hideStatusBar,
    required bool showHeaderInfo,
    required bool showFooterInfo,
    required double paddingTop,
    required double paddingBottom,
    required double footerOffset,
  }) {
    final top = hideStatusBar
        ? topCutoutExtent ?? mediaPadding.top
        : mediaPadding.top;
    final double headerExtent;
    final double headerRowTop;
    if (!showHeaderInfo) {
      headerExtent = top;
      headerRowTop = top;
    } else if (hideStatusBar) {
      headerExtent = top > kReaderInfoRowHeight ? top : kReaderInfoRowHeight;
      headerRowTop = 0;
    } else {
      headerExtent = top + kReaderInfoRowHeight;
      headerRowTop = top;
    }
    final footerRowBottom = footerOffset;
    final footerExtent = showFooterInfo
        ? footerRowBottom + kReaderFooterRowHeight
        : mediaPadding.bottom;
    return ReaderV2PageChromeLayout._(
      headerExtent: headerExtent,
      headerRowTop: headerRowTop,
      footerExtent: footerExtent,
      footerRowBottom: footerRowBottom,
      contentTop: headerExtent + paddingTop,
      contentBottom: footerExtent + paddingBottom,
      showHeaderInfo: showHeaderInfo,
      showFooterInfo: showFooterInfo,
    );
  }

  final double headerExtent;

  /// 頁首資訊列在頁首區內的起點；狀態列顯示時位於狀態列下方。
  final double headerRowTop;
  final double footerExtent;

  /// 頁尾資訊列底部到畫面底部的距離。
  final double footerRowBottom;
  final double contentTop;
  final double contentBottom;
  final bool showHeaderInfo;
  final bool showFooterInfo;
}

class ReaderV2PageShell extends StatelessWidget {
  const ReaderV2PageShell({
    super.key,
    required this.book,
    required this.scaffoldKey,
    required this.content,
    required this.drawer,
    required this.backgroundColor,
    required this.infoColor,
    required this.textColor,
    required this.controlsVisible,
    required this.showReadTitleAddition,
    required this.infoState,
    required this.chapterTitle,
    required this.originName,
    this.progressListenable,
    required this.navigation,
    required this.isAutoPaging,
    required this.hideStatusBar,
    required this.headerInfo,
    required this.footerInfo,
    required this.paddingHorizontal,
    required this.paddingTop,
    required this.paddingBottom,
    required this.footerOffset,
    this.topCutoutExtent,
    required this.dayNightIcon,
    required this.dayNightTooltip,
    required this.onExitIntent,
    required this.onSystemBack,
    required this.onMore,
    required this.onOpenDrawer,
    required this.onTts,
    required this.onTimedTts,
    required this.onInterface,
    required this.onSettings,
    required this.onAutoPage,
    required this.onToggleDayNight,
    required this.onReplaceRule,
    required this.onShowControls,
    required this.onDismissControls,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onScrubStart,
    required this.onScrubbing,
    required this.onScrubEnd,
    this.brightnessControl,
    this.sleepTimer,
    this.isTtsPlaying = false,
    this.showTts = true,
    this.showAutoPage = true,
    this.showReplaceRule = true,
    this.onMenuHidden,
  });

  final Book book;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final Widget content;
  final ReaderV2ChaptersDrawer drawer;
  final Color backgroundColor;

  /// 頁首／頁尾資訊列的文字與圖示色。
  final Color infoColor;

  /// 正文色：資訊列的載入骨架與正文骨架同色。
  final Color textColor;
  final bool controlsVisible;
  final bool showReadTitleAddition;
  final ReaderV2InfoState infoState;
  final String chapterTitle;
  final String originName;
  final ValueListenable<HybridProgressSnapshot?>? progressListenable;
  final ReaderV2ChapterNavigationState navigation;
  final bool isAutoPaging;
  final bool hideStatusBar;
  final ReaderV2InfoSlots headerInfo;
  final ReaderV2InfoSlots footerInfo;

  /// 正文的左右邊距；頁首頁尾資訊列的左右內距也用它。
  final double paddingHorizontal;
  final double paddingTop;
  final double paddingBottom;

  /// 頁尾資訊列底部到畫面底部的距離。
  final double footerOffset;

  /// 鏡頭挖孔與曲面邊緣佔掉的上緣高度；null 表示尚未取得。
  final double? topCutoutExtent;
  final IconData dayNightIcon;
  final String dayNightTooltip;

  /// 頂部返回鈕與錯誤頁的返回：直接走離開流程。
  final VoidCallback onExitIntent;

  /// 系統返回且目錄沒開著時呼叫：由頁面決定先收起什麼。
  final VoidCallback onSystemBack;
  final VoidCallback onMore;
  final VoidCallback onOpenDrawer;

  final VoidCallback onTts;
  final VoidCallback onTimedTts;
  final VoidCallback onInterface;
  final VoidCallback onSettings;
  final VoidCallback onAutoPage;
  final VoidCallback onToggleDayNight;
  final VoidCallback onReplaceRule;
  final VoidCallback onShowControls;
  final VoidCallback onDismissControls;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final ValueChanged<double> onScrubStart;
  final ValueChanged<double> onScrubbing;
  final ValueChanged<double> onScrubEnd;
  final Widget? brightnessControl;
  final ReaderV2TtsSleepTimer? sleepTimer;
  final bool isTtsPlaying;
  final bool showTts;
  final bool showAutoPage;
  final bool showReplaceRule;

  /// 上下選單與亮度條收完、完全移出畫面時呼叫。三塊同時出發、收起時長
  /// 相同，跟著下方選單的收起動畫。
  final VoidCallback? onMenuHidden;

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final layout = ReaderV2PageChromeLayout.resolve(
      mediaPadding: mediaPadding,
      topCutoutExtent: topCutoutExtent,
      hideStatusBar: hideStatusBar,
      showHeaderInfo: showReadTitleAddition && !headerInfo.isEmpty,
      showFooterInfo: showReadTitleAddition && !footerInfo.isEmpty,
      paddingTop: paddingTop,
      paddingBottom: paddingBottom,
      footerOffset: footerOffset,
    );
    final infoShown = infoState != ReaderV2InfoState.hidden;
    // 正文與頁首、頁尾之間的空隙（上下邊距）裡的漸隱，最多 14（同 App 頁首
    // 下緣）。邊距是 0 時沒有空隙，切口照舊。
    final fadeTop = math.min(
      layout.contentTop - layout.headerExtent,
      AppGlass.headerFadeHeight,
    );
    final fadeBottom = math.min(
      layout.contentBottom - layout.footerExtent,
      AppGlass.headerFadeHeight,
    );
    // 自動翻頁提示放在頁尾；頁尾關閉時改放頁首。
    final autoPageInFooter = layout.showFooterInfo;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // 目錄開著時返回只收目錄。
        final scaffold = scaffoldKey.currentState;
        if (scaffold != null && scaffold.isDrawerOpen) {
          scaffold.closeDrawer();
          return;
        }
        onSystemBack();
      },
      child: Scaffold(
        key: scaffoldKey,
        body: Container(
          color: backgroundColor,
          child: Stack(
            children: [
              // 正文上下緣常露出半行（ADR 0006）。正文區本身不動：跨在邊上
              // 的那一行畫進正文與頁首頁尾之間的空隙，在空隙裡漸隱，不蓋到
              // 頁首頁尾，也不淡掉正文區裡的字。
              Positioned.fill(
                top: layout.contentTop - fadeTop,
                bottom: layout.contentBottom - fadeBottom,
                child: ClipRect(
                  child: Padding(
                    padding: EdgeInsets.only(top: fadeTop, bottom: fadeBottom),
                    child: content,
                  ),
                ),
              ),
              if (fadeTop > 0)
                Positioned(
                  top: layout.contentTop - fadeTop,
                  left: 0,
                  right: 0,
                  child: EdgeFade(
                    edge: AxisDirection.up,
                    height: fadeTop,
                    color: backgroundColor,
                  ),
                ),
              if (fadeBottom > 0)
                Positioned(
                  bottom: layout.contentBottom - fadeBottom,
                  left: 0,
                  right: 0,
                  child: EdgeFade(
                    edge: AxisDirection.down,
                    height: fadeBottom,
                    color: backgroundColor,
                  ),
                ),
              if (layout.headerExtent > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: layout.headerExtent,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // 完成點擊才叫出選單；從這裡起手的滑動與長按不算。
                    // 選單開著時由收起層處理。
                    onTap: controlsVisible ? null : onShowControls,
                    child: ColoredBox(
                      color: backgroundColor,
                      child: layout.showHeaderInfo && infoShown
                          ? Padding(
                              padding: EdgeInsets.only(
                                top: layout.headerRowTop,
                              ),
                              child: Center(
                                child: _InfoLayer(
                                  state: infoState,
                                  builder: (skeleton) => _InfoRow(
                                    shell: this,
                                    slots: headerInfo,
                                    showAutoPage:
                                        isAutoPaging && !autoPageInFooter,
                                    skeleton: skeleton,
                                  ),
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              if (layout.showFooterInfo && infoShown)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: layout.footerExtent,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // 完成點擊才叫出選單；從這裡起手的滑動與長按不算。
                    // 選單開著時由收起層處理。
                    onTap: controlsVisible ? null : onShowControls,
                    child: _PermanentInfoBar(
                      shell: this,
                      rowBottom: layout.footerRowBottom,
                    ),
                  ),
                ),
              if (controlsVisible)
                Positioned.fill(
                  child: _ReaderV2ControlsDismissLayer(
                    onDismiss: onDismissControls,
                  ),
                ),
              // 收起層隨選單開關進出，前面的子元件會錯位；有 key 選單才會
              // 留在原處播動畫，不被重建成終點狀態。
              Positioned.fill(
                key: const ValueKey('reader-menus'),
                child: CustomMultiChildLayout(
                  delegate: _MenuLayoutDelegate(),
                  children: [
                    LayoutId(
                      id: _MenuSlot.top,
                      child: ReaderV2TopMenu(
                        controlsVisible: controlsVisible,
                        bookName: context.zh(book.name),
                        chapterTitle: chapterTitle,
                        originName: originName,
                        showReadTitleAddition: showReadTitleAddition,
                        onBack: onExitIntent,
                        onMore: onMore,
                      ),
                    ),
                    LayoutId(
                      id: _MenuSlot.bottom,
                      child: ReaderV2BottomMenu(
                        controlsVisible: controlsVisible,
                        navigation: navigation,
                        isAutoPaging: isAutoPaging,
                        dayNightIcon: dayNightIcon,
                        dayNightTooltip: dayNightTooltip,
                        onOpenDrawer: onOpenDrawer,
                        onTts: onTts,
                        onTimedTts: onTimedTts,
                        onInterface: onInterface,
                        onSettings: onSettings,
                        onAutoPage: onAutoPage,
                        onToggleDayNight: onToggleDayNight,
                        onReplaceRule: onReplaceRule,
                        onPrevChapter: onPrevChapter,
                        onNextChapter: onNextChapter,
                        onScrubStart: onScrubStart,
                        onScrubbing: onScrubbing,
                        onScrubEnd: onScrubEnd,
                        progressListenable: progressListenable,
                        sleepTimer: sleepTimer,
                        isTtsPlaying: isTtsPlaying,
                        showTts: showTts,
                        showAutoPage: showAutoPage,
                        showReplaceRule: showReplaceRule,
                        onHidden: onMenuHidden,
                      ),
                    ),
                    if (brightnessControl case final control?)
                      LayoutId(
                        id: _MenuSlot.brightness,
                        child: ReaderV2MenuEntrance(
                          visible: controlsVisible,
                          edge: AxisDirection.left,
                          gap: AppGrouped.margin,
                          // 比上下選單晚一點出發，三塊錯開。
                          delay: AppMotion.readerMenuStagger,
                          child: Theme(
                            data: ReaderV2MenuStyle.of(context)
                                .toSheetTheme(Theme.of(context)),
                            child: control,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        drawer: drawer,
      ),
    );
  }
}

enum _MenuSlot { top, bottom, brightness }

/// 上下選單貼齊畫面上下緣；亮度條靠左，撐滿兩者之間的空間、上下各留
/// [AppSpacing.xl]，在上下選單之間置中。空間不夠時亮度條自己不畫
/// （[ReaderV2BrightnessBar.minHeight]）。
class _MenuLayoutDelegate extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size).copyWith(minWidth: size.width);
    final top = layoutChild(_MenuSlot.top, loose);
    positionChild(_MenuSlot.top, Offset.zero);
    final bottom = layoutChild(_MenuSlot.bottom, loose);
    positionChild(_MenuSlot.bottom, Offset(0, size.height - bottom.height));
    if (!hasChild(_MenuSlot.brightness)) return;
    final available =
        size.height - top.height - bottom.height - AppSpacing.xl * 2;
    layoutChild(
      _MenuSlot.brightness,
      BoxConstraints.tightFor(
        width: AppGlass.buttonSize,
        height: available < 0 ? 0 : available,
      ),
    );
    positionChild(
      _MenuSlot.brightness,
      Offset(AppGrouped.margin, top.height + AppSpacing.xl),
    );
  }

  @override
  bool shouldRelayout(_MenuLayoutDelegate oldDelegate) => false;
}

/// 頁首頁尾資訊列目前要畫什麼。
enum ReaderV2InfoState {
  /// 不畫：開書取不到正文（正文區改顯示錯誤）。
  hidden,

  /// 正文還沒排好（開書、跳到別章、改排版或重載內容）：每個欄位畫成骨架。
  loading,

  /// 正文已排好：顯示真正的資訊。
  ready,
}

/// 資訊列在骨架與真正資訊之間交叉淡換：骨架照資訊的寬度畫在同一個位置，
/// 看起來是文字變成長條、長條再變回文字。變成骨架、以及骨架換成資訊（和
/// 正文一起）都照骨架換場（[SkeletonReveal]）的方式與時長，收起（取不到
/// 正文）用 [AppMotion.fade]。開書時原本沒有資訊，就是骨架出現。系統關閉
/// 動畫時直接到位。
class _InfoLayer extends StatefulWidget {
  const _InfoLayer({required this.state, required this.builder});

  final ReaderV2InfoState state;

  /// 畫出資訊列；`skeleton` 為 true 時每個欄位畫成骨架。
  final Widget Function(bool skeleton) builder;

  @override
  State<_InfoLayer> createState() => _InfoLayerState();
}

class _InfoLayerState extends State<_InfoLayer> with TickerProviderStateMixin {
  late final AnimationController _skeleton = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
  )..addStatusListener(_onFadeStatus);
  late final AnimationController _info = AnimationController(
    vsync: this,
    duration: AppMotion.fade,
  )..addStatusListener(_onFadeStatus);

  /// null 表示還沒讀過 MediaQuery，第一次讀到時才開始同步狀態。
  bool? _reduceMotion;

  /// 這一次換進來的是骨架還是資訊。
  SkeletonRevealSide _incoming = SkeletonRevealSide.content;

  /// 這一次換場是不是由左而右；收起一律整條淡。
  bool _sweep = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _sync();
  }

  @override
  void didUpdateWidget(_InfoLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _sync(from: oldWidget.state);
  }

  @override
  void dispose() {
    _skeleton.dispose();
    _info.dispose();
    super.dispose();
  }

  void _sync({ReaderV2InfoState? from}) {
    // 骨架與資訊在同一個位置交叉淡換，兩者都從目前的濃淡接著走，切換途中
    // 再切回來不會先閃空。
    final state = widget.state;
    final toSkeleton = state == ReaderV2InfoState.loading;
    final toInfo =
        from == ReaderV2InfoState.loading && state == ReaderV2InfoState.ready;
    final reveal = toSkeleton || toInfo ? SkeletonReveal.of(context) : null;
    // 換場途中反過來時沿用這一輪的方向與方式倒著走：換掉 _incoming 會讓
    // 左右的濃淡在同一幀對調。
    if (!_skeleton.isAnimating && !_info.isAnimating) {
      _incoming = toSkeleton
          ? SkeletonRevealSide.skeleton
          : SkeletonRevealSide.content;
      _sweep = reveal?.sweeps ?? false;
    }
    final duration = reveal?.duration ?? AppMotion.fade;
    _info.duration = duration;
    _skeleton.duration = duration;
    _animate(_skeleton, toSkeleton ? 1 : 0);
    _animate(_info, state == ReaderV2InfoState.ready ? 1 : 0);
  }

  void _animate(AnimationController controller, double target) {
    if (_reduceMotion ?? false) {
      controller.value = target;
    } else {
      // 濃淡停在目標上不代表動畫停了：剛開始往反方向走的動畫還沒動，
      // 也要轉回來；已經在終點時 forward／reverse 不會動。
      unawaited(target == 1 ? controller.forward() : controller.reverse());
    }
  }

  void _onFadeStatus(AnimationStatus status) {
    // 淡出完的一層移出畫面（骨架的呼吸動畫跟著停）。
    if (status == AnimationStatus.dismissed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final showInfo = state == ReaderV2InfoState.ready || !_info.isDismissed;
    final showSkeleton =
        state == ReaderV2InfoState.loading || !_skeleton.isDismissed;
    // 兩層各帶 key：一層淡完移出時另一層的位置往前挪，沒有 key 會被接到
    // 移走那一層的元素上重建，骨架的呼吸從頭開始、資訊的時鐘電量重訂閱。
    return Stack(
      alignment: Alignment.center,
      children: [
        if (showInfo)
          SkeletonRevealLayer(
            key: const ValueKey(SkeletonRevealSide.content),
            presence: _info,
            side: SkeletonRevealSide.content,
            incoming: _incoming,
            sweep: _sweep,
            child: widget.builder(false),
          ),
        if (showSkeleton)
          SkeletonRevealLayer(
            key: const ValueKey(SkeletonRevealSide.skeleton),
            presence: _skeleton,
            side: SkeletonRevealSide.skeleton,
            incoming: _incoming,
            sweep: _sweep,
            child: Skeleton(child: widget.builder(true)),
          ),
      ],
    );
  }
}

class _PermanentInfoBar extends StatelessWidget {
  const _PermanentInfoBar({required this.shell, required this.rowBottom});

  final ReaderV2PageShell shell;

  /// 資訊列底部到畫面底部的距離。
  final double rowBottom;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            shell.backgroundColor.withValues(alpha: 0.0),
            shell.backgroundColor.withValues(alpha: 0.88),
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: rowBottom),
        child: Align(
          alignment: Alignment.topCenter,
          child: _InfoLayer(
            state: shell.infoState,
            builder: (skeleton) => _InfoRow(
              shell: shell,
              slots: shell.footerInfo,
              showAutoPage: shell.isAutoPaging,
              rowHeight: kReaderFooterRowHeight,
              skeleton: skeleton,
            ),
          ),
        ),
      ),
    );
  }
}

/// 一條資訊列：左欄可省略、右欄靠右；兩欄都放不下時各自以刪節號收尾。
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.shell,
    required this.slots,
    required this.showAutoPage,
    this.rowHeight = kReaderInfoRowHeight,
    this.skeleton = false,
  });

  final ReaderV2PageShell shell;
  final ReaderV2InfoSlots slots;
  final bool showAutoPage;
  final double rowHeight;

  /// 每個欄位畫成骨架（見 [_InfoItemSkeleton]），不提供語意。
  final bool skeleton;

  @override
  Widget build(BuildContext context) {
    final progressListenable = shell.progressListenable;
    if (progressListenable == null) return _buildRow(context, null);
    return ValueListenableBuilder<HybridProgressSnapshot?>(
      valueListenable: progressListenable,
      builder: (context, progress, _) => _buildRow(context, progress),
    );
  }

  Widget _buildRow(BuildContext context, HybridProgressSnapshot? progress) {
    final infoColor = shell.infoColor;
    final skeletonColor = skeleton
        ? Skeleton.tint(
            shell.textColor,
            dark:
                ThemeData.estimateBrightnessForColor(shell.backgroundColor) ==
                Brightness.dark,
            strength: SkeletonLook.of(context).strength,
          )
        : null;
    Widget? masked(Widget? child) => skeletonColor == null || child == null
        ? child
        : _InfoItemSkeleton(color: skeletonColor, child: child);
    final left = masked(
      _itemWidget(context, slots.left, progress, TextAlign.left),
    );
    final right = masked(
      _itemWidget(context, slots.right, progress, TextAlign.right),
    );
    final semantics = skeleton
        ? ''
        : [
            if (showAutoPage) '自動翻頁中',
            ?_itemSemantics(context, slots.left, progress),
            ?_itemSemantics(context, slots.right, progress),
          ].join('，');
    return Semantics(
      container: true,
      label: semantics,
      child: ExcludeSemantics(
        child: Padding(
          // 與正文同一個左右邊距：開「左右對齊」時正文兩緣與資訊列貼齊
          // （ADR 0019）。
          padding: EdgeInsets.symmetric(horizontal: shell.paddingHorizontal),
          child: DefaultTextStyle(
            style: AppTextStyles.uiXs.copyWith(
              color: infoColor,
              fontWeight: FontWeight.w400,
              fontFamily: kReaderV2PunctFontFamily,
              fontFamilyFallback: kReaderV2FontFamilyFallback,
              locale: kReaderV2TextLocale,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  if (showAutoPage) ...[
                    ?masked(
                      Icon(
                        Icons.auto_stories_outlined,
                        size: 13,
                        color: infoColor,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  // 左欄通常放較長的書名／章節名，佔剩餘空間並先被刪節；
                  // 右欄放短的進度或時間，最多佔一半寬度，盡量完整顯示。
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: left ?? const SizedBox.shrink(),
                            ),
                          ),
                          if (left != null && right != null)
                            const SizedBox(width: AppSpacing.md),
                          if (right != null)
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth / 2,
                              ),
                              child: right,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _itemWidget(
    BuildContext context,
    ReaderV2InfoItem item,
    HybridProgressSnapshot? progress,
    TextAlign align,
  ) {
    if (item == ReaderV2InfoItem.none) return null;
    if (item == ReaderV2InfoItem.time) return _ReaderClock(textAlign: align);
    if (item == ReaderV2InfoItem.battery ||
        item == ReaderV2InfoItem.batteryWithIcon) {
      return _ReaderBattery(
        showIcon: item == ReaderV2InfoItem.batteryWithIcon,
        iconColor: shell.infoColor,
      );
    }
    return Text(_itemText(context, item, progress) ?? '', textAlign: align);
  }

  String? _itemSemantics(
    BuildContext context,
    ReaderV2InfoItem item,
    HybridProgressSnapshot? progress,
  ) {
    if (item == ReaderV2InfoItem.time) {
      return '時間 ${DateFormat('HH:mm').format(DateTime.now())}';
    }
    if (item == ReaderV2InfoItem.battery ||
        item == ReaderV2InfoItem.batteryWithIcon) {
      final battery = ReaderV2DeviceChannel.latestBattery;
      return battery == null ? null : '電量 ${battery.percent}%';
    }
    return _itemText(context, item, progress);
  }

  String? _itemText(
    BuildContext context,
    ReaderV2InfoItem item,
    HybridProgressSnapshot? progress,
  ) {
    final navigation = shell.navigation;
    return switch (item) {
      ReaderV2InfoItem.none ||
      ReaderV2InfoItem.time ||
      ReaderV2InfoItem.battery ||
      ReaderV2InfoItem.batteryWithIcon => null,
      ReaderV2InfoItem.bookName => context.zh(shell.book.name),
      ReaderV2InfoItem.chapterTitle => shell.chapterTitle,
      ReaderV2InfoItem.chapterIndex =>
        progress?.chapterIndexLabel ??
            (navigation.chapterCount > 0
                ? '${navigation.currentIndex + 1}/${navigation.chapterCount}'
                : '…'),
      ReaderV2InfoItem.chapterProgress =>
        progress?.chapterProgressLabel ?? '本章 …',
      ReaderV2InfoItem.bookProgress => progress?.bookPercentLabel ?? '…%',
    };
  }
}

/// 載入中的一個資訊欄位：照真正內容排版但不畫出，在它佔的寬度上畫一條
/// 和字一樣高的圓角條（同 [SkeletonLine]），資訊淡入時位置不動。
class _InfoItemSkeleton extends StatelessWidget {
  const _InfoItemSkeleton({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fontSize = MediaQuery.textScalerOf(context)
        .scale(DefaultTextStyle.of(context).style.fontSize ?? 14);
    return Stack(
      alignment: Alignment.center,
      children: [
        Visibility.maintain(visible: false, child: child),
        Positioned.fill(
          child: Center(
            child: SkeletonBox(
              width: double.infinity,
              height: fontSize * Skeleton.barHeightFactor,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// 頁首／頁尾的電量；只在系統回報電量變化時重建。
class _ReaderBattery extends StatefulWidget {
  const _ReaderBattery({required this.showIcon, required this.iconColor});

  final bool showIcon;
  final Color iconColor;

  @override
  State<_ReaderBattery> createState() => _ReaderBatteryState();
}

class _ReaderBatteryState extends State<_ReaderBattery> {
  StreamSubscription<ReaderV2Battery>? _subscription;
  ReaderV2Battery? _battery = ReaderV2DeviceChannel.latestBattery;

  @override
  void initState() {
    super.initState();
    _subscription = ReaderV2DeviceChannel.battery.listen(
      (battery) {
        if (mounted) setState(() => _battery = battery);
      },
      // 非 Android 平台沒有原生端；維持佔位顯示，不影響閱讀。
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final battery = _battery;
    final text = Text(battery == null ? '…%' : '${battery.percent}%');
    if (!widget.showIcon) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_iconFor(battery), size: 13, color: widget.iconColor),
        const SizedBox(width: 2),
        Flexible(child: text),
      ],
    );
  }

  static IconData _iconFor(ReaderV2Battery? battery) {
    if (battery == null) return Icons.battery_unknown_outlined;
    if (battery.charging) return Icons.battery_charging_full;
    final percent = battery.percent;
    if (percent >= 95) return Icons.battery_full;
    if (percent >= 80) return Icons.battery_6_bar;
    if (percent >= 65) return Icons.battery_5_bar;
    if (percent >= 50) return Icons.battery_4_bar;
    if (percent >= 35) return Icons.battery_3_bar;
    if (percent >= 20) return Icons.battery_2_bar;
    if (percent >= 8) return Icons.battery_1_bar;
    return Icons.battery_0_bar;
  }
}

/// 頁首／頁尾的時鐘；只在分鐘變化時重建。
class _ReaderClock extends StatefulWidget {
  const _ReaderClock({required this.textAlign});

  final TextAlign textAlign;

  @override
  State<_ReaderClock> createState() => _ReaderClockState();
}

class _ReaderClockState extends State<_ReaderClock> {
  static final DateFormat _format = DateFormat('HH:mm');
  Timer? _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _scheduleTick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleTick() {
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _timer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(_format.format(_now), textAlign: widget.textAlign);
  }
}

class _ReaderV2ControlsDismissLayer extends StatefulWidget {
  const _ReaderV2ControlsDismissLayer({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  State<_ReaderV2ControlsDismissLayer> createState() =>
      _ReaderV2ControlsDismissLayerState();
}

class _ReaderV2ControlsDismissLayerState
    extends State<_ReaderV2ControlsDismissLayer> {
  int? _pointer;
  Offset? _downPosition;
  bool _dismissed = false;

  /// 裝置觸控門檻的平方（照 [TapGestureRecognizer]）：移動超過它就收起選單，
  /// 和正文開始捲動用同一個門檻。
  late double _slopSquared;

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) {
      _resetTracking();
      return;
    }
    if (_pointer != null) {
      _resetTracking();
      return;
    }
    _pointer = event.pointer;
    _downPosition = event.position;
    _dismissed = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _dismissed) return;
    final downPosition = _downPosition;
    if (downPosition == null) return;
    if ((event.position - downPosition).distanceSquared > _slopSquared) {
      _dismissed = true;
      widget.onDismiss();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final downPosition = _downPosition;
    final shouldDismiss =
        !_dismissed &&
        downPosition != null &&
        (event.position - downPosition).distanceSquared <= _slopSquared;
    _resetTracking();
    if (shouldDismiss) widget.onDismiss();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) _resetTracking();
  }

  void _resetTracking() {
    _pointer = null;
    _downPosition = null;
    _dismissed = false;
  }

  @override
  Widget build(BuildContext context) {
    final slop =
        MediaQuery.maybeGestureSettingsOf(context)?.touchSlop ?? kTouchSlop;
    _slopSquared = slop * slop;
    // 不擋住底下的正文：在正文上滑動會收起選單，同一次手勢也照常捲動。
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: const SizedBox.expand(),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/services/chinese_display.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_constants.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_top_menu.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_device_channel.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

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
  /// [footerOffset] 為頁尾資訊列底部到畫面底部的距離；null 表示跟隨系統
  /// 底部內距。
  factory ReaderV2PageChromeLayout.resolve({
    required EdgeInsets mediaPadding,
    double? topCutoutExtent,
    required bool hideStatusBar,
    required bool showHeaderInfo,
    required bool showFooterInfo,
    required double paddingTop,
    required double paddingBottom,
    double? footerOffset,
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
    final footerRowBottom =
        footerOffset ?? mediaPadding.bottom + kReaderFooterAutoSpacing;
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
    required this.controlsVisible,
    required this.showReadTitleAddition,
    required this.hasVisibleContent,
    required this.isLoading,
    required this.chapterTitle,
    required this.chapterUrl,
    required this.originName,
    this.progressListenable,
    required this.navigation,
    required this.isAutoPaging,
    required this.hideStatusBar,
    required this.headerInfo,
    required this.footerInfo,
    required this.paddingTop,
    required this.paddingBottom,
    this.footerOffset,
    this.topCutoutExtent,
    required this.dayNightIcon,
    required this.dayNightTooltip,
    required this.onExitIntent,
    required this.onSystemBack,
    required this.onMore,
    required this.onOpenDrawer,
    required this.onTts,
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
    this.showTts = true,
    this.showAutoPage = true,
    this.showReplaceRule = true,
  });

  final Book book;
  final GlobalKey<ScaffoldState> scaffoldKey;
  final Widget content;
  final ReaderV2ChaptersDrawer drawer;
  final Color backgroundColor;

  /// 頁首／頁尾資訊列的文字與圖示色。
  final Color infoColor;
  final bool controlsVisible;
  final bool showReadTitleAddition;
  final bool hasVisibleContent;
  final bool isLoading;
  final String chapterTitle;
  final String chapterUrl;
  final String originName;
  final ValueListenable<HybridProgressSnapshot?>? progressListenable;
  final ReaderV2ChapterNavigationState navigation;
  final bool isAutoPaging;
  final bool hideStatusBar;
  final ReaderV2InfoSlots headerInfo;
  final ReaderV2InfoSlots footerInfo;
  final double paddingTop;
  final double paddingBottom;

  /// 頁尾資訊列底部到畫面底部的距離；null 表示跟隨系統底部內距。
  final double? footerOffset;

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
  final bool showTts;
  final bool showAutoPage;
  final bool showReplaceRule;

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
    final infoVisible = hasVisibleContent && !isLoading;
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
              Positioned.fill(
                top: layout.contentTop,
                bottom: layout.contentBottom,
                child: content,
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
                      child: layout.showHeaderInfo && infoVisible
                          ? Padding(
                              padding: EdgeInsets.only(
                                top: layout.headerRowTop,
                              ),
                              child: Center(
                                child: _InfoRow(
                                  shell: this,
                                  slots: headerInfo,
                                  showAutoPage:
                                      isAutoPaging && !autoPageInFooter,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              if (layout.showFooterInfo && infoVisible)
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
              ReaderV2TopMenu(
                controlsVisible: controlsVisible,
                bookName: context.zh(book.name),
                chapterTitle: chapterTitle,
                chapterUrl: chapterUrl,
                originName: originName,
                showReadTitleAddition: showReadTitleAddition,
                onBack: onExitIntent,
                onMore: onMore,
              ),
              ReaderV2BottomMenu(
                controlsVisible: controlsVisible,
                navigation: navigation,
                isAutoPaging: isAutoPaging,
                dayNightIcon: dayNightIcon,
                dayNightTooltip: dayNightTooltip,
                onOpenDrawer: onOpenDrawer,
                onTts: onTts,
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
                showTts: showTts,
                showAutoPage: showAutoPage,
                showReplaceRule: showReplaceRule,
              ),
            ],
          ),
        ),
        drawer: drawer,
      ),
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
          child: _InfoRow(
            shell: shell,
            slots: shell.footerInfo,
            showAutoPage: shell.isAutoPaging,
            rowHeight: kReaderFooterRowHeight,
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
  });

  final ReaderV2PageShell shell;
  final ReaderV2InfoSlots slots;
  final bool showAutoPage;
  final double rowHeight;

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
    final left = _itemWidget(context, slots.left, progress, TextAlign.left);
    final right = _itemWidget(context, slots.right, progress, TextAlign.right);
    final semantics = [
      if (showAutoPage) '自動翻頁中',
      ?_itemSemantics(context, slots.left, progress),
      ?_itemSemantics(context, slots.right, progress),
    ].join('，');
    return Semantics(
      container: true,
      label: semantics,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    Icon(
                      Icons.auto_stories_outlined,
                      size: 13,
                      color: infoColor,
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

const double _controlsDismissTapToleranceSquared = kTouchSlop * kTouchSlop;
const double _controlsDismissDragToleranceSquared = kTouchSlop * kTouchSlop;

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
    if ((event.position - downPosition).distanceSquared >
        _controlsDismissDragToleranceSquared) {
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
        (event.position - downPosition).distanceSquared <=
            _controlsDismissTapToleranceSquared;
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

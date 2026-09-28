import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_constants.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_top_menu.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_typography.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/settings/theme_settings_provider.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

/// 閱讀頁面框架的垂直幾何：頁首、正文、頁尾各佔的高度。
///
/// 頁首佔用狀態列（或隱藏狀態列後剩下的鏡頭挖孔區）；有資訊時，
/// 狀態列顯示中會在其下方多一條資訊列，隱藏時則直接把資訊放進該區。
/// 使用者的上／下邊距只加在正文與頁首、頁尾之間，不影響資訊列本身。
@immutable
final class ReaderV2PageChromeLayout {
  const ReaderV2PageChromeLayout._({
    required this.headerExtent,
    required this.headerRowTop,
    required this.footerExtent,
    required this.contentTop,
    required this.contentBottom,
    required this.showHeaderInfo,
    required this.showFooterInfo,
  });

  factory ReaderV2PageChromeLayout.resolve({
    required EdgeInsets mediaPadding,
    required bool hideStatusBar,
    required bool showHeaderInfo,
    required bool showFooterInfo,
    required double paddingTop,
    required double paddingBottom,
  }) {
    final top = mediaPadding.top;
    final double headerExtent;
    final double headerRowTop;
    if (!showHeaderInfo) {
      headerExtent = top;
      headerRowTop = top;
    } else if (hideStatusBar) {
      headerExtent = top > kReaderInfoRowHeight
          ? top
          : kReaderInfoRowHeight;
      headerRowTop = 0;
    } else {
      headerExtent = top + kReaderInfoRowHeight;
      headerRowTop = top;
    }
    final footerExtent = showFooterInfo
        ? mediaPadding.bottom + kReaderPermanentInfoReservedHeight
        : mediaPadding.bottom;
    return ReaderV2PageChromeLayout._(
      headerExtent: headerExtent,
      headerRowTop: headerRowTop,
      footerExtent: footerExtent,
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
    required this.textColor,
    required this.menuBackgroundColor,
    required this.menuTextColor,
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
    required this.dayNightIcon,
    required this.dayNightTooltip,
    required this.onExitIntent,
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
  final Color textColor;
  final Color menuBackgroundColor;
  final Color menuTextColor;
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
  final IconData dayNightIcon;
  final String dayNightTooltip;
  final VoidCallback onExitIntent;
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
      hideStatusBar: hideStatusBar,
      showHeaderInfo: showReadTitleAddition && !headerInfo.isEmpty,
      showFooterInfo: showReadTitleAddition && !footerInfo.isEmpty,
      paddingTop: paddingTop,
      paddingBottom: paddingBottom,
    );
    final infoVisible = hasVisibleContent && !isLoading;
    // 自動翻頁提示放在頁尾；頁尾關閉時改放頁首。
    final autoPageInFooter = layout.showFooterInfo;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        onExitIntent();
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
                    onTapDown: (_) => onShowControls(),
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
                    onTapDown: (_) => onShowControls(),
                    child: _PermanentInfoBar(shell: this),
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
                menuBackgroundColor: menuBackgroundColor,
                menuTextColor: menuTextColor,
                bookName: book.name,
                chapterTitle: chapterTitle,
                chapterUrl: chapterUrl,
                originName: originName,
                showReadTitleAddition: showReadTitleAddition,
                onBack: onExitIntent,
                onMore: onMore,
              ),
              ReaderV2BottomMenu(
                controlsVisible: controlsVisible,
                menuBackgroundColor: menuBackgroundColor,
                menuTextColor: menuTextColor,
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

/// 資訊列的配色：跟隨正文區自訂色，未自訂時以正文文字色降低不透明度。
({Color info, Color accent, Color? border}) _infoColors(ReaderV2PageShell shell) {
  final dark = shell.backgroundColor.computeLuminance() < 0.5;
  final custom = ThemeSettingsProvider.resolveReaderAreaColors(
    dark: dark,
    menu: false,
  );
  final info = custom?.secondaryText ?? shell.textColor.withValues(alpha: 0.68);
  return (info: info, accent: custom?.accent ?? info, border: custom?.border);
}

class _PermanentInfoBar extends StatelessWidget {
  const _PermanentInfoBar({required this.shell});

  final ReaderV2PageShell shell;

  @override
  Widget build(BuildContext context) {
    final colors = _infoColors(shell);
    final borderColor = colors.border;
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
        border: borderColor == null
            ? null
            : Border(
                top: BorderSide(color: borderColor.withValues(alpha: 0.45)),
              ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: kReaderPermanentInfoTopPadding,
          bottom:
              MediaQuery.paddingOf(context).bottom +
              kReaderPermanentInfoBottomSpacing,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: _InfoRow(
            shell: shell,
            slots: shell.footerInfo,
            showAutoPage: shell.isAutoPaging,
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
  });

  final ReaderV2PageShell shell;
  final ReaderV2InfoSlots slots;
  final bool showAutoPage;

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
    final colors = _infoColors(shell);
    final left = _itemWidget(slots.left, progress, TextAlign.left);
    final right = _itemWidget(slots.right, progress, TextAlign.right);
    final semantics = [
      if (showAutoPage) '自動翻頁中',
      ?_itemSemantics(slots.left, progress),
      ?_itemSemantics(slots.right, progress),
    ].join('，');
    return Semantics(
      container: true,
      label: semantics,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DefaultTextStyle(
            style: AppTextStyles.uiXs.copyWith(
              color: colors.info,
              fontWeight: FontWeight.w400,
              locale: kReaderV2TextLocale,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: SizedBox(
              height: kReaderInfoRowHeight,
              child: Row(
                children: [
                  if (showAutoPage) ...[
                    Icon(
                      Icons.auto_stories_outlined,
                      size: 13,
                      color: colors.accent,
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
    ReaderV2InfoItem item,
    HybridProgressSnapshot? progress,
    TextAlign align,
  ) {
    if (item == ReaderV2InfoItem.none) return null;
    if (item == ReaderV2InfoItem.time) return _ReaderClock(textAlign: align);
    return Text(_itemText(item, progress) ?? '', textAlign: align);
  }

  String? _itemSemantics(ReaderV2InfoItem item, HybridProgressSnapshot? progress) {
    if (item == ReaderV2InfoItem.time) {
      return '時間 ${DateFormat('HH:mm').format(DateTime.now())}';
    }
    return _itemText(item, progress);
  }

  String? _itemText(ReaderV2InfoItem item, HybridProgressSnapshot? progress) {
    final navigation = shell.navigation;
    return switch (item) {
      ReaderV2InfoItem.none || ReaderV2InfoItem.time => null,
      ReaderV2InfoItem.bookName => shell.book.name,
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
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: const SizedBox.expand(),
    );
  }
}

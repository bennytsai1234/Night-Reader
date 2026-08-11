import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_constants.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_top_menu.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';

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
    required this.displayPageLabel,
    required this.displayChapterPercentLabel,
    this.progressListenable,
    required this.navigation,
    required this.isAutoPaging,
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
  final String displayPageLabel;
  final String displayChapterPercentLabel;
  final ValueListenable<HybridProgressSnapshot?>? progressListenable;
  final ReaderV2ChapterNavigationState navigation;
  final bool isAutoPaging;
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
    final topSystemExtent = _topSystemExtent(context);
    final permanentInfoExtent =
        showReadTitleAddition ? _permanentInfoExtent(context) : 0.0;
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
                top: topSystemExtent,
                bottom: permanentInfoExtent,
                child: content,
              ),
              if (topSystemExtent > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: topSystemExtent,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => onShowControls(),
                    child: _TopSystemInfoBar(shell: this),
                  ),
                ),
              if (_shouldShowPermanentInfo())
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: permanentInfoExtent,
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

  bool _shouldShowPermanentInfo() {
    return hasVisibleContent && !isLoading && showReadTitleAddition;
  }

  double _permanentInfoExtent(BuildContext context) {
    return MediaQuery.paddingOf(context).bottom +
        kReaderPermanentInfoReservedHeight;
  }

  double _topSystemExtent(BuildContext context) {
    return MediaQuery.paddingOf(context).top;
  }
}

class _TopSystemInfoBar extends StatelessWidget {
  const _TopSystemInfoBar({required this.shell});

  final ReaderV2PageShell shell;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: shell.backgroundColor);
  }
}

class _PermanentInfoBar extends StatelessWidget {
  const _PermanentInfoBar({required this.shell});

  final ReaderV2PageShell shell;

  @override
  Widget build(BuildContext context) {
    final progressListenable = shell.progressListenable;
    if (progressListenable == null) {
      return _buildBar(context, null);
    }
    return ValueListenableBuilder<HybridProgressSnapshot?>(
      valueListenable: progressListenable,
      builder: (context, progress, _) => _buildBar(context, progress),
    );
  }

  Widget _buildBar(BuildContext context, HybridProgressSnapshot? progress) {
    final chapterLabel = progress?.chapterLabel ?? shell.displayPageLabel;
    final percentLabel =
        progress?.percentLabel ?? shell.displayChapterPercentLabel;
    final statusLabel = [
      shell.book.name,
      chapterLabel,
      percentLabel,
      if (shell.isAutoPaging) '自動翻頁中',
    ].join('，');
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
      child: Semantics(
        container: true,
        label: statusLabel,
        child: ExcludeSemantics(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              kReaderPermanentInfoTopPadding,
              16,
              MediaQuery.of(context).padding.bottom +
                  kReaderPermanentInfoBottomSpacing,
            ),
            child: DefaultTextStyle(
              style: TextStyle(
                color: shell.textColor.withValues(alpha: 0.68),
                fontSize: 11,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (shell.isAutoPaging) ...[
                          Icon(
                            Icons.auto_stories_outlined,
                            size: 13,
                            color: shell.textColor.withValues(alpha: 0.68),
                          ),
                          const SizedBox(width: 4),
                          const Text('自動翻頁中'),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            shell.book.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      chapterLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(percentLabel, maxLines: 1, textAlign: TextAlign.right),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

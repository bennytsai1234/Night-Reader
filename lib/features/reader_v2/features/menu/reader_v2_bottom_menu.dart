import 'package:flutter/material.dart';
import 'reader_v2_menu_palette.dart';

class ReaderV2ChapterNavigationState {
  const ReaderV2ChapterNavigationState({
    required this.chapterCount,
    required this.currentIndex,
    required this.isScrubbing,
    required this.scrubIndex,
    required this.pendingIndex,
    required this.titleFor,
  });

  final int chapterCount;
  final int currentIndex;
  final bool isScrubbing;
  final int scrubIndex;
  final int? pendingIndex;
  final String Function(int index) titleFor;

  bool get hasPending => pendingIndex != null;
  bool get canNavigateToPrev => chapterCount > 1 && currentIndex > 0;
  bool get canNavigateToNext =>
      chapterCount > 1 && currentIndex < chapterCount - 1;
  int get displayIndex =>
      isScrubbing ? scrubIndex : (pendingIndex ?? currentIndex);
}

class ReaderV2BottomMenu extends StatelessWidget {
  const ReaderV2BottomMenu({
    super.key,
    required this.controlsVisible,
    required this.menuBackgroundColor,
    required this.menuTextColor,
    required this.navigation,
    required this.isAutoPaging,
    required this.autoPageSpeed,
    required this.dayNightIcon,
    required this.dayNightTooltip,
    required this.onOpenDrawer,
    required this.onTts,
    required this.onInterface,
    required this.onSettings,
    required this.onAutoPage,
    required this.onAutoPageSpeedChanged,
    required this.onToggleDayNight,
    required this.onReplaceRule,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onScrubStart,
    required this.onScrubbing,
    required this.onScrubEnd,
    this.showTts = true,
    this.showAutoPage = true,
    this.showReplaceRule = true,
  });

  final bool controlsVisible;
  final Color menuBackgroundColor;
  final Color menuTextColor;
  final ReaderV2ChapterNavigationState navigation;
  final bool isAutoPaging;
  final double autoPageSpeed;
  final IconData dayNightIcon;
  final String dayNightTooltip;
  final VoidCallback onOpenDrawer;
  final VoidCallback onTts;
  final VoidCallback onInterface;
  final VoidCallback onSettings;
  final VoidCallback onAutoPage;
  final ValueChanged<double> onAutoPageSpeedChanged;
  final VoidCallback onToggleDayNight;
  final VoidCallback onReplaceRule;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final VoidCallback onScrubStart;
  final ValueChanged<int> onScrubbing;
  final ValueChanged<int> onScrubEnd;
  final bool showTts;
  final bool showAutoPage;
  final bool showReplaceRule;

  @override
  Widget build(BuildContext context) {
    final menuStyle = ReaderV2MenuStyle.resolve(
      context: context,
      backgroundColor: menuBackgroundColor,
      textColor: menuTextColor,
    );
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !controlsVisible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          offset: controlsVisible ? Offset.zero : const Offset(0, 1.15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFloatingButtons(menuStyle),
              Container(
                padding: EdgeInsets.fromLTRB(
                  0,
                  8,
                  0,
                  MediaQuery.of(context).padding.bottom + 8,
                ),
                decoration: BoxDecoration(
                  color: menuStyle.background,
                  border: Border(top: BorderSide(color: menuStyle.outline)),
                  boxShadow: [
                    BoxShadow(
                      color: menuStyle.scrim,
                      blurRadius: 18,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showAutoPage) ...[
                      _buildAutoPageSpeed(menuStyle),
                      const SizedBox(height: 4),
                    ],
                    _buildChapterSlider(context, menuStyle),
                    const SizedBox(height: 8),
                    _buildMainActions(menuStyle),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingButtons(ReaderV2MenuStyle menuStyle) {
    final actions = <Widget>[
      if (showAutoPage)
        _floatingFab(
          icon: Icons.auto_stories_outlined,
          tooltip: isAutoPaging ? '停止自動翻頁' : '開始自動翻頁',
          onTap: onAutoPage,
          menuStyle: menuStyle,
          active: isAutoPaging,
        ),
      if (showReplaceRule)
        _floatingFab(
          icon: Icons.find_replace,
          tooltip: '替換規則',
          onTap: onReplaceRule,
          menuStyle: menuStyle,
        ),
      _floatingFab(
        icon: dayNightIcon,
        tooltip: dayNightTooltip,
        onTap: onToggleDayNight,
        menuStyle: menuStyle,
      ),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: actions,
      ),
    );
  }

  Widget _floatingFab({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required ReaderV2MenuStyle menuStyle,
    bool active = false,
  }) {
    return FloatingActionButton.small(
      heroTag: null,
      onPressed: onTap,
      tooltip: tooltip,
      backgroundColor: menuStyle.backgroundElevated,
      foregroundColor: active ? menuStyle.accent : menuStyle.foreground,
      child: Icon(icon),
    );
  }

  Widget _buildChapterSlider(
    BuildContext context,
    ReaderV2MenuStyle menuStyle,
  ) {
    final maxVal =
        (navigation.chapterCount <= 1 ? 0 : navigation.chapterCount - 1)
            .toDouble();
    final displayIndex = navigation.displayIndex.clamp(
      0,
      navigation.chapterCount <= 0 ? 0 : navigation.chapterCount - 1,
    );
    final displayTitle =
        navigation.chapterCount > 0 ? navigation.titleFor(displayIndex) : '';
    final canChangeChapter =
        navigation.chapterCount > 1 && !navigation.hasPending;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((navigation.isScrubbing || navigation.hasPending) &&
              displayTitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (navigation.hasPending) ...[
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          menuStyle.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      displayTitle,
                      style: TextStyle(
                        color: menuStyle.mutedForeground,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              TextButton(
                onPressed: navigation.canNavigateToPrev ? onPrevChapter : null,
                style: TextButton.styleFrom(
                  foregroundColor: menuStyle.foreground,
                ),
                child: const Text('上一章', style: TextStyle(fontSize: 14)),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                  ),
                  child: Slider(
                    value: displayIndex.toDouble().clamp(0, maxVal),
                    min: 0,
                    max: maxVal,
                    onChangeStart:
                        canChangeChapter ? (_) => onScrubStart() : null,
                    onChanged:
                        canChangeChapter ? (v) => onScrubbing(v.toInt()) : null,
                    onChangeEnd:
                        canChangeChapter ? (v) => onScrubEnd(v.toInt()) : null,
                    activeColor: menuStyle.accent,
                    inactiveColor: menuStyle.mutedForeground.withValues(
                      alpha: 0.24,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: navigation.canNavigateToNext ? onNextChapter : null,
                style: TextButton.styleFrom(
                  foregroundColor: menuStyle.foreground,
                ),
                child: const Text('下一章', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAutoPageSpeed(ReaderV2MenuStyle menuStyle) {
    final value = autoPageSpeed.clamp(0.08, 0.45).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Icon(Icons.speed_rounded, color: menuStyle.foreground, size: 18),
          const SizedBox(width: 10),
          Text(
            '自動翻頁',
            style: TextStyle(color: menuStyle.foreground, fontSize: 12),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: menuStyle.accent,
                inactiveTrackColor: menuStyle.mutedForeground.withValues(
                  alpha: 0.24,
                ),
                thumbColor: menuStyle.accent,
              ),
              child: Slider(
                value: value,
                min: 0.08,
                max: 0.45,
                divisions: 37,
                onChanged: onAutoPageSpeedChanged,
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.end,
              style: TextStyle(color: menuStyle.mutedForeground, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainActions(ReaderV2MenuStyle menuStyle) {
    final actions = <Widget>[
      _menuIcon(Icons.list, '目錄', onOpenDrawer, menuStyle),
      if (showTts) _menuIcon(Icons.record_voice_over, '朗讀', onTts, menuStyle),
      _menuIcon(Icons.color_lens, '介面', onInterface, menuStyle),
      _menuIcon(Icons.settings, '設定', onSettings, menuStyle),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: actions,
    );
  }

  Widget _menuIcon(
    IconData icon,
    String label,
    VoidCallback onTap,
    ReaderV2MenuStyle menuStyle,
  ) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 70,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: menuStyle.foreground, size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(color: menuStyle.foreground, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

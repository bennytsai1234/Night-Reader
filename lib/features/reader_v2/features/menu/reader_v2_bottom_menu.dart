import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'reader_v2_menu_palette.dart';

class ReaderV2ChapterNavigationState {
  const ReaderV2ChapterNavigationState({
    required this.chapterCount,
    required this.currentIndex,
    required this.isScrubbing,
    required this.scrubPercent,
    required this.titleFor,
  });

  final int chapterCount;
  final int currentIndex;
  final bool isScrubbing;

  /// 拖動中的章內進度（0–100）。
  final double scrubPercent;
  final String Function(int index) titleFor;

  bool get canNavigateToPrev => chapterCount > 1 && currentIndex > 0;
  bool get canNavigateToNext =>
      chapterCount > 1 && currentIndex < chapterCount - 1;
}

class ReaderV2BottomMenu extends StatelessWidget {
  const ReaderV2BottomMenu({
    super.key,
    required this.controlsVisible,
    required this.menuBackgroundColor,
    required this.menuTextColor,
    required this.navigation,
    required this.isAutoPaging,
    required this.dayNightIcon,
    required this.dayNightTooltip,
    required this.onOpenDrawer,
    required this.onTts,
    required this.onInterface,
    required this.onSettings,
    required this.onAutoPage,
    required this.onToggleDayNight,
    required this.onReplaceRule,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onScrubStart,
    required this.onScrubbing,
    required this.onScrubEnd,
    this.progressListenable,
    this.showTts = true,
    this.showAutoPage = true,
    this.showReplaceRule = true,
  });

  final bool controlsVisible;
  final Color menuBackgroundColor;
  final Color menuTextColor;
  final ReaderV2ChapterNavigationState navigation;
  final bool isAutoPaging;
  final IconData dayNightIcon;
  final String dayNightTooltip;
  final VoidCallback onOpenDrawer;
  final VoidCallback onTts;
  final VoidCallback onInterface;
  final VoidCallback onSettings;
  final VoidCallback onAutoPage;
  final VoidCallback onToggleDayNight;
  final VoidCallback onReplaceRule;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;
  final ValueChanged<double> onScrubStart;
  final ValueChanged<double> onScrubbing;
  final ValueChanged<double> onScrubEnd;

  /// 章內進度的窄通道；未拖動時拖動條跟隨此值即時顯示。
  final ValueListenable<HybridProgressSnapshot?>? progressListenable;
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
    final canScrub = navigation.chapterCount > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (navigation.isScrubbing)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '本章 ${(navigation.scrubPercent / 10).round()}/10',
                style: TextStyle(
                  color: menuStyle.mutedForeground,
                  fontSize: 11,
                ),
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
                  child: _buildProgressSlider(canScrub, menuStyle),
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

  /// 拖動條表示「本章內進度」，與資訊列同樣切成十等份：未拖動時跟隨
  /// 閱讀進度（經 progressListenable 窄通道，不觸發整頁 rebuild）；
  /// 拖動跨檔位時由外層做預覽跳轉，放開才落定存進度。
  Widget _buildProgressSlider(bool canScrub, ReaderV2MenuStyle menuStyle) {
    final listenable = progressListenable;
    if (listenable == null) {
      return _progressSlider(canScrub, menuStyle, currentPercent: 0);
    }
    return ValueListenableBuilder<HybridProgressSnapshot?>(
      valueListenable: listenable,
      builder: (context, progress, _) {
        return _progressSlider(
          canScrub,
          menuStyle,
          currentPercent: progress?.chapterPercent ?? 0,
        );
      },
    );
  }

  Widget _progressSlider(
    bool canScrub,
    ReaderV2MenuStyle menuStyle, {
    required double currentPercent,
  }) {
    final value =
        (navigation.isScrubbing ? navigation.scrubPercent : currentPercent)
            .clamp(0.0, 100.0)
            .toDouble();
    return Slider(
      value: value,
      min: 0,
      max: 100,
      divisions: 10,
      onChangeStart: canScrub ? onScrubStart : null,
      onChanged: canScrub ? onScrubbing : null,
      onChangeEnd: canScrub ? onScrubEnd : null,
      activeColor: menuStyle.accent,
      inactiveColor: menuStyle.mutedForeground.withValues(alpha: 0.24),
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

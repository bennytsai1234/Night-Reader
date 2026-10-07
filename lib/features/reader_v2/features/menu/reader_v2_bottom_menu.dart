import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/glass.dart';

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

/// 閱讀器下方選單：浮在手勢列上方的圓角玻璃膠囊（章節拖動條與主功能），
/// 膠囊上方另有一排圓形玻璃按鈕。
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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !controlsVisible,
        child: AnimatedSlide(
          duration: AppMotion.menu,
          curve: AppMotion.menuCurve,
          offset: controlsVisible ? Offset.zero : const Offset(0, 1.15),
          // 玻璃元件的亮邊與陰影取自選單配色推導的主題，而非 App 主題。
          child: Theme(
            data: menuStyle.toSheetTheme(Theme.of(context)),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppGrouped.margin,
                0,
                AppGrouped.margin,
                bottomInset + AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildFloatingButtons(menuStyle),
                  const SizedBox(height: AppSpacing.md),
                  GlassSurface(
                    borderRadius: AppRadius.cardXl,
                    tint: menuStyle.glassTint,
                    grouped: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.sm,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildChapterSlider(context, menuStyle),
                          const SizedBox(height: AppSpacing.xs),
                          _buildMainActions(menuStyle),
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

  /// 膠囊上方的圓形玻璃按鈕（自動翻頁、替換規則、日夜切換）。
  Widget _buildFloatingButtons(ReaderV2MenuStyle menuStyle) {
    final tint = menuStyle.glassTint;
    final actions = <Widget>[
      if (showAutoPage)
        GlassIconButton(
          icon: Icons.auto_stories_outlined,
          tooltip: isAutoPaging ? '停止自動翻頁' : '開始自動翻頁',
          tint: isAutoPaging
              ? Color.alphaBlend(menuStyle.accentMuted, tint)
              : tint,
          color: isAutoPaging ? menuStyle.accent : menuStyle.foreground,
          onPressed: onAutoPage,
        ),
      if (showReplaceRule)
        GlassIconButton(
          icon: Icons.find_replace,
          tooltip: '替換規則',
          tint: tint,
          color: menuStyle.foreground,
          onPressed: onReplaceRule,
        ),
      GlassIconButton(
        icon: dayNightIcon,
        tooltip: dayNightTooltip,
        tint: tint,
        color: menuStyle.foreground,
        onPressed: onToggleDayNight,
      ),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: actions,
    );
  }

  Widget _buildChapterSlider(
    BuildContext context,
    ReaderV2MenuStyle menuStyle,
  ) {
    final canScrub = navigation.chapterCount > 0;
    final track = menuStyle.mutedForeground.withValues(alpha: 0.24);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (navigation.isScrubbing)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              '本章 ${(navigation.scrubPercent / 10).round()}/10',
              style: AppTextStyles.labelXs.copyWith(
                color: menuStyle.mutedForeground,
              ),
            ),
          ),
        Row(
          children: [
            _chapterJumpButton(
              '上一章',
              navigation.canNavigateToPrev ? onPrevChapter : null,
              menuStyle,
            ),
            Expanded(
              // Telegram 式拖動條：細圓角軌道、帶柔和陰影的大圓鈕，無光暈與刻度。
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  trackShape: const RoundedRectSliderTrackShape(),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 13,
                    disabledThumbRadius: 13,
                    elevation: 2,
                    pressedElevation: 4,
                  ),
                  overlayShape: SliderComponentShape.noOverlay,
                  overlayColor: Colors.transparent,
                  tickMarkShape: SliderTickMarkShape.noTickMark,
                  activeTrackColor: menuStyle.accent,
                  inactiveTrackColor: track,
                  thumbColor: AppPalette.paper50,
                  disabledActiveTrackColor: track,
                  disabledInactiveTrackColor: track,
                  disabledThumbColor: Color.alphaBlend(
                    track,
                    AppPalette.paper50,
                  ),
                ),
                child: SizedBox(
                  // 圓鈕本身 26，觸控高度維持 44。
                  height: AppGlass.buttonSize,
                  child: _buildProgressSlider(canScrub),
                ),
              ),
            ),
            _chapterJumpButton(
              '下一章',
              navigation.canNavigateToNext ? onNextChapter : null,
              menuStyle,
            ),
          ],
        ),
      ],
    );
  }

  Widget _chapterJumpButton(
    String label,
    VoidCallback? onPressed,
    ReaderV2MenuStyle menuStyle,
  ) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: menuStyle.foreground,
        disabledForegroundColor: menuStyle.foreground.withValues(alpha: 0.38),
        textStyle: AppTextStyles.uiSm,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        minimumSize: const Size(AppGlass.buttonSize, AppGlass.buttonSize),
        shape: const StadiumBorder(),
      ),
      child: Text(label),
    );
  }

  /// 拖動條表示「本章內進度」，與資訊列同樣切成十等份：未拖動時跟隨
  /// 閱讀進度（經 progressListenable 窄通道，不觸發整頁 rebuild）；
  /// 拖動跨檔位時由外層做預覽跳轉，放開才落定存進度。
  Widget _buildProgressSlider(bool canScrub) {
    final listenable = progressListenable;
    if (listenable == null) {
      return _progressSlider(canScrub, currentPercent: 0);
    }
    return ValueListenableBuilder<HybridProgressSnapshot?>(
      valueListenable: listenable,
      builder: (context, progress, _) {
        return _progressSlider(
          canScrub,
          currentPercent: progress?.chapterPercent ?? 0,
        );
      },
    );
  }

  Widget _progressSlider(bool canScrub, {required double currentPercent}) {
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
    );
  }

  /// 膠囊內的主功能：圖示加小字標籤，按下微縮而不鋪水波紋。
  Widget _buildMainActions(ReaderV2MenuStyle menuStyle) {
    return Row(
      children: [
        _menuIcon(Icons.list_rounded, '目錄', onOpenDrawer, menuStyle),
        if (showTts)
          _menuIcon(Icons.record_voice_over_outlined, '朗讀', onTts, menuStyle),
        _menuIcon(Icons.format_paint_outlined, '排版', onInterface, menuStyle),
        _menuIcon(Icons.tune_rounded, '進階', onSettings, menuStyle),
      ],
    );
  }

  Widget _menuIcon(
    IconData icon,
    String label,
    VoidCallback onTap,
    ReaderV2MenuStyle menuStyle,
  ) {
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: PressScale(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: menuStyle.foreground, size: 24),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  style: AppTextStyles.uiXs.copyWith(
                    color: menuStyle.foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_sleep_timer.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/widgets/glass.dart';

import 'reader_v2_menu_entrance.dart';
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
    required this.navigation,
    required this.isAutoPaging,
    required this.dayNightIcon,
    required this.dayNightTooltip,
    required this.onOpenDrawer,
    required this.onTts,
    required this.onTimedTts,
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
    this.sleepTimer,
    this.isTtsPlaying = false,
    this.showTts = true,
    this.showAutoPage = true,
    this.showReplaceRule = true,
  });

  final bool controlsVisible;
  final ReaderV2ChapterNavigationState navigation;
  final bool isAutoPaging;
  final IconData dayNightIcon;
  final String dayNightTooltip;
  final VoidCallback onOpenDrawer;
  final VoidCallback onTts;

  /// 定時鍵：正在念就停止，否則照記住的定時開始朗讀。
  final VoidCallback onTimedTts;
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

  /// 朗讀定時；朗讀還沒準備好時為 null，不顯示定時鍵。
  final ReaderV2TtsSleepTimer? sleepTimer;
  final bool isTtsPlaying;
  final bool showTts;
  final bool showAutoPage;
  final bool showReplaceRule;

  @override
  Widget build(BuildContext context) {
    final menuStyle = ReaderV2MenuStyle.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ReaderV2MenuEntrance(
      visible: controlsVisible,
      edge: AxisDirection.down,
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
              _buildFloatingButtons(context, menuStyle),
              const SizedBox(height: AppSpacing.md),
              GlassSurface(
                borderRadius: AppRadius.cardXl,
                tint: menuStyle.glassTintOf(context),
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
    );
  }

  /// 膠囊上方的圓形玻璃按鈕（自動翻頁、替換規則、定時朗讀、日夜切換）。
  Widget _buildFloatingButtons(
    BuildContext context,
    ReaderV2MenuStyle menuStyle,
  ) {
    final tint = menuStyle.glassTintOf(context);
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
      if (sleepTimer case final timer? when showTts)
        _SleepTimerButton(
          timer: timer,
          isPlaying: isTtsPlaying,
          menuStyle: menuStyle,
          onPressed: onTimedTts,
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
        // 字級沿用 TextButton 預設的 labelLarge（主題裡就是 uiSm），自己帶
        // textStyle 會蓋掉主題的字族。
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
    return Semantics(
      label: '本章進度',
      child: Slider(
        value: value,
        min: 0,
        max: 100,
        divisions: 10,
        // 讀屏念出「本章 n/10」，和拖動時的提示一致，而不只是百分比。
        semanticFormatterCallback: (v) => '本章 ${(v / 10).round()}/10',
        onChangeStart: canScrub ? onScrubStart : null,
        onChanged: canScrub ? onScrubbing : null,
        onChangeEnd: canScrub ? onScrubEnd : null,
      ),
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

/// 定時朗讀鍵：倒數中以強調色顯示剩餘分鐘（無條件進位），沒有在倒數時是
/// 計時器圖示。倒數不逐秒通知，這裡只在顯示的分鐘數要變的那一刻重建。
class _SleepTimerButton extends StatefulWidget {
  const _SleepTimerButton({
    required this.timer,
    required this.isPlaying,
    required this.menuStyle,
    required this.onPressed,
  });

  final ReaderV2TtsSleepTimer timer;
  final bool isPlaying;
  final ReaderV2MenuStyle menuStyle;
  final VoidCallback onPressed;

  @override
  State<_SleepTimerButton> createState() => _SleepTimerButtonState();
}

class _SleepTimerButtonState extends State<_SleepTimerButton> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    widget.timer.addListener(_refresh);
    _scheduleTick();
  }

  @override
  void didUpdateWidget(_SleepTimerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timer == widget.timer) return;
    oldWidget.timer.removeListener(_refresh);
    widget.timer.addListener(_refresh);
    _scheduleTick();
  }

  @override
  void dispose() {
    widget.timer.removeListener(_refresh);
    _tick?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _scheduleTick();
  }

  /// 排到剩餘時間跨過下一個整分鐘的那一刻。
  void _scheduleTick() {
    _tick?.cancel();
    _tick = null;
    final remaining = widget.timer.remaining;
    if (remaining == null || remaining == Duration.zero) return;
    final intoMinute =
        remaining.inMicroseconds % Duration.microsecondsPerMinute;
    _tick = Timer(
      Duration(
        microseconds: intoMinute == 0
            ? Duration.microsecondsPerMinute
            : intoMinute,
      ),
      _refresh,
    );
  }

  @override
  Widget build(BuildContext context) {
    final timer = widget.timer;
    final menuStyle = widget.menuStyle;
    final remaining = timer.remaining;
    final label = remaining != null ? '${_ceilMinutes(remaining)}分' : null;
    final tint = menuStyle.glassTintOf(context);
    return GlassIconButton(
      icon: Icons.timer_outlined,
      label: label,
      tooltip: widget.isPlaying ? '停止朗讀' : '定時朗讀',
      tint: label != null
          ? Color.alphaBlend(menuStyle.accentMuted, tint)
          : tint,
      color: label != null ? menuStyle.accent : menuStyle.foreground,
      onPressed: widget.onPressed,
    );
  }

  static int _ceilMinutes(Duration remaining) {
    final minutes =
        (remaining.inMicroseconds + Duration.microsecondsPerMinute - 1) ~/
        Duration.microsecondsPerMinute;
    return minutes < 1 ? 1 : minutes;
  }
}

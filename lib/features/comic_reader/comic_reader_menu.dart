import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_entrance.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_palette.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

/// 漫畫閱讀選單下方那一塊要的進度：第幾話、本話第幾張、共幾張。
@immutable
class ComicMenuProgress {
  const ComicMenuProgress({
    required this.chapterIndex,
    required this.pageIndex,
    required this.pageCount,
  });

  final int chapterIndex;
  final int pageIndex;

  /// 這一話共幾張；還沒載好是 0。
  final int pageCount;

  @override
  bool operator ==(Object other) =>
      other is ComicMenuProgress &&
      other.chapterIndex == chapterIndex &&
      other.pageIndex == pageIndex &&
      other.pageCount == pageCount;

  @override
  int get hashCode => Object.hash(chapterIndex, pageIndex, pageCount);
}

/// 漫畫閱讀器的下方選單（`docs/design/comics.md`「閱讀選單」）：沿用文字
/// 閱讀器的外框與進出場——上排圓鈕（自動捲動、日夜切換），膠囊裡上一話、
/// 本話第幾張的拖動條、下一話，以及目錄、漫畫偏好。
class ComicReaderBottomMenu extends StatefulWidget {
  const ComicReaderBottomMenu({
    super.key,
    required this.controlsVisible,
    required this.progress,
    required this.chapterCount,
    required this.autoScrolling,
    required this.dayNightIcon,
    required this.dayNightTooltip,
    required this.onToggleAutoScroll,
    required this.onToggleDayNight,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onSeekPage,
    required this.onOpenChapters,
    required this.onPreferences,
  });

  final ValueListenable<bool> controlsVisible;
  final ValueListenable<ComicMenuProgress> progress;
  final int chapterCount;
  final ValueListenable<bool> autoScrolling;
  final IconData dayNightIcon;
  final String dayNightTooltip;
  final VoidCallback onToggleAutoScroll;
  final VoidCallback onToggleDayNight;
  final VoidCallback onPrevChapter;
  final VoidCallback onNextChapter;

  /// 放開拖動條：跳到本話第幾張（從 0 起）。
  final ValueChanged<int> onSeekPage;
  final VoidCallback onOpenChapters;
  final VoidCallback onPreferences;

  @override
  State<ComicReaderBottomMenu> createState() => _ComicReaderBottomMenuState();
}

class _ComicReaderBottomMenuState extends State<ComicReaderBottomMenu> {
  /// 拖動中的張數；沒在拖時是 null，拖動條跟著閱讀位置。
  int? _scrubbing;

  @override
  Widget build(BuildContext context) {
    final menuStyle = ReaderV2MenuStyle.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final tint = menuStyle.glassTintOf(context);
    return ReaderV2MenuEntrance(
      visible: widget.controlsVisible,
      edge: AxisDirection.down,
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.autoScrolling,
                    builder: (context, on, _) => GlassIconButton(
                      icon: Icons.keyboard_double_arrow_down_rounded,
                      tooltip: on ? '停止自動捲動' : '開始自動捲動',
                      tint: on
                          ? Color.alphaBlend(menuStyle.accentMuted, tint)
                          : tint,
                      color: on ? menuStyle.accent : menuStyle.foreground,
                      onPressed: widget.onToggleAutoScroll,
                    ),
                  ),
                  GlassIconButton(
                    icon: widget.dayNightIcon,
                    tooltip: widget.dayNightTooltip,
                    tint: tint,
                    color: menuStyle.foreground,
                    onPressed: widget.onToggleDayNight,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              GlassSurface(
                borderRadius: AppRadius.cardXl,
                tint: tint,
                grouped: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: ValueListenableBuilder<ComicMenuProgress>(
                    valueListenable: widget.progress,
                    builder: (context, progress, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _pageRow(context, menuStyle, progress),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Expanded(
                              child: ReaderV2MenuIcon(
                                icon: Icons.list_rounded,
                                label: '目錄',
                                onTap: widget.onOpenChapters,
                                menuStyle: menuStyle,
                              ),
                            ),
                            Expanded(
                              child: ReaderV2MenuIcon(
                                icon: Icons.tune_rounded,
                                label: '漫畫偏好',
                                onTap: widget.onPreferences,
                                menuStyle: menuStyle,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageRow(
    BuildContext context,
    ReaderV2MenuStyle menuStyle,
    ComicMenuProgress progress,
  ) {
    final count = progress.pageCount;
    final shown = (_scrubbing ?? progress.pageIndex).clamp(
      0,
      count < 1 ? 0 : count - 1,
    );
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: menuStyle.foreground,
      disabledForegroundColor: menuStyle.foreground.withValues(alpha: 0.38),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      minimumSize: const Size(AppGlass.buttonSize, AppGlass.buttonSize),
      shape: const StadiumBorder(),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count > 0 ? '第 ${shown + 1} / $count 張' : '',
          style: AppTextStyles.labelXs.copyWith(
            color: menuStyle.mutedForeground,
          ),
        ),
        Row(
          children: [
            TextButton(
              onPressed: progress.chapterIndex > 0
                  ? widget.onPrevChapter
                  : null,
              style: buttonStyle,
              child: const Text('上一話'),
            ),
            Expanded(
              child: SliderTheme(
                data: ReaderV2BottomMenu.sliderThemeOf(context, menuStyle),
                child: SizedBox(
                  height: AppGlass.buttonSize,
                  child: Semantics(
                    label: '本話第幾張',
                    child: Slider(
                      value: count > 1 ? shown.toDouble() : 0,
                      max: count > 1 ? (count - 1).toDouble() : 1,
                      divisions: count > 1 ? count - 1 : null,
                      semanticFormatterCallback: (v) =>
                          '第 ${v.round() + 1} / $count 張',
                      onChanged: count > 1
                          ? (v) => setState(() => _scrubbing = v.round())
                          : null,
                      onChangeEnd: count > 1
                          ? (v) {
                              setState(() => _scrubbing = null);
                              widget.onSeekPage(v.round());
                            }
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: progress.chapterIndex < widget.chapterCount - 1
                  ? widget.onNextChapter
                  : null,
              style: buttonStyle,
              child: const Text('下一話'),
            ),
          ],
        ),
      ],
    );
  }
}

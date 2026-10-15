import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/features/brightness/reader_v2_brightness.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_palette.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';

/// 閱讀選單左側的亮度條：上方一顆「自動」鈕，下方一條直立膠囊，亮度從下
/// 往上填滿。膠囊中的細線以下是加暗段（[ReaderV2Brightness.dimZone]），
/// 填色換成主色。跟隨系統時膠囊變淡，一拖就改成自己的亮度。
class ReaderV2BrightnessBar extends StatelessWidget {
  const ReaderV2BrightnessBar({
    super.key,
    required this.auto,
    required this.level,
    required this.onAutoChanged,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final bool auto;
  final double level;
  final ValueChanged<bool> onAutoChanged;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  static const double pillHeight = 180;

  @override
  Widget build(BuildContext context) {
    final menuStyle = ReaderV2MenuStyle.of(context);
    final tint = menuStyle.glassTintOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassIconButton(
          icon: Icons.brightness_auto_rounded,
          tooltip: auto ? '改用自訂亮度' : '亮度跟隨系統',
          tint: auto ? Color.alphaBlend(menuStyle.accentMuted, tint) : tint,
          color: auto ? menuStyle.accent : menuStyle.foreground,
          onPressed: () => onAutoChanged(!auto),
        ),
        const SizedBox(height: AppSpacing.md),
        _BrightnessPill(
          auto: auto,
          level: level,
          tint: tint,
          menuStyle: menuStyle,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}

class _BrightnessPill extends StatefulWidget {
  const _BrightnessPill({
    required this.auto,
    required this.level,
    required this.tint,
    required this.menuStyle,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final bool auto;
  final double level;
  final Color tint;
  final ReaderV2MenuStyle menuStyle;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_BrightnessPill> createState() => _BrightnessPillState();
}

class _BrightnessPillState extends State<_BrightnessPill> {
  static const double _height = ReaderV2BrightnessBar.pillHeight;
  static const double _step = 0.05;
  static const double _iconSize = 22;
  double? _dragLevel;

  double _levelAt(double dy) => (1 - dy / _height).clamp(0.0, 1.0).toDouble();

  void _update(double dy) {
    final level = _levelAt(dy);
    setState(() => _dragLevel = level);
    widget.onChanged(level);
  }

  void _end() {
    final level = _dragLevel;
    if (level == null) return;
    setState(() => _dragLevel = null);
    widget.onChangeEnd(level);
  }

  static double _clamp(double level) => level.clamp(0.0, 1.0).toDouble();

  static String _percent(double level) => '${(level * 100).round()}%';

  void _nudge(double delta) => widget.onChangeEnd(_clamp(widget.level + delta));

  @override
  Widget build(BuildContext context) {
    final menuStyle = widget.menuStyle;
    final level = _dragLevel ?? widget.level;
    final inDimZone = level < ReaderV2Brightness.dimZone;
    final fillColor = inDimZone ? menuStyle.accent : menuStyle.foreground;
    final fillOpacity = widget.auto && _dragLevel == null ? 0.3 : 0.85;
    // 圖示整個被填色蓋住時改用選單底色，否則用前景色。
    final iconCovered =
        fillOpacity > 0.5 && _height * level >= AppSpacing.md + _iconSize;
    return Semantics(
      slider: true,
      label: '亮度',
      value: widget.auto ? '跟隨系統' : _percent(level),
      increasedValue: _percent(_clamp(widget.level + _step)),
      decreasedValue: _percent(_clamp(widget.level - _step)),
      onIncrease: () => _nudge(_step),
      onDecrease: () => _nudge(-_step),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _update(details.localPosition.dy),
        onTapUp: (_) => _end(),
        onVerticalDragStart: (details) => _update(details.localPosition.dy),
        onVerticalDragUpdate: (details) => _update(details.localPosition.dy),
        onVerticalDragEnd: (_) => _end(),
        onVerticalDragCancel: _end,
        child: SizedBox(
          width: AppGlass.buttonSize,
          height: _height,
          child: GlassSurface(
            borderRadius: AppRadius.pillShape,
            tint: widget.tint,
            grouped: false,
            child: ClipRRect(
              borderRadius: AppRadius.pillShape,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: _height * level,
                    child: ColoredBox(
                      color: fillColor.withValues(alpha: fillOpacity),
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.md,
                    right: AppSpacing.md,
                    bottom: _height * ReaderV2Brightness.dimZone - 1,
                    height: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: menuStyle.mutedForeground.withValues(alpha: 0.6),
                        borderRadius: AppRadius.pillShape,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: AppSpacing.md,
                    child: Icon(
                      inDimZone
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      size: _iconSize,
                      color: iconCovered
                          ? menuStyle.background.withValues(alpha: 1)
                          : menuStyle.foreground,
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
}

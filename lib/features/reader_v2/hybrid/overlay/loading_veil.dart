import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:night_reader/core/services/motion_gate.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

/// 開書、跳章與重新排版時蓋在正文上的一張紙。
///
/// 排版期間整張紙蓋住，接在開書轉場後面看起來是同一張紙；蓋上時紙上就
/// 淡入照閱讀版面畫的正文骨架。正文排好後紙以骨架換場（[SkeletonReveal]，
/// 使用者選的方式與時長）淡出、露出正文，骨架跟著一起淡掉。
///
/// 只改紙與骨架顏色的透明度，不對正文做整頁 Opacity：載入期間排版用滿每
/// 一幀的預算，這一層每幀只多畫幾十個圓角條。
class LoadingVeilController {
  LoadingVeilController({required TickerProvider vsync, this.onHidden})
    : _cover = AnimationController(
        vsync: vsync,
        duration: AppMotion.fade,
        value: 1,
      ),
      _skeleton = AnimationController(vsync: vsync, duration: AppMotion.fade),
      _pulse = AnimationController(
        vsync: vsync,
        duration: AppMotion.skeletonPulse,
      ) {
    _cover.addStatusListener(_onCoverStatus);
    _skeleton.addStatusListener((_) => _syncHold());
  }

  /// 紙完全淡出時呼叫，呼叫端據此把 [LoadingVeil] 移出畫面。
  final VoidCallback? onHidden;

  /// 這一次掀紙是不是由左而右。
  bool _sweep = false;

  final AnimationController _cover;
  final AnimationController _skeleton;
  final AnimationController _pulse;
  late final Animation<double> _coverCurve = CurvedAnimation(
    parent: _cover,
    curve: AppMotion.fadeCurve,
  );
  late final Animation<double> _skeletonCurve = CurvedAnimation(
    parent: _skeleton,
    curve: AppMotion.fadeCurve,
  );
  late final Animation<double> _pulseCurve = CurvedAnimation(
    parent: _pulse,
    curve: AppMotion.fadeCurve,
  );
  int _attachedVeils = 0;
  bool _reduceMotion = false;

  /// 紙淡入淡出、骨架淡入與呼吸時持有 [MotionGate]（ADR 0018）。
  final MotionHold _hold = MotionHold();

  /// 系統要求減少動態（`MediaQuery.disableAnimations`）時，紙與骨架直接到位，
  /// 骨架不呼吸；中途切換時，進行中的淡出與淡入也直接跳到終點。
  set reduceMotion(bool value) {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    if (value) {
      if (_cover.isAnimating) _cover.value = 0;
      if (_skeleton.isAnimating) _skeleton.value = 1;
    }
    _syncPulse();
  }

  /// 紙還蓋著或正在淡出。
  bool get isVisible => !_cover.isDismissed;

  /// 蓋上整張紙，骨架從目前的濃淡繼續淡入（淡出途中再蓋上不會先閃空）。
  void cover() {
    _cover.value = 1;
    if (_reduceMotion) {
      _skeleton.value = 1;
    } else {
      unawaited(_skeleton.forward());
    }
    _syncPulse();
  }

  /// 正文已排好：照 [reveal] 的方式與時長掀開紙。
  void reveal([SkeletonReveal reveal = const SkeletonReveal()]) {
    if (_reduceMotion) {
      _cover.value = 0;
    } else {
      _sweep = reveal.sweeps;
      _cover.reverseDuration = reveal.duration;
      unawaited(_cover.reverse());
    }
  }

  void dispose() {
    _hold.release();
    _cover.dispose();
    _skeleton.dispose();
    _pulse.dispose();
  }

  void _onCoverStatus(AnimationStatus status) {
    _syncHold();
    if (status != AnimationStatus.dismissed) return;
    _skeleton.value = 0;
    _syncPulse();
    onHidden?.call();
  }

  void _attach() {
    _attachedVeils += 1;
    _syncPulse();
  }

  void _detach() {
    _attachedVeils -= 1;
    _syncPulse();
  }

  /// 呼吸只在骨架畫在畫面上時跑：載入失敗改顯示錯誤、或紙已淡出時都停，
  /// 不讓一個看不到的動畫持續要求重畫。
  void _syncPulse() {
    final run =
        _attachedVeils > 0 &&
        !_reduceMotion &&
        !_cover.isDismissed &&
        (_skeleton.value > 0 || _skeleton.isAnimating);
    if (run) {
      if (!_pulse.isAnimating) unawaited(_pulse.repeat(reverse: true));
    } else if (_pulse.isAnimating || _pulse.value != 0) {
      _pulse
        ..stop()
        ..value = 0;
    }
    _syncHold();
  }

  void _syncHold() {
    _hold.moving =
        _pulse.isAnimating || _cover.isAnimating || _skeleton.isAnimating;
  }
}

/// [LoadingVeilController] 的畫面：撐滿正文區，不攔觸控（呼叫端決定）。
class LoadingVeil extends StatefulWidget {
  const LoadingVeil({
    super.key,
    required this.controller,
    required this.spec,
    required this.backgroundColor,
    required this.textColor,
    this.lines,
  });

  final LoadingVeilController controller;

  /// 正文目前的版面：骨架照它的行高、段距、首行縮排與左右邊距畫。
  final ReaderV2LayoutSpec spec;
  final Color backgroundColor;
  final Color textColor;

  /// 上次在這個位置看到的每一行字（[ReaderSkeletonPage.lines]）；有的話
  /// 骨架照它們畫，沒有時照 [spec] 畫固定的段落樣式。
  final List<Rect>? lines;

  @override
  State<LoadingVeil> createState() => _LoadingVeilState();
}

class _LoadingVeilState extends State<LoadingVeil> {
  @override
  void initState() {
    super.initState();
    widget.controller._attach();
  }

  @override
  void didUpdateWidget(covariant LoadingVeil oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._detach();
      widget.controller._attach();
    }
  }

  @override
  void dispose() {
    widget.controller._detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _LoadingVeilPainter(
          cover: controller._coverCurve,
          skeleton: controller._skeletonCurve,
          pulse: controller._pulseCurve,
          sweep: () => controller._sweep,
          spec: widget.spec,
          lines: widget.lines,
          backgroundColor: widget.backgroundColor,
          textColor: widget.textColor,
        ),
      ),
    );
  }
}

class _LoadingVeilPainter extends CustomPainter {
  _LoadingVeilPainter({
    required this.cover,
    required this.skeleton,
    required this.pulse,
    required this.sweep,
    required this.spec,
    required this.lines,
    required this.backgroundColor,
    required this.textColor,
  }) : super(repaint: Listenable.merge([cover, skeleton, pulse]));

  final Animation<double> cover;
  final Animation<double> skeleton;
  final Animation<double> pulse;

  /// 掀紙是不是由左而右；紙蓋著時不影響畫面。
  final bool Function() sweep;
  final ReaderV2LayoutSpec spec;
  final List<Rect>? lines;
  final Color backgroundColor;
  final Color textColor;

  /// 每段的行數與末行長度（佔整行的比例），依序循環；長短交錯才像文字。
  static const List<int> _paragraphLines = [3, 5, 2, 4, 1, 3, 6, 2];
  static const List<double> _lastLineWidths = [
    0.64,
    0.38,
    0.82,
    0.5,
    0.72,
    0.27,
    0.56,
    0.9,
  ];

  /// 圓角條佔字號的比例，與 [SkeletonLine] 相同。
  static const double _barHeightFactor = 0.75;

  @override
  void paint(Canvas canvas, Size size) {
    final coverStrength = cover.value;
    if (coverStrength <= 0) return;
    // 由左而右掀紙時，紙與骨架在每個橫向位置各自淡出：濃度是 1 減該處
    // 正文的濃度。
    final sweeping = sweep() && coverStrength < 1;
    final stops = sweeping
        ? SkeletonReveal.sweepStops(1 - coverStrength)
        : const <(double, double)>[];
    Paint shade(Color color, double strength) {
      if (!sweeping) {
        return Paint()..color = color.withValues(alpha: color.a * strength);
      }
      return Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, 0),
          [
            for (final (_, content) in stops)
              color.withValues(alpha: color.a * strength * (1 - content)),
          ],
          [for (final (u, _) in stops) u],
        );
    }

    canvas.drawRect(
      Offset.zero & size,
      shade(backgroundColor, sweeping ? 1 : coverStrength),
    );

    final strength = skeleton.value * (sweeping ? 1 : coverStrength);
    if (strength <= 0) return;
    final style = spec.style;
    final lineExtent = style.fontSize * style.effectiveLineHeight;
    final left = spec.textPaddingLeft;
    final width = size.width - left - spec.textPaddingRight;
    if (lineExtent <= 0 || width <= 0) return;

    final dark =
        ThemeData.estimateBrightnessForColor(backgroundColor) ==
        Brightness.dark;
    final base = Skeleton.tint(textColor, dark: dark);
    final paint = shade(base, Skeleton.pulseStrength(pulse.value) * strength);
    final barHeight = style.fontSize * _barHeightFactor;
    final barInset = (lineExtent - barHeight) / 2;
    final radius = AppRadius.cardXs.topLeft;
    if (lines case final lines? when lines.isNotEmpty) {
      _paintLines(canvas, lines, barHeight, radius, paint);
      return;
    }
    final indent = style.textIndent * (spec.cellWidth ?? style.fontSize);
    final paragraphGap = lineExtent * style.paragraphSpacing;

    var top = 0.0;
    for (var paragraph = 0; top < size.height; paragraph++) {
      final pattern = paragraph % _paragraphLines.length;
      final lines = _paragraphLines[pattern];
      for (var line = 0; line < lines && top < size.height; line++) {
        final start = line == 0 ? indent : 0.0;
        final end = line == lines - 1
            ? width * _lastLineWidths[pattern]
            : width;
        if (end > start) {
          canvas.drawRRect(
            RRect.fromLTRBR(
              left + start,
              top + barInset,
              left + end,
              top + barInset + barHeight,
              radius,
            ),
            paint,
          );
        }
        top += lineExtent;
      }
      top += paragraphGap;
    }
  }

  /// 照記下的每一行畫：長條與那一行字同寬、置中在那一行上；正文的長條
  /// 是 [barHeight]，比正文高的行（章名）照字框高度等比放大。
  static void _paintLines(
    Canvas canvas,
    List<Rect> lines,
    double barHeight,
    Radius radius,
    Paint paint,
  ) {
    final heights = [for (final line in lines) line.height]..sort();
    final bodyHeight = heights[heights.length ~/ 2];
    for (final line in lines) {
      final height = bodyHeight <= 0
          ? barHeight
          : barHeight * (line.height / bodyHeight).clamp(1.0, 3.0);
      final top = line.center.dy - height / 2;
      canvas.drawRRect(
        RRect.fromLTRBR(line.left, top, line.right, top + height, radius),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LoadingVeilPainter oldDelegate) =>
      oldDelegate.cover != cover ||
      oldDelegate.skeleton != skeleton ||
      oldDelegate.pulse != pulse ||
      oldDelegate.spec != spec ||
      !identical(oldDelegate.lines, lines) ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.textColor != textColor;
}

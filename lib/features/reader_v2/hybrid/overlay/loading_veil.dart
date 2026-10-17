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
/// 排版期間整張紙蓋住，接在開書轉場後面看起來是同一張紙。紙上的骨架照
/// 一頁真正的每一行畫：開書有上次記下的那一頁時紙一蓋上就淡入，其他時候
/// 紙先空著，第一頁排好後才照它淡入（[showSkeleton]，ADR 0016、0024）。
/// 正文排好後紙以骨架換場（[SkeletonReveal]，使用者選的方式與時長）淡出、
/// 露出正文，骨架跟著一起淡掉。
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
      if (_skeleton.isAnimating) {
        _skeleton.value = _skeleton.status == AnimationStatus.reverse ? 0 : 1;
      }
    }
    _syncPulse();
  }

  /// 紙還蓋著或正在淡出。
  bool get isVisible => !_cover.isDismissed;

  /// 骨架還在淡入或淡出。
  bool get isSkeletonFading => _skeleton.isAnimating;

  /// 紙上還看得到骨架（含淡出中）。
  bool get hasSkeleton => !_skeleton.isDismissed;

  /// 蓋上整張紙。[skeleton] 為 true 時骨架從目前的濃淡繼續淡入（淡出途中
  /// 再蓋上不會先閃空）；false 時紙先空著，等 [showSkeleton]，已經畫著的
  /// 骨架淡掉。
  void cover({bool skeleton = true}) {
    _cover.value = 1;
    if (skeleton) {
      showSkeleton();
    } else {
      hideSkeleton();
    }
  }

  /// 淡入紙上的骨架。
  void showSkeleton() {
    if (_reduceMotion) {
      _skeleton.value = 1;
    } else {
      unawaited(_skeleton.forward());
    }
    _syncPulse();
  }

  /// 淡掉紙上的骨架，紙留著。
  void hideSkeleton() {
    if (_reduceMotion || _skeleton.isDismissed) {
      _skeleton.value = 0;
    } else {
      unawaited(_skeleton.reverse());
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
    this.titleLines = const <int>{},
  });

  final LoadingVeilController controller;

  /// 正文目前的版面：骨架長條的高度照它的字級。
  final ReaderV2LayoutSpec spec;
  final Color backgroundColor;
  final Color textColor;

  /// 這一頁每一行字在正文區的位置：上次離開時記下的
  /// （[ReaderSkeletonPage.lines]），或這次排好的第一頁。還沒有時紙上只有
  /// 底色。
  final List<Rect>? lines;

  /// [lines] 裡章名那幾行的索引：長條照章名與正文的字級比放大。
  final Set<int> titleLines;

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
          titleLines: widget.titleLines,
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
    required this.titleLines,
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
  final Set<int> titleLines;
  final Color backgroundColor;
  final Color textColor;

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
    final lines = this.lines;
    if (lines == null) return;
    final style = spec.style;
    final dark =
        ThemeData.estimateBrightnessForColor(backgroundColor) ==
        Brightness.dark;
    final base = Skeleton.tint(textColor, dark: dark);
    final paint = shade(base, Skeleton.pulseStrength(pulse.value) * strength);
    final barHeight = style.fontSize * _barHeightFactor;
    final titleBarHeight = style.fontSize > 0
        ? barHeight * style.titleFontSize / style.fontSize
        : barHeight;
    final radius = AppRadius.cardXs.topLeft;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final height = titleLines.contains(i) ? titleBarHeight : barHeight;
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
      !identical(oldDelegate.titleLines, titleLines) ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.textColor != textColor;
}

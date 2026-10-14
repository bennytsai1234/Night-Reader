import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

/// 開書、跳章與重新排版時蓋在正文上的一張紙。
///
/// 排版期間整張紙蓋住，畫面只有閱讀器底色，接在開書轉場後面看起來是同一
/// 張紙；超過 [AppMotion.readerSkeletonDelay] 還沒排好，才在紙上淡入照閱讀
/// 版面畫的正文骨架。正文排好後紙以 [AppMotion.fade] 淡出、露出正文，骨架
/// 跟著一起淡掉。
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
  }

  /// 紙完全淡出時呼叫，呼叫端據此把 [LoadingVeil] 移出畫面。
  final VoidCallback? onHidden;

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
  Timer? _skeletonDelay;
  int _attachedVeils = 0;
  bool _reduceMotion = false;

  /// 系統要求減少動態（`MediaQuery.disableAnimations`）時，紙與骨架直接到位，
  /// 骨架不呼吸。
  set reduceMotion(bool value) {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    _syncPulse();
  }

  /// 紙還蓋著或正在淡出。
  bool get isVisible => !_cover.isDismissed;

  /// 蓋上整張紙，重新計時骨架。
  void cover() {
    _skeletonDelay?.cancel();
    _cover.value = 1;
    _skeleton.value = 0;
    _skeletonDelay = Timer(AppMotion.readerSkeletonDelay, _showSkeleton);
    _syncPulse();
  }

  /// 正文已排好：紙淡出。
  void reveal() {
    _skeletonDelay?.cancel();
    _skeletonDelay = null;
    if (_reduceMotion) {
      _cover.value = 0;
    } else {
      unawaited(_cover.reverse());
    }
  }

  void dispose() {
    _skeletonDelay?.cancel();
    _cover.dispose();
    _skeleton.dispose();
    _pulse.dispose();
  }

  void _showSkeleton() {
    _skeletonDelay = null;
    if (_reduceMotion) {
      _skeleton.value = 1;
    } else {
      unawaited(_skeleton.forward());
    }
    _syncPulse();
  }

  void _onCoverStatus(AnimationStatus status) {
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
  });

  final LoadingVeilController controller;

  /// 正文目前的版面：骨架照它的行高、段距、首行縮排與左右邊距畫。
  final ReaderV2LayoutSpec spec;
  final Color backgroundColor;
  final Color textColor;

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
          spec: widget.spec,
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
    required this.spec,
    required this.backgroundColor,
    required this.textColor,
  }) : super(repaint: Listenable.merge([cover, skeleton, pulse]));

  final Animation<double> cover;
  final Animation<double> skeleton;
  final Animation<double> pulse;
  final ReaderV2LayoutSpec spec;
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
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = backgroundColor.withValues(
          alpha: backgroundColor.a * coverStrength,
        ),
    );

    final strength = skeleton.value * coverStrength;
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
    final paint = Paint()
      ..color = base.withValues(
        alpha: base.a * Skeleton.pulseStrength(pulse.value) * strength,
      );
    final barHeight = style.fontSize * _barHeightFactor;
    final barInset = (lineExtent - barHeight) / 2;
    final radius = AppRadius.cardXs.topLeft;
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

  @override
  bool shouldRepaint(_LoadingVeilPainter oldDelegate) =>
      oldDelegate.cover != cover ||
      oldDelegate.skeleton != skeleton ||
      oldDelegate.pulse != pulse ||
      oldDelegate.spec != spec ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.textColor != textColor;
}

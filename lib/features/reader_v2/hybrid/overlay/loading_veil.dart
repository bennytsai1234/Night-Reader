import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

/// 開書、跳章與重新排版時蓋在正文上的一張紙。
///
/// 排版期間整張紙蓋住，接在開書轉場後面看起來是同一張紙。跳章、改排版與
/// 重載內容時舊正文還在畫面上，紙以 [AppMotion.fade] 淡入蓋過它
/// （[cover] 的 `fade`），蓋滿（[covered]）才拿掉舊正文、開始排版
/// （ADR 0018）。紙上的骨架照
/// 一頁真正的每一行畫：開書有上次記下的那一頁時紙一蓋上就淡入，其他時候
/// 紙先空著，第一頁排好後才照它淡入（[showSkeleton]，ADR 0016、0024）。
/// 骨架出現與正文排好後掀紙都照骨架換場（[SkeletonReveal] 的方式與時長）：骨架照它長出來，掀紙時骨架跟著紙一起淡掉、露出正文。
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
      _skeleton = AnimationController(
        vsync: vsync,
        duration: AppMotion.fade,
        reverseDuration: AppMotion.fade,
      ),
      _pulse = AnimationController(
        vsync: vsync,
        duration: Skeleton.breathCycle,
      ) {
    _cover.addStatusListener(_onCoverStatus);
  }

  /// 紙完全淡出時呼叫，呼叫端據此把 [LoadingVeil] 移出畫面。
  final VoidCallback? onHidden;

  /// 這一次掀紙是不是由左而右。
  bool _sweep = false;

  /// 骨架出現的方式與時長，見 [skeletonReveal]。
  SkeletonReveal _skeletonReveal = const SkeletonReveal();

  /// 這一次骨架出現是不是由左而右；骨架自己淡掉時一律整頁淡。
  bool _skeletonSweep = false;

  final AnimationController _cover;
  final AnimationController _skeleton;
  final AnimationController _pulse;
  int _attachedVeils = 0;
  bool _reduceMotion = false;

  /// 系統要求減少動態（`MediaQuery.disableAnimations`）時，紙與骨架直接到位，
  /// 骨架不呼吸；中途切換時，進行中的淡出與淡入也直接跳到終點（淡入中的
  /// 紙蓋滿、掀開中的紙掀掉）。
  set reduceMotion(bool value) {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    if (value) {
      if (_cover.isAnimating) {
        _cover.value = _cover.status == AnimationStatus.forward ? 1 : 0;
      }
      if (_skeleton.isAnimating) {
        _skeleton.value = _skeleton.status == AnimationStatus.reverse ? 0 : 1;
      }
    }
    _syncPulse();
  }

  /// 骨架出現照的骨架換場設定，呼叫端從主題取得、設定改變時更新。開書時
  /// 骨架在拿到主題之前就開始出現，這時改照新的方式與時長走完剩下的部分。
  set skeletonReveal(SkeletonReveal value) {
    if (_skeletonReveal == value) return;
    _skeletonReveal = value;
    if (_skeleton.status == AnimationStatus.forward) {
      _skeletonSweep = value.sweeps;
      _skeleton.duration = value.duration;
      unawaited(_skeleton.forward());
    }
  }

  /// 紙還蓋著或正在淡入、淡出。
  bool get isVisible => !_cover.isDismissed;

  /// 紙整張蓋滿、沒有在淡入淡出。
  bool get isCovered => _cover.isCompleted;

  /// 紙正在掀開（淡出中）。
  bool get isRevealing => _cover.status == AnimationStatus.reverse;

  /// 等 [covered] 的呼叫端；紙不再往蓋滿走（蓋滿、改成掀開）或控制器
  /// 拆掉時，每一個都完成一次。
  final List<Completer<bool>> _coverWaiters = <Completer<bool>>[];

  /// 淡入停下來時完成：整張蓋滿為 true；途中改成掀開、或控制器拆掉時為
  /// false，呼叫端當成這次蓋紙取消。沒有在淡入時立即以目前是否蓋滿完成。
  Future<bool> get covered {
    if (_cover.status != AnimationStatus.forward) {
      return Future<bool>.value(_cover.isCompleted);
    }
    final waiter = Completer<bool>();
    _coverWaiters.add(waiter);
    return waiter.future;
  }

  void _settleCoverWaiters({required bool covered}) {
    if (_coverWaiters.isEmpty) return;
    final waiters = List<Completer<bool>>.of(_coverWaiters);
    _coverWaiters.clear();
    for (final waiter in waiters) {
      waiter.complete(covered);
    }
  }

  /// 骨架還在淡入或淡出。
  bool get isSkeletonFading => _skeleton.isAnimating;

  /// 紙上還看得到骨架（含淡出中）。
  bool get hasSkeleton => !_skeleton.isDismissed;

  /// 蓋上整張紙。[skeleton] 為 true 時骨架從目前的濃淡繼續淡入（淡出途中
  /// 再蓋上不會先閃空）；false 時紙先空著，等 [showSkeleton]，已經畫著的
  /// 骨架淡掉。
  ///
  /// [fade] 時紙從目前的濃淡以 [AppMotion.fade] 淡入（底下的舊正文還在，
  /// 等 [covered] 再拿掉）；否則直接蓋滿。掀紙途中再淡入時沿用那次掀紙的
  /// 方式倒回來，其他時候整張一起淡。
  void cover({bool skeleton = true, bool fade = false}) {
    if (fade && !_reduceMotion) {
      if (!_cover.isAnimating) _sweep = false;
      unawaited(_cover.forward());
    } else {
      _cover.value = 1;
    }
    if (skeleton) {
      showSkeleton();
    } else {
      hideSkeleton();
    }
  }

  /// 照 [skeletonReveal] 讓紙上的骨架出現。
  void showSkeleton() {
    if (_reduceMotion) {
      _skeleton.value = 1;
    } else {
      _skeletonSweep = _skeletonReveal.sweeps;
      _skeleton.duration = _skeletonReveal.duration;
      unawaited(_skeleton.forward());
    }
    _syncPulse();
  }

  /// 淡掉紙上的骨架，紙留著。
  void hideSkeleton() {
    _skeletonSweep = false;
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
    _cover.removeStatusListener(_onCoverStatus);
    _settleCoverWaiters(covered: false);
    _cover.dispose();
    _skeleton.dispose();
    _pulse.dispose();
  }

  void _onCoverStatus(AnimationStatus status) {
    if (status != AnimationStatus.forward) {
      _settleCoverWaiters(covered: status == AnimationStatus.completed);
    }
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
      if (!_pulse.isAnimating) unawaited(_pulse.repeat());
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
    final viewWidth = MediaQuery.maybeSizeOf(context)?.width ?? 0;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _LoadingVeilPainter(
          cover: controller._cover,
          skeleton: controller._skeleton,
          pulse: controller._pulse,
          look: SkeletonLook.of(context),
          breathSpan: () {
            final box = context.findRenderObject();
            if (box is! RenderBox || !box.hasSize || viewWidth <= 0) {
              return (0, 1);
            }
            return Skeleton.screenSpan(box, viewWidth);
          },
          sweep: () => controller._sweep,
          skeletonSweep: () => controller._skeletonSweep,
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
    required this.look,
    required this.breathSpan,
    required this.sweep,
    required this.skeletonSweep,
    required this.spec,
    required this.lines,
    required this.titleLines,
    required this.backgroundColor,
    required this.textColor,
  }) : super(repaint: Listenable.merge([cover, skeleton, pulse]));

  /// 紙與骨架出現的進度：經過的時間比例，不套曲線。整頁淡時在這裡套
  /// [AppMotion.fadeCurve]，由左而右時交給 [SkeletonReveal] 每個位置各自套。
  final Animation<double> cover;
  final Animation<double> skeleton;

  /// 呼吸一輪的進度（[Skeleton.breathAt]）；停著時骨架不呼吸。
  final Animation<double> pulse;
  final SkeletonLook look;

  /// 紙的左右兩緣在螢幕上的位置（[Skeleton.screenSpan]）：呼吸照螢幕位置，
  /// 換頁平移、縮放時和頁首頁尾的骨架接得上；長出與掀紙照紙上的位置。
  final (double, double) Function() breathSpan;

  /// 掀紙是不是由左而右；紙蓋著時不影響畫面。
  final bool Function() sweep;

  /// 骨架出現是不是由左而右；骨架已經完全出現時不影響畫面。
  final bool Function() skeletonSweep;
  final ReaderV2LayoutSpec spec;
  final List<Rect>? lines;
  final Set<int> titleLines;
  final Color backgroundColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cover = this.cover.value;
    if (cover <= 0) return;
    final coverStrength = AppMotion.fadeCurve.transform(cover);
    // 由左而右掀紙時，紙與骨架在每個橫向位置各自淡出：濃度是 1 減該處
    // 正文的濃度。
    final sweeping = sweep() && cover < 1;
    final stops = sweeping
        ? SkeletonReveal.sweepStops(1 - cover)
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

    final strength =
        AppMotion.fadeCurve.transform(skeleton.value) *
        (sweeping ? 1 : coverStrength);
    if (strength <= 0) return;
    final lines = this.lines;
    if (lines == null) return;
    final style = spec.style;
    final dark =
        ThemeData.estimateBrightnessForColor(backgroundColor) ==
        Brightness.dark;
    final base = Skeleton.tint(textColor, dark: dark, strength: look.strength);
    final breathing = pulse.isAnimating;
    // 紙蓋著、骨架由左而右出現時，每個橫向位置照骨架換進來的濃度畫；掀紙
    // 途中照紙的漸層。
    final growing = !sweeping && skeletonSweep() && skeleton.value < 1;
    double layerAt(double u) {
      if (growing) {
        return coverStrength *
            SkeletonReveal.incomingOpacityAt(skeleton.value, u);
      }
      if (sweeping) {
        return strength * (1 - SkeletonReveal.incomingOpacityAt(1 - cover, u));
      }
      return strength;
    }

    final (screenLeft, screenRight) = breathing ? breathSpan() : (0.0, 1.0);
    double alphaAt(double u) =>
        base.a *
        layerAt(u) *
        (breathing
            ? Skeleton.breathAt(
                pulse.value,
                screenLeft + (screenRight - screenLeft) * u,
                look.breath,
              )
            : 1);
    // 沿橫向會變的有：骨架長出來、掀紙與由左而右的呼吸。換場取
    // [SkeletonReveal.sweepStops] 的停點；呼吸每 1/32 個寬度取一點。
    final breathSweeps = breathing && look.breath.lag > 0;
    final points = <double>{0, 1};
    if (growing) {
      points.addAll(SkeletonReveal.sweepStops(skeleton.value).map((s) => s.$1));
    }
    if (sweeping) points.addAll(stops.map((s) => s.$1));
    if (breathSweeps) {
      for (var i = 1; i < 32; i++) {
        points.add(i / 32);
      }
    }
    final Paint paint;
    if (!growing && !sweeping && !breathSweeps) {
      paint = Paint()..color = base.withValues(alpha: alphaAt(0));
    } else {
      final us = points.toList()..sort();
      paint = Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, 0), [
          for (final u in us) base.withValues(alpha: alphaAt(u)),
        ], us);
    }
    final barHeight = style.fontSize * Skeleton.barHeightFactor;
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
      oldDelegate.look != look ||
      oldDelegate.spec != spec ||
      !identical(oldDelegate.lines, lines) ||
      !identical(oldDelegate.titleLines, titleLines) ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.textColor != textColor;
}

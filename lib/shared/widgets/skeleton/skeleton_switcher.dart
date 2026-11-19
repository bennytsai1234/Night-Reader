import 'dart:async';

import 'package:flutter/material.dart';

import 'cover_reveal.dart';
import 'launch_entrance.dart';
import 'painted_when.dart';
import 'skeleton.dart';
import 'skeleton_reveal.dart';
import 'snapshot_sweep.dart';

/// 骨架與真實內容之間的切換：資料到了以骨架換場（[SkeletonReveal] 的方式
/// 與時長）換成內容；重新載入時骨架也照同樣的方式
/// 與時長長回來。
///
/// 預設兩者都撐滿父層（整頁內容區）；可收縮的面板以 [fit] 保留自然高度。
/// [builder] 只在載入完成後才呼叫。
class SkeletonSwitcher extends StatefulWidget {
  const SkeletonSwitcher({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.builder,
    this.waitForCovers,
    this.entrance,
    this.backdrop,
    this.onRevealed,
    this.fit = StackFit.expand,
  });

  final bool loading;
  final Widget skeleton;
  final WidgetBuilder builder;

  /// 骨架換成內容、換場播完的那一刻（內容已經照常排好）。
  final VoidCallback? onRevealed;

  /// 頁面撐滿內容區；依內容收縮的面板沿用自然高度。
  final StackFit fit;

  /// 骨架與內容後面的實色（通常是頁面底色）。給了的話換場只遮骨架一層：
  /// 骨架墊著這個顏色蓋在照常畫出的內容上，由左而右退開；內容不再套動畫
  /// 遮罩、不另開離屏圖層，換場的每一格少合成一張整區大的圖層（ADR 0029）。
  /// 換到一半時是骨架覆蓋著淡出，比兩層交叉淡換的骨架稍微明顯一點。
  /// 後面不是單一實色（例如半透明、漸層或圖片）時留 null，兩層各自淡入淡出。
  final Color? backdrop;

  /// 給了的話，資料到了先在骨架底下建好內容，照這個方式等畫面上的封面
  /// （[CoverReveal]），再連同封面一次換場；不會先出現空白的書卡、封面再
  /// 一張張浮出來。null 時不等。
  final CoverWait? waitForCovers;

  /// 開 App 的進場（書架的骨架，見 [LaunchEntrance]）：骨架照它的進度、以
  /// 骨架換場的方式出現；這段期間資料到了也先不建內容、不換場，播完才接著
  /// 做（ADR 0018）。第一次換成內容時整個主頁面一起照兩張定格畫面換場
  /// （[LaunchEntranceMotion.reveal]，ADR 0031）。null 時骨架一開始就在。
  final LaunchEntranceMotion? entrance;

  @override
  State<SkeletonSwitcher> createState() => _SkeletonSwitcherState();
}

class _SkeletonSwitcherState extends State<SkeletonSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.loading || _entering ? 0 : 1,
  )..addStatusListener(_onStatus);

  /// 內容出現的進度（經過的時間比例，曲線由 [SkeletonReveal] 套）。
  late final Animation<double> _content = _controller;
  late final Animation<double> _skeleton = ReverseAnimation(_content);

  void _onStatus(AnimationStatus status) {
    setState(() {});
    // 定格換場時內容一下就換好，換場播完才算出現。
    if (status.isCompleted && !widget.loading && _snapshotting == null) {
      widget.onRevealed?.call();
    }
  }

  /// 正在播的定格換場；換場播完或重新載入時清掉。
  SnapshotSweepController? _snapshotting;

  /// 這一次換進來的是哪一層：換成內容，或重新載入時長回骨架。
  SkeletonRevealSide _incoming = SkeletonRevealSide.content;

  /// 這一次換場是不是由左而右。
  bool _sweep = false;

  /// 淡入前等封面的那一輪；等完或重新載入就換掉。
  CoverReveal? _reveal;

  /// 開 App 第一次換場前，資料到了、正在等骨架收住呼吸
  /// （[LaunchEntranceMotion.settleBreath]）；這段期間當作還在載入，內容不建。
  Future<void>? _resting;

  /// 重新載入、淡回骨架時，淡出中的內容沿用上一次建好的樣子。
  Widget? _lastContent;

  /// [_lastContent] 是照哪一個 widget 與哪一輪等封面建的。
  SkeletonSwitcher? _contentFor;
  CoverReveal? _contentReveal;

  /// 骨架還在進場：這段期間當作還在載入。
  bool get _entering {
    final entrance = widget.entrance;
    return entrance != null && !entrance.skeleton.isCompleted;
  }

  @override
  void initState() {
    super.initState();
    widget.entrance?.skeleton.addStatusListener(_onEntranceStatus);
    // 一開始就是內容（沒有骨架可換）時，進場的按鈕也直接到位。
    if (_controller.isCompleted) widget.entrance?.revealNow();
  }

  @override
  void didUpdateWidget(SkeletonSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.entrance, oldWidget.entrance)) {
      oldWidget.entrance?.skeleton.removeStatusListener(_onEntranceStatus);
      widget.entrance?.skeleton.addStatusListener(_onEntranceStatus);
    }
    if (widget.loading == oldWidget.loading) return;
    _reveal = null;
    _resting = null;
    if (widget.loading) {
      // 定格換場還沒播完就要長回骨架：先換回真的畫面，從內容接著長回去。
      // 呼吸前的準備做到一半的話放棄，骨架照常呼吸。
      _snapshotting?.finish();
      _snapshotting = null;
      widget.entrance?.donePreparing();
      _prepare(SkeletonRevealSide.skeleton);
      _controller.reverse();
    } else if (!_entering) {
      _onLoaded(duringBuild: true);
    }
  }

  void _onEntranceStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {});
    if (!widget.loading) _onLoaded();
  }

  void _onLoaded({bool duringBuild = false}) {
    final wait = widget.waitForCovers;
    final entrance = widget.entrance;
    final launching = entrance != null && !entrance.revealStarted;
    // 開 App 第一次換場前：骨架剛長完、還沒排好呼吸時，等長完那一格畫完
    // 就在底下一次建好內容、等封面、拍好兩張定格畫面（ADR 0035）；來不及
    // 的話等骨架收住呼吸，畫面靜止了才做（ADR 0031）。呼吸的每一格底下都
    // 不做事：拆成一格一小步時，手機稍慢一點，每一步都讓呼吸那一格晚
    // 出來，一路頓頓地走過去。
    if (launching && !entrance.breathSettled && !entrance.preparing) {
      final resting = _resting =
          entrance.requestPreparation() ?? entrance.settleBreath();
      unawaited(
        resting.then((_) {
          if (!mounted || !identical(_resting, resting)) return;
          setState(() => _resting = null);
          if (!widget.loading) _onLoaded();
        }),
      );
      return;
    }
    if (wait != null) {
      final reveal = _reveal = CoverReveal(wait, paced: !launching);
      // 淡回骨架途中又載入完成時，新內容也要從全透明開始等。建畫面途中歸零
      // 會在別人建構時通知聽換場進度的元件；先停住，這一幀畫完再歸零
      // （封面最快也要下一輪才等完）。
      if (duringBuild) {
        _controller.stop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(_reveal, reveal)) _controller.value = 0;
        });
      } else {
        _controller.value = 0;
      }
      unawaited(
        reveal.settle().whenComplete(() {
          if (mounted && identical(_reveal, reveal)) _revealContent();
        }),
      );
    } else {
      _revealContent();
    }
  }

  void _revealContent() {
    _prepare(SkeletonRevealSide.content);
    // 開 App 的第一次換場由進場整個畫面一起照兩張定格畫面換（ADR 0031）；
    // 之後重新載入照常兩層換場。
    final entrance = widget.entrance;
    if (entrance == null || entrance.revealStarted) {
      _controller.forward();
      return;
    }
    // 拍下骨架畫面後內容一下就換好（這時螢幕上蓋著骨架那張圖），換場由兩張
    // 圖混合播完。
    final snapshot = _snapshotting = entrance.screen;
    bool current() =>
        mounted && identical(_snapshotting, snapshot) && !widget.loading;
    void showContent() {
      if (current()) _controller.value = 1;
    }

    // 呼吸前：先拍好兩張定格畫面、換回骨架，等呼吸收住再接著換場（ADR
    // 0035）。等的這段當作還在載入（[_resting]）：重新載入時拍好的圖放掉
    // （[didUpdateWidget] 的 finish），照呼吸收住後再拍。
    if (entrance.preparing) {
      unawaited(
        entrance
            .capture(
              change: showContent,
              restore: () {
                if (current()) _controller.value = 0;
              },
            )
            .then((_) {
              if (!current()) return;
              final resting = _resting = entrance.settleBreath();
              setState(() {});
              unawaited(
                resting.then((_) {
                  if (!mounted || !identical(_resting, resting)) return;
                  setState(() => _resting = null);
                  if (!widget.loading) _revealContent();
                }),
              );
            }),
      );
      return;
    }
    final played = entrance.reveal(
      change: showContent,
      duration: _controller.duration!,
      sweep: _sweep,
    );
    unawaited(
      played.whenComplete(() {
        if (!mounted || !identical(_snapshotting, snapshot)) return;
        // 骨架層留到換場播完才拿掉（[build]）。
        setState(() => _snapshotting = null);
        if (!widget.loading && _controller.isCompleted) {
          widget.onRevealed?.call();
        }
      }),
    );
  }

  /// 這一次換場照 [SkeletonReveal] 的方式與時長。換場途中反過來時沿用這一輪的方向
  /// 與方式倒著走：換掉 [_incoming] 會讓左右的濃淡在同一幀對調。
  void _prepare(SkeletonRevealSide incoming) {
    final reveal = SkeletonReveal.of(context);
    if (!_controller.isAnimating) {
      _incoming = incoming;
      _sweep = reveal.sweeps;
    }
    _controller
      ..duration = reveal.duration
      ..reverseDuration = reveal.duration;
  }

  @override
  void dispose() {
    widget.entrance?.skeleton.removeStatusListener(_onEntranceStatus);
    // 拍到一半、拍好還沒播或換場中就被拆掉：結束這一輪、放掉圖，骨架照常
    // 呼吸（換場由這個元件接著播，拆掉就沒有人播了）。
    _snapshotting?.finish();
    widget.entrance?.donePreparing();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reveal = _reveal;
    final entrance = _entering ? widget.entrance : null;
    final appearing = entrance?.skeleton;
    final loading = widget.loading || entrance != null || _resting != null;
    // 還沒開始換場：內容建在骨架底下看不到（有墊色時被骨架整個蓋住，沒有
    // 時全透明），例如等封面、開 App 呼吸前就拍好兩張定格畫面時呼吸的那段
    // （ADR 0035）。不畫（手機不必每一格多畫一整頁看不到的書架），也點不到。
    final covered = _controller.isDismissed;
    final hidden = loading || covered || reveal != null && reveal.waiting;
    // 換場開始與結束時只是自己的動畫狀態變了，沿用同一個內容元件，整頁內容
    // 不重建；上層給了新的 [SkeletonSwitcher] 或換了一輪等封面才重新建。原本
    // 每次都包新的 Builder，換場的第一幀與最後一幀都把整個書架重建一次
    // （ADR 0018）。
    if (!loading &&
        (!identical(_contentFor, widget) ||
            !identical(_contentReveal, reveal))) {
      _contentFor = widget;
      _contentReveal = reveal;
      _lastContent = reveal == null
          ? Builder(builder: widget.builder)
          : CoverRevealScope(
              reveal: reveal,
              child: Builder(builder: widget.builder),
            );
    }
    final content = _lastContent;
    final backdrop = widget.backdrop;
    final skeletonLayer = SkeletonRevealLayer(
      key: const ValueKey('skeleton'),
      presence: appearing ?? _skeleton,
      side: SkeletonRevealSide.skeleton,
      incoming: entrance == null ? _incoming : SkeletonRevealSide.skeleton,
      sweep: entrance?.sweep ?? _sweep,
      child: backdrop == null
          ? Skeleton(child: widget.skeleton)
          // 蓋在內容上面時不擋點擊：換場途中已經露出來的書照樣點得到。
          : IgnorePointer(
              child: ColoredBox(
                color: backdrop,
                child: Skeleton(child: widget.skeleton),
              ),
            ),
    );
    // 等封面時內容已經建在骨架底下：有 [backdrop] 時被墊色的骨架整個蓋住，
    // 沒有時是全透明。
    final contentLayer =
        content != null &&
            (!_controller.isDismissed ||
                reveal != null ||
                _snapshotting != null)
        ? SkeletonRevealLayer(
            key: const ValueKey('content'),
            // 有墊色時內容一律照常畫，交叉淡換全由上面的骨架層負責。
            presence: backdrop == null ? _content : kAlwaysCompleteAnimation,
            side: SkeletonRevealSide.content,
            incoming: _incoming,
            sweep: _sweep,
            // 還沒淡入或正在淡出的內容不接點擊、不給讀屏念。
            child: PaintedWhen(
              shown: !covered,
              child: IgnorePointer(
                ignoring: hidden,
                child: ExcludeSemantics(excluding: hidden, child: content),
              ),
            ),
          )
        : null;
    // 開 App 的定格換場播完前骨架層留著（換成內容後全透明、不畫）：呼吸前
    // 拍好兩張圖換回骨架時不必重建整片骨架。
    final showSkeleton = !_controller.isCompleted || _snapshotting != null;
    // 兩層各有 key：另一層進出 Stack 時不會被錯配、重建。有墊色時骨架在
    // 上面蓋住內容；沒有時骨架在下、內容在上，各自淡入淡出。
    return Stack(
      fit: widget.fit,
      children: backdrop == null
          ? [?(showSkeleton ? skeletonLayer : null), ?contentLayer]
          : [?contentLayer, ?(showSkeleton ? skeletonLayer : null)],
    );
  }
}

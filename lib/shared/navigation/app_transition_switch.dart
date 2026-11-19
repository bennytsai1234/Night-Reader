import 'package:flutter/material.dart';
import 'package:night_reader/shared/navigation/app_page_transition.dart';
import 'package:night_reader/shared/navigation/transition_origin.dart';
import 'package:night_reader/shared/navigation/transition_poses.dart';

/// 不經過路由、在同一處把一個畫面換成另一個時播選定的換頁動畫，例如點
/// 主頁的分頁。[forward] 時 [incoming] 像新開的頁蓋上 [outgoing]；否則
/// [outgoing] 像返回一樣離開、露出 [incoming]。
///
/// [animation] 是這一趟的時間比例 0→1，曲線由各動畫自己套；[follow] 時
/// 是拖曳返回的進度，照拖曳返回的樣子和進度成正比。「展開」從這一趟開始
/// 時（[trip] 換了值）最後按下的地方長出來（返回時縮回去）。
///
/// 沒在換頁時 [outgoing] 是 null，[incoming] 原樣畫在整頁。元件一直掛著、
/// [incoming] 不論換頁與否、往哪個方向，都包在同一串元件的同一個位置，換頁
/// 開始與結束時不會被搬動：原本換頁時才把它搬進來，帶著 GlobalKey 的整個
/// 分頁每次換頁開始與結束都整棵重建（ADR 0018）。
class AppTransitionSwitch extends StatefulWidget {
  const AppTransitionSwitch({
    super.key,
    required this.transition,
    required this.animation,
    required this.trip,
    required this.forward,
    required this.outgoing,
    required this.incoming,
    required this.outgoingBackground,
    required this.incomingBackground,
    this.follow = false,
    this.held = false,
  });

  /// 換頁停在起點準備中：[incoming] 原樣畫在整頁、被墊了底色的 [outgoing]
  /// 蓋住。新頁的字這時就上過螢幕、建好字的貼圖，開始播的頭幾幀不必再建
  /// （ADR 0037 策略一）；開始播時兩層只是對調順序、換上姿勢。
  final bool held;

  final AppPageTransition transition;
  final Animation<double> animation;

  /// 每一趟換頁給不同的值。
  final Object? trip;
  final bool forward;
  final bool follow;

  /// 換頁中離開的畫面；null 是沒在換頁。
  final Widget? outgoing;
  final Widget incoming;

  /// 墊在淡掉的底下那一頁後面的顏色（見 [UnderPose.wrap]）。
  final Color outgoingBackground;
  final Color incomingBackground;

  @override
  State<AppTransitionSwitch> createState() => _AppTransitionSwitchState();
}

class _AppTransitionSwitchState extends State<AppTransitionSwitch> {
  static const _incomingKey = ValueKey('incoming');
  static const _outgoingKey = ValueKey('outgoing');

  TransitionSourceRect? _origin;

  @override
  void initState() {
    super.initState();
    _takeOrigin();
  }

  @override
  void didUpdateWidget(AppTransitionSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trip != oldWidget.trip) _takeOrigin();
  }

  // 系統的返回手勢不經過 App 的按下，上一次按下的地方跟這一趟無關，
  // 「展開」改縮回畫面中央。
  void _takeOrigin() => _origin = widget.follow ? null : TransitionOrigin.last;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.animation,
    builder: (context, _) {
      final size = MediaQuery.sizeOf(context);
      final outgoing = widget.outgoing;
      if (outgoing == null) {
        return Stack(
          fit: StackFit.expand,
          children: [
            _posed(
              widget.incoming,
              top: const TopPose(),
              under: const UnderPose(),
              size: size,
              background: widget.incomingBackground,
            ),
          ],
        );
      }
      if (widget.held) {
        return Stack(
          fit: StackFit.expand,
          children: [
            _posed(
              widget.incoming,
              top: const TopPose(),
              under: const UnderPose(),
              size: size,
              background: widget.incomingBackground,
            ),
            _posed(
              ColoredBox(color: widget.outgoingBackground, child: outgoing),
              top: const TopPose(),
              under: const UnderPose(),
              size: size,
              background: widget.outgoingBackground,
              key: _outgoingKey,
            ),
          ],
        );
      }
      final t = widget.animation.value;
      final TopPose top;
      final UnderPose under;
      if (widget.follow) {
        // 上面那頁露出、底下那頁被蓋住的比例：開啟時隨進度增加，返回時減少。
        final shown = widget.forward ? t : 1 - t;
        top = TopPose.follow(
          widget.transition,
          shown,
          size: size,
          origin: _origin,
        );
        under = UnderPose.follow(widget.transition, shown);
      } else {
        final trip = (closing: !widget.forward, time: t);
        top = TopPose.of(
          widget.transition,
          trip: trip,
          size: size,
          origin: _origin,
        );
        under = UnderPose.of(widget.transition, trip: trip);
      }
      // 上下兩層都包同一串元件，上層的「底下」與下層的「上面」停在原樣；
      // 兩層各有 key，往左往右換頁時上下對調只是搬動順序。
      final incoming = _posed(
        widget.incoming,
        top: widget.forward ? top : const TopPose(),
        under: widget.forward ? const UnderPose() : under,
        size: size,
        background: widget.incomingBackground,
      );
      final leaving = _posed(
        outgoing,
        top: widget.forward ? const TopPose() : top,
        under: widget.forward ? under : const UnderPose(),
        size: size,
        background: widget.outgoingBackground,
        key: _outgoingKey,
      );
      return Stack(
        fit: StackFit.expand,
        children: widget.forward ? [leaving, incoming] : [incoming, leaving],
      );
    },
  );

  Widget _posed(
    Widget child, {
    required TopPose top,
    required UnderPose under,
    required Size size,
    required Color background,
    Key key = _incomingKey,
  }) => KeyedSubtree(
    key: key,
    child: under.wrap(top.wrap(child, size), background),
  );
}

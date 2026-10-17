import 'package:flutter/material.dart';
import 'package:night_reader/core/services/motion_gate.dart';

import '../theme/app_tokens.dart';
import 'skeleton_reveal.dart';

/// 開 App 的進場（ADR 0025）：系統啟動畫面只有底色，Flutter 第一幀也只畫
/// 底色，接著頁首按鈕從上緣、分頁列從下緣滑進來（玻璃只動不淡，ADR 0022），
/// 標題淡入；頁首滑到一半時，書架的骨架照骨架換場（[SkeletonReveal]）的方式
/// 與時長出現。
///
/// 包在主頁面外面；底下的頁首（`GlassNavHeader`）、分頁列與書架骨架用
/// [maybeOf] 取得各自的進度。從主頁面推出去的頁面不在底下，不受影響。
/// 系統要求減少動態時直接到位。播放中持有 [MotionGate]（ADR 0018）。
class LaunchEntrance extends StatefulWidget {
  const LaunchEntrance({super.key, required this.child});

  final Widget child;

  /// 頁首與分頁列滑進來的時間，和閱讀選單打開一樣。
  static const Duration chrome = AppMotion.readerMenuIn;

  /// 分頁列比頁首晚這麼久開始。
  static const Duration tabBarDelay = AppMotion.readerMenuStagger;

  /// 骨架在頁首滑到一半時開始出現（使用者在原型裡選的，2026-10-17）。
  static const Duration skeletonDelay = Duration(milliseconds: 160);

  static LaunchEntranceMotion? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_LaunchEntranceScope>()
      ?.motion;

  @override
  State<LaunchEntrance> createState() => _LaunchEntranceState();
}

/// 進場各部分的進度，0 還沒出現、1 到位。
class LaunchEntranceMotion {
  LaunchEntranceMotion._(this._controller, Duration skeleton) {
    final total = _controller.duration!.inMicroseconds;
    double at(Duration time) => time.inMicroseconds / total;
    Animation<double> part(Duration start, Duration length, Curve curve) =>
        CurvedAnimation(
          parent: _controller,
          curve: Interval(at(start), at(start + length), curve: curve),
        );
    header = part(Duration.zero, LaunchEntrance.chrome, AppMotion.menuCurve);
    title = part(Duration.zero, AppMotion.fade, AppMotion.fadeCurve);
    tabBar = part(
      LaunchEntrance.tabBarDelay,
      LaunchEntrance.chrome,
      AppMotion.menuCurve,
    );
    this.skeleton = part(
      LaunchEntrance.skeletonDelay,
      skeleton,
      AppMotion.fadeCurve,
    );
  }

  final AnimationController _controller;

  /// 頁首兩側的玻璃按鈕。
  late final Animation<double> header;

  /// 頁首標題。
  late final Animation<double> title;

  /// 底部分頁列。
  late final Animation<double> tabBar;

  /// 書架的骨架；完成時才讀進書架的內容。
  late final Animation<double> skeleton;

  /// 骨架換場時長為 [skeleton] 時，整段進場的時間。
  static Duration totalFor(Duration skeleton) {
    final chromeEnd = LaunchEntrance.tabBarDelay + LaunchEntrance.chrome;
    final skeletonEnd = LaunchEntrance.skeletonDelay + skeleton;
    return chromeEnd > skeletonEnd ? chromeEnd : skeletonEnd;
  }
}

class _LaunchEntranceState extends State<LaunchEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener((_) => _syncHold());
  LaunchEntranceMotion? _motion;
  final MotionHold _hold = MotionHold();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motion != null) return;
    // 時長在第一次建畫面時定下來，播放中改設定不影響這一次。
    final skeleton = SkeletonReveal.of(context).duration;
    _controller.duration = LaunchEntranceMotion.totalFor(skeleton);
    _motion = LaunchEntranceMotion._(_controller, skeleton);
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    // 第一幀只畫底色、和系統啟動畫面一樣，畫完才開始進場。
    _hold.moving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  void _syncHold() => _hold.moving = !_controller.isCompleted;

  @override
  void dispose() {
    _hold.release();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _LaunchEntranceScope(motion: _motion!, child: widget.child);
}

class _LaunchEntranceScope extends InheritedWidget {
  const _LaunchEntranceScope({required this.motion, required super.child});

  final LaunchEntranceMotion motion;

  @override
  bool updateShouldNotify(_LaunchEntranceScope oldWidget) =>
      !identical(motion, oldWidget.motion);
}

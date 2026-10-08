import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 掛在根 Navigator 的狀態列策略；見 [StatusBarPolicy]。
final StatusBarPolicy statusBarPolicy = StatusBarPolicy();

/// 狀態列可見性跟著最前面的整頁頁面走。
///
/// 最前面的不透明路由以 [StatusBarHidden] 要求隱藏時收起狀態列（保留導覽
/// 列），其餘頁面一律顯示。底部面板、對話框與選單是透明路由，蓋在頁面上時
/// 沿用底下頁面的決定。頁面推入或彈出的當下就重新決定，因此從閱讀頁返回
/// 時，狀態列在返回動畫進行中就回來。
///
/// 頁面排版由 [StatusBarStableInset] 固定在狀態列原本的高度，狀態列收起或
/// 出現都不會推動頁面。
class StatusBarPolicy extends NavigatorObserver {
  final List<Route<dynamic>> _routes = <Route<dynamic>>[];
  final Set<Route<dynamic>> _hidingRoutes = <Route<dynamic>>{};

  /// App 啟動時狀態列是顯示的。
  bool _appliedHidden = false;
  bool _syncScheduled = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _scheduleSync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _forget(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _forget(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (oldRoute != null) _hidingRoutes.remove(oldRoute);
    if (newRoute == null) {
      if (index >= 0) _routes.removeAt(index);
    } else if (index >= 0) {
      _routes[index] = newRoute;
    } else {
      _routes.add(newRoute);
    }
    _scheduleSync();
  }

  void _forget(Route<dynamic> route) {
    _routes.remove(route);
    _hidingRoutes.remove(route);
    _scheduleSync();
  }

  void _setHiding(Route<dynamic> route, bool hiding) {
    final changed = hiding
        ? _hidingRoutes.add(route)
        : _hidingRoutes.remove(route);
    if (changed) _scheduleSync();
  }

  bool get _frontPageHides {
    for (final route in _routes.reversed) {
      if (route is TransitionRoute && route.opaque) {
        return _hidingRoutes.contains(route);
      }
    }
    return false;
  }

  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    // 新頁面推入後，下一幀才建出它的 [StatusBarHidden]；等這一幀結束再決定，
    // 換源改開另一個閱讀頁時才不會在兩頁之間閃出狀態列。
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _syncScheduled = false;
        _apply(_frontPageHides);
      })
      ..ensureVisualUpdate();
  }

  void _apply(bool hidden) {
    if (_appliedHidden == hidden) return;
    _appliedHidden = hidden;
    if (hidden) {
      _hide();
      SystemChrome.setSystemUIChangeCallback(_rehideAfterReveal);
    } else {
      SystemChrome.setSystemUIChangeCallback(null);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  static Future<void> _hide() => SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: const [SystemUiOverlay.bottom],
  );

  /// 使用者從頂端下滑叫出狀態列後，稍候再收回。
  Future<void> _rehideAfterReveal(bool systemOverlaysAreVisible) async {
    if (!systemOverlaysAreVisible) return;
    await Future<void>.delayed(const Duration(seconds: 3));
    if (_appliedHidden) await _hide();
  }
}

/// 所在頁面位於最前面時要求隱藏狀態列；[hidden] 為 false 時不提出要求。
///
/// 要求交給所在 Navigator 掛著的 [StatusBarPolicy]；Navigator 沒掛策略時
/// 不起作用。
class StatusBarHidden extends StatefulWidget {
  const StatusBarHidden({super.key, required this.hidden, required this.child});

  final bool hidden;
  final Widget child;

  @override
  State<StatusBarHidden> createState() => _StatusBarHiddenState();
}

class _StatusBarHiddenState extends State<StatusBarHidden> {
  Route<dynamic>? _route;
  StatusBarPolicy? _policy;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    _withdraw();
    _route = route;
    _policy = route?.navigator?.widget.observers
        .whereType<StatusBarPolicy>()
        .firstOrNull;
    _submit();
  }

  @override
  void didUpdateWidget(StatusBarHidden oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hidden != widget.hidden) _submit();
  }

  @override
  void dispose() {
    _withdraw();
    super.dispose();
  }

  void _submit() {
    final route = _route;
    if (route != null) _policy?._setHiding(route, widget.hidden);
  }

  void _withdraw() {
    final route = _route;
    if (route != null) _policy?._setHiding(route, false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 讓底下所有頁面的上緣內距至少保留狀態列原本的高度，不論狀態列是否顯示。
///
/// Flutter 在狀態列隱藏時把上緣內距降成只剩挖孔高度；頁面若照這個值排版，
/// 狀態列收起或出現時整頁會上下跳。掛在 MaterialApp.builder，對所有路由
/// 生效；閱讀正文的頁首另依挖孔高度排版，不受影響。
class StatusBarStableInset extends StatefulWidget {
  const StatusBarStableInset({super.key, required this.child});

  final Widget child;

  @override
  State<StatusBarStableInset> createState() => _StatusBarStableInsetState();
}

class _StatusBarStableInsetState extends State<StatusBarStableInset>
    with WidgetsBindingObserver {
  static const MethodChannel _systemBars = MethodChannel(
    'night_reader/system_bars',
  );

  /// 原生端量到的狀態列高度與量測時的視窗尺寸；尺寸變了（旋轉、分割畫面）
  /// 就先不套用，等重新量到為止。
  ({Size size, double extent})? _measured;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void didChangeMetrics() => unawaited(_refresh());

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    final double? extent;
    try {
      extent = await _systemBars.invokeMethod<double>('statusBarExtent');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
    if (!mounted || extent == null) return;
    final view = View.of(context);
    final measured = (
      size: view.physicalSize / view.devicePixelRatio,
      extent: extent,
    );
    if (measured == _measured) return;
    setState(() => _measured = measured);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final measured = _measured;
    final extent = measured != null && measured.size == media.size
        ? measured.extent
        : 0.0;
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(
          top: math.max(media.padding.top, extent),
        ),
        viewPadding: media.viewPadding.copyWith(
          top: math.max(media.viewPadding.top, extent),
        ),
      ),
      child: widget.child,
    );
  }
}

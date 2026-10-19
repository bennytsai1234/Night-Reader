import 'dart:async';
import 'dart:collection';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 骨架換成內容前，等內容建好、裡面的封面解碼好（[SkeletonSwitcher.waitForCovers]）。
///
/// 內容先在骨架底下以全透明建好。較重的一塊（一張書卡，[CoverRevealSlot]）
/// 排隊，一幀只建一塊：整頁擠在同一幀建完，骨架的呼吸會頓一下（ADR 0018）。
/// 裡面的封面（`BookCoverWidget`）解碼前 [add]、解碼好或失敗時 [remove]；
/// [settle] 等排隊的都建好，再等封面都好了（或逾時）就結束等待，整頁連同
/// 封面一次淡入。等待中解碼好的封面直接顯示，不另外淡入。
class CoverReveal extends ChangeNotifier {
  final Set<String> _pending = {};
  Completer<void>? _drained;
  bool _waiting = true;

  final Queue<VoidCallback> _builds = Queue();

  /// 排進來、還沒真的建好的塊數，包括已經放行、下一幀才建的。
  int _unbuilt = 0;
  Completer<void>? _allBuilt;

  /// 還在等封面；結束後新解碼的封面照常各自淡入。
  bool get waiting => _waiting;

  void add(String source) {
    if (_waiting) _pending.add(source);
  }

  void remove(String source) {
    if (!_pending.remove(source) || _pending.isNotEmpty) return;
    _drained?.complete();
    _drained = null;
  }

  /// 排一塊內容等著建，輪到時呼叫 [build]（之後那一幀才真的建）；建好或
  /// 不再需要時由那一塊呼叫 [_slotDone]。
  void _queueBuild(VoidCallback build) {
    _unbuilt++;
    _builds.add(build);
    if (_builds.length == 1) _grantNext();
  }

  void _slotDone() {
    if (_unbuilt == 0) return;
    _unbuilt--;
    if (_unbuilt > 0) return;
    _allBuilt?.complete();
    _allBuilt = null;
  }

  /// 每一幀畫完放行一塊：一塊書卡在電腦的 debug 模式約 3ms，一幀一塊放得
  /// 下；整頁一起建要 40ms 以上（`test/frame_budget/`）。
  void _grantNext() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_builds.isEmpty) return;
      _builds.removeFirst()();
      if (_builds.isNotEmpty) _grantNext();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// 等這一幀建好內容；排隊的一塊塊建完、封面都登記過，再等到封面都好了
  /// 或 [timeout]。排隊的不算在逾時裡：沒建完就換場會露出空格。
  Future<void> settle(Duration timeout) async {
    await SchedulerBinding.instance.endOfFrame;
    // 看的是「還沒建好」而不是「還在排隊」：最後一塊放行後下一幀才建，它的
    // 封面那時才登記。這一塊建好的那一幀，封面在同一個 build 裡登記，接下
    // 來的封面等待照樣等它。
    if (_unbuilt > 0) await (_allBuilt ??= Completer<void>()).future;
    if (_pending.isNotEmpty) {
      final drained = _drained = Completer<void>();
      await drained.future.timeout(timeout, onTimeout: () {});
    }
    _waiting = false;
    _pending.clear();
    notifyListeners();
  }
}

/// 把 [CoverReveal] 交給底下的封面。
class CoverRevealScope extends InheritedNotifier<CoverReveal> {
  const CoverRevealScope({
    super.key,
    required CoverReveal super.notifier,
    required super.child,
  });

  /// 還在等待中的 [CoverReveal]；不在等待中或不在範圍內時為 null。等待結束
  /// 時依賴的元件會重建。
  static CoverReveal? waitingOf(BuildContext context) {
    final reveal = context
        .dependOnInheritedWidgetOfExactType<CoverRevealScope>()
        ?.notifier;
    return reveal != null && reveal.waiting ? reveal : null;
  }
}

/// 骨架底下等著換場的內容裡較重的一塊（一張書卡）：輪到才建 [child]，之前
/// 畫 [placeholder]（和 [child] 一樣大，版面不變）。不在等待中（換場之後、
/// 捲動時才建的）直接建。
class CoverRevealSlot extends StatefulWidget {
  const CoverRevealSlot({
    super.key,
    this.placeholder = const SizedBox.shrink(),
    required this.child,
  });

  final Widget placeholder;
  final Widget child;

  @override
  State<CoverRevealSlot> createState() => _CoverRevealSlotState();
}

class _CoverRevealSlotState extends State<CoverRevealSlot> {
  bool _granted = false;
  CoverReveal? _queuedOn;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_granted) return;
    final reveal = CoverRevealScope.waitingOf(context);
    if (reveal == null) {
      _release();
      _granted = true;
      return;
    }
    if (identical(_queuedOn, reveal)) return;
    // 換了一輪等待（重新載入）：舊的那一輪不再等這一塊。
    _release();
    _queuedOn = reveal;
    reveal._queueBuild(() {
      if (mounted && !_granted) setState(() => _granted = true);
    });
  }

  /// 告訴排隊的那一輪這一塊建好了，或不再需要。
  void _release() {
    final reveal = _queuedOn;
    _queuedOn = null;
    reveal?._slotDone();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_granted) return widget.placeholder;
    _release();
    return widget.child;
  }
}

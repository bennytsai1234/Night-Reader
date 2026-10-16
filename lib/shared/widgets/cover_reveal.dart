import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 骨架換成內容前，等內容裡的封面解碼好（[SkeletonSwitcher.waitForCovers]）。
///
/// 內容先在骨架底下以全透明建好，裡面的封面（`BookCoverWidget`）解碼前
/// [add]、解碼好或失敗時 [remove]；[settle] 等到都好了（或逾時）就結束等待，
/// 整頁連同封面一次淡入。等待中解碼好的封面直接顯示，不另外淡入。
class CoverReveal extends ChangeNotifier {
  final Set<String> _pending = {};
  Completer<void>? _drained;
  bool _waiting = true;

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

  /// 等這一幀建好內容、封面都登記過，再等到封面都好了或 [timeout]。
  Future<void> settle(Duration timeout) async {
    await SchedulerBinding.instance.endOfFrame;
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

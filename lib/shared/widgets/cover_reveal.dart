import 'dart:async';
import 'dart:collection';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_tokens.dart';
import 'painted_when.dart';

/// 換場前怎麼等封面（[SkeletonSwitcher.waitForCovers]）。
enum CoverWait {
  /// 畫面上的封面（網路的也算）最多等 [AppMotion.revealCoverWait]，還沒好的
  /// 換場後各自淡入：發現的書單、分組清單、書源管理。
  brief,

  /// 手機裡已經有的封面全部畫得出來才換場，不設時間上限；要上網抓的網路
  /// 封面不等：開 App 的書架（ADR 0031）。
  onDevice,
}

/// 骨架換成內容前，等內容建好、裡面的封面畫得出來（[SkeletonSwitcher.waitForCovers]）。
///
/// 內容先在骨架底下以全透明建好。較重的一塊（一張書卡，[CoverRevealSlot]）
/// 排隊，一幀只建一塊：整頁擠在同一幀建完，骨架的呼吸會頓一下（ADR 0018）。
/// 裡面的封面（`BookCoverWidget`）解碼前 [add]、解碼好、失敗或不再顯示時
/// [remove]（[CoverWait.onDevice] 時要上網抓的封面不登記）。[settle] 等排隊的
/// 都建好，再照 [wait] 等登記的封面，整頁連同封面一次換場。
/// [CoverWait.onDevice] 不設時間上限：每一個登記都一定會以解碼好、失敗或
/// 拆掉結束。等待中解碼好的封面直接顯示，不另外淡入。
///
/// [inSteps] 時每一塊再拆成更小的步驟，和建好的塊一起排隊、一幀只放行一步：
/// 建好、排好版的那一幀先不畫，下一步才第一次畫出來（字第一次出現要先畫
/// 進字形快取）；等待中解碼好的封面也排隊，一步只換上一張（[showCover]）。
/// 開 App 的書架用：內容在骨架呼吸時於底下準備，呼吸的每一格只多一小步。
class CoverReveal extends ChangeNotifier {
  CoverReveal(this.wait, {this.inSteps = false});

  final CoverWait wait;

  /// 第一次畫與換上封面也拆成各自一步，見 [CoverReveal]。
  final bool inSteps;

  final Set<Object> _pending = {};
  Completer<void>? _drained;
  bool _waiting = true;

  /// 排隊的步驟：建一塊、第一次畫一塊、換上一張封面。
  final Queue<VoidCallback> _steps = Queue();

  /// 排進來、還沒真的建好（[inSteps] 時是還沒畫出來）的塊數，包括已經放行、
  /// 下一幀才建的。
  int _unbuilt = 0;
  Completer<void>? _allBuilt;

  /// 還在等封面；結束後新解碼的封面照常各自淡入。
  bool get waiting => _waiting;

  /// 登記一張還畫不出來的封面；[cover] 是那一張封面自己（同一張重複登記
  /// 只算一次，同一個來源的兩張封面各算各的）。
  void add(Object cover) {
    if (_waiting) _pending.add(cover);
  }

  /// [cover] 畫得出來了、失敗了，或不再顯示。
  void remove(Object cover) {
    if (!_pending.remove(cover) || _pending.isNotEmpty) return;
    _drained?.complete();
    _drained = null;
  }

  /// 排一塊內容等著建，輪到時呼叫 [build]（之後那一幀才真的建）；建好或
  /// 不再需要時由那一塊呼叫 [_slotDone]。
  void _queueBuild(VoidCallback build) {
    _unbuilt++;
    _queueStep(build);
  }

  /// [inSteps] 時，等待中解碼好的一張封面排隊換上去：輪到時呼叫 [show]
  /// （之後那一幀才換上）。封面換上之前照樣登記著，換場等它。
  void showCover(VoidCallback show) => _queueStep(show);

  void _queueStep(VoidCallback step) {
    _steps.add(step);
    if (_steps.length == 1) _grantNext();
  }

  void _slotDone() {
    if (_unbuilt == 0) return;
    _unbuilt--;
    if (_unbuilt > 0) return;
    _allBuilt?.complete();
    _allBuilt = null;
  }

  /// 每一幀畫完放行一步：一塊書卡在電腦的 debug 模式約 3ms，一幀一塊放得
  /// 下；整頁一起建要 40ms 以上（`test/frame_budget/`）。
  void _grantNext() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_steps.isEmpty) return;
      _steps.removeFirst()();
      if (_steps.isNotEmpty) _grantNext();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// 等這一幀建好內容；排隊的一塊塊建完、封面都登記過，再等到登記的封面
  /// 都畫得出來（或失敗、拆掉）；[CoverWait.brief] 最多等
  /// [AppMotion.revealCoverWait]。排隊的不算在逾時裡：沒建完就換場會露出
  /// 空格。
  Future<void> settle() async {
    await SchedulerBinding.instance.endOfFrame;
    // 看的是「還沒建好」而不是「還在排隊」：最後一塊放行後下一幀才建，它的
    // 封面那時才登記。這一塊建好的那一幀，封面在同一個 build 裡登記，接下
    // 來的封面等待照樣等它。
    if (_unbuilt > 0) await (_allBuilt ??= Completer<void>()).future;
    if (_pending.isNotEmpty) {
      final drained = (_drained = Completer<void>()).future;
      await switch (wait) {
        CoverWait.brief => drained.timeout(
          AppMotion.revealCoverWait,
          onTimeout: () {},
        ),
        CoverWait.onDevice => drained,
      };
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
    this.wait = true,
    required this.child,
  });

  final Widget placeholder;

  /// false 時不排隊、直接建，換場也不等它（畫面外的列）。只看建立當下的
  /// 值；同一個位置之後改了也不會換掉已經建好的內容。
  final bool wait;
  final Widget child;

  @override
  State<CoverRevealSlot> createState() => _CoverRevealSlotState();
}

class _CoverRevealSlotState extends State<CoverRevealSlot> {
  bool _granted = false;
  CoverReveal? _queuedOn;

  /// 建好時那一輪是 [CoverReveal.inSteps]：[child] 外面一直包著
  /// [PaintedWhen]，元件樹的形狀不變。
  bool _inSteps = false;

  /// [_inSteps] 時，建好之後排到的下一步才畫出來。
  bool _painted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 建好、也畫出來了（或不分步）就不再排隊。
    if (_granted && (!_inSteps || _painted)) return;
    final reveal = widget.wait ? CoverRevealScope.waitingOf(context) : null;
    if (reveal != null && identical(_queuedOn, reveal)) return;
    // 換了一輪等待（重新載入）或等待結束：舊的那一輪不再等這一塊，它排著的
    // 這一塊的步驟一律作廢（每一步執行前都核對還是不是這一輪的）。
    _release();
    if (reveal == null) {
      _granted = true;
      _painted = true;
      return;
    }
    _queuedOn = reveal;
    void paint() {
      if (mounted && identical(_queuedOn, reveal)) {
        setState(() => _painted = true);
      }
    }

    if (_granted) {
      // 上一輪建好、還沒畫：畫的那一步改由這一輪排、這一輪等。
      reveal._queueBuild(paint);
      return;
    }
    reveal._queueBuild(() {
      if (!mounted || !identical(_queuedOn, reveal)) return;
      setState(() {
        _granted = true;
        _inSteps = reveal.inSteps;
      });
    });
    // 建的那一步只建、只排版，緊接著的下一步才第一次畫。兩步一起排進去：
    // 這一塊的封面要等建好才開始解碼，換上封面的那一步一定排在畫之後，字和
    // 封面不會擠在同一幀第一次畫。
    if (reveal.inSteps) reveal._queueStep(paint);
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
    if (!_inSteps) {
      _release();
      return widget.child;
    }
    // 畫出來了才算這一塊好了，換場等它。
    if (_painted) _release();
    return PaintedWhen(shown: _painted, child: widget.child);
  }
}

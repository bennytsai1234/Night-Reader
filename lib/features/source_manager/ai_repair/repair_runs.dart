import 'dart:async';

import 'package:flutter/material.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/source_repair_batch.dart';
import 'package:night_reader/core/services/background_work/background_work.dart';
import 'package:night_reader/shared/navigation/root_navigator.dart';

import 'ai_repair_page.dart';
import 'source_repair_page.dart';

/// 按了停止、還沒停好時的通知內文（`BackgroundWorkService.kt` 認這幾個字，
/// 這時不再放「停止」按鈕）。
const String backgroundWorkStopping = '正在停下…';

/// 修復異常書源的四段，頁面第一張卡片照這個順序列。
const List<RepairStage> repairStages = [
  RepairStage.checking,
  RepairStage.checkingSites,
  RepairStage.moving,
  RepairStage.repairing,
];

/// 頁面上這一段的名稱。
String repairStageTitle(RepairStage stage) => switch (stage) {
  RepairStage.checking => '重新校驗',
  RepairStage.checkingSites => '檢查網站',
  RepairStage.moving => '網站搬家的換網址',
  RepairStage.repairing || RepairStage.sharing => 'AI 修，每個網站一個',
  RepairStage.done => '',
};

/// 通知內文前面的段名：比頁面上的短，後面接著進度。
String _repairStageShortTitle(RepairStage stage) => switch (stage) {
  RepairStage.checking => '重新校驗',
  RepairStage.checkingSites => '檢查網站',
  RepairStage.moving => '換網址',
  RepairStage.repairing || RepairStage.sharing || RepairStage.done => 'AI 修',
};

/// 正在做的那一段做到哪：「第 12／199 個」「7／24 個網站」。頁面那一段的
/// 副標與通知內文用同一句（ADR 0058）。
String repairStageProgress(SourceRepairBatch batch) {
  final progress = '${batch.stageDone}／${batch.stageTotal}';
  return switch (batch.stage) {
    RepairStage.checking => '第 $progress 個',
    RepairStage.checkingSites ||
    RepairStage.repairing ||
    RepairStage.sharing => '$progress 個網站',
    RepairStage.moving => '$progress 個',
    RepairStage.done => '',
  };
}

/// 整批的進度：四段各佔四分之一，這一段做完的比例佔那四分之一的幾成。
double repairBatchProgress(SourceRepairBatch batch) {
  if (batch.isFinished) return 1;
  final index = switch (batch.stage) {
    RepairStage.sharing => repairStages.indexOf(RepairStage.repairing),
    final stage => repairStages.indexOf(stage),
  };
  if (index < 0) return 0;
  final part = batch.stageTotal > 0
      ? (batch.stageDone / batch.stageTotal).clamp(0.0, 1.0)
      : 0.0;
  return (index + part) / repairStages.length;
}

/// 一件修復：頁面關了照跑，入口再按推回同一件（ADR 0058）。做完、而且有頁面
/// 開著看過結果之後，最後一頁關掉才算結束。
abstract class RepairRun extends ChangeNotifier implements BackgroundJob {
  RepairRun({BackgroundWork? work, NavigatorState? Function()? navigator})
    : _work = work ?? BackgroundWork.instance,
      _navigator = navigator ?? (() => rootNavigatorKey.currentState);

  final BackgroundWork _work;
  final NavigatorState? Function() _navigator;

  bool _started = false;
  bool _finished = false;
  bool _seen = false;
  int _pages = 0;
  Route<void>? _topRoute;

  bool get isFinished => _finished;

  /// 做完而且看過了：書源管理可以收掉它、下次重開一件。
  bool get isDone => _finished && _seen && _pages == 0;

  /// 通知欄這時要顯示的樣子。
  BackgroundWorkStatus get status;

  /// 開始做；回傳做完（停下、出錯也算）的時刻。
  Future<void> run();

  /// 停下：正在做的那一件不改書源，已經存的照存。
  void stop();

  /// 這一件的頁面。
  Widget page();

  /// 做完之後在結果頁刪了、併了幾次書源：書源管理看到它變了就重讀清單。
  int get sourceEdits => 0;

  /// 工作本身（批次、單一修復）做完之後放掉資源。
  void disposeWork();

  /// 推入動畫播完才開始（ADR 0018）：頁面呼叫。要在 App 看得到時開始，
  /// Android 才肯開前景服務。
  void start() {
    if (_started) return;
    _started = true;
    _work.begin(this, status);
    unawaited(
      run().whenComplete(() {
        _finished = true;
        _work.end(this);
        if (_pages > 0) _seen = true;
        notifyListeners();
      }),
    );
  }

  /// 工作的內容變了：更新通知。
  @protected
  void changed() {
    if (_started && !_finished) _work.update(this, status);
  }

  /// 頁面打開與關掉時呼叫，算有沒有人看著。
  void attach() {
    _pages++;
    if (_finished) _seen = true;
  }

  /// 最上面那一頁的路由：點通知時它已經在最上面就不再推一頁。
  set route(Route<void>? route) => _topRoute = route;

  void detach() {
    _pages--;
    if (_pages > 0) return;
    _topRoute = null;
    // 頁面還在拆：等它的監聽都拿掉，再讓書源管理收掉這一件。
    if (isDone) scheduleMicrotask(notifyListeners);
  }

  @override
  void stopFromSystem() {
    stop();
    changed();
  }

  @override
  void openFromNotification() {
    final navigator = _navigator();
    if (navigator == null) return;
    final top = _topRoute;
    if (top != null && top.isCurrent) return;
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => page())));
  }
}

/// 修復異常書源（一批）。
class BatchRepairRun extends RepairRun {
  BatchRepairRun(
    this.batch, {
    required this.title,
    super.work,
    super.navigator,
  }) {
    batch
      ..addListener(changed)
      ..addListener(_watchEdits);
  }

  final SourceRepairBatch batch;
  final String title;
  int _seenEdits = 0;

  @override
  int get sourceEdits => batch.sourceEdits;

  void _watchEdits() {
    if (batch.sourceEdits == _seenEdits) return;
    _seenEdits = batch.sourceEdits;
    notifyListeners();
  }

  @override
  BackgroundWorkStatus get status => BackgroundWorkStatus(
    title: title,
    text: batch.isStopped
        ? backgroundWorkStopping
        : '${_repairStageShortTitle(batch.stage)}，${repairStageProgress(batch)}',
    progress: repairBatchProgress(batch),
  );

  @override
  Future<void> run() => batch.start();

  @override
  void stop() => batch.stop();

  @override
  Widget page() => SourceRepairPage(run: this);

  @override
  void disposeWork() {
    batch
      ..removeListener(changed)
      ..removeListener(_watchEdits)
      ..dispose();
  }
}

/// 單一書源的 AI 修復（用 AI 服務的；剪貼簿的要使用者來回貼，留在頁面上）。
class SingleRepairRun extends RepairRun {
  SingleRepairRun(this.session, {super.work, super.navigator}) {
    session.addListener(changed);
  }

  final AiRepairSession session;

  String get sourceUrl => session.job.original.bookSourceUrl;

  @override
  BackgroundWorkStatus get status {
    final step = session.job.steps.lastOrNull;
    return BackgroundWorkStatus(
      title: 'AI 修復 · ${session.job.original.bookSourceName}',
      text: session.isStopped ? backgroundWorkStopping : step?.title ?? '準備中…',
    );
  }

  @override
  Future<void> run() => session.start();

  @override
  void stop() => session.stop();

  @override
  Widget page() => AiRepairPage(session: session, owned: false, run: this);

  @override
  void disposeWork() {
    session.removeListener(changed);
    session.dispose();
  }
}

/// 正在跑、或做完還沒看過結果的那一件修復。書源管理的入口照它決定推回
/// 同一件還是開新的；它做完時書源管理重讀清單。
class RepairRuns extends ChangeNotifier {
  static final RepairRuns instance = RepairRuns();

  RepairRun? _current;

  RepairRun? get current => _current;

  /// 舊結果已經看過、頁面也關了，才可以開始下一件。
  bool get canStartNew => _current == null || _current!.isDone;

  /// 修完但還沒看過結果時，不允許新工作覆蓋舊結果。
  /// 回傳 false 時由呼叫端收掉尚未開始的新工作。
  bool adopt(RepairRun run) {
    if (!canStartNew) return false;
    _drop();
    _current = run..addListener(_changed);
    notifyListeners();
    return true;
  }

  void _changed() {
    final run = _current;
    if (run != null && run.isDone) _drop();
    notifyListeners();
  }

  void _drop() {
    final run = _current;
    if (run == null || !run.isDone) return;
    _current = null;
    run
      ..removeListener(_changed)
      ..disposeWork()
      ..dispose();
  }
}

/// 一次只跑一件（ADR 0058）：有背景工作在跑時，書源管理的修復與校驗入口是
/// 灰的，只有推回正在跑的那一件的還能按。
bool backgroundWorkIdle() => !BackgroundWork.instance.isBusy;

/// 單一書源的「AI 修復」能不能按：這個書源正在修（推回那一頁），或沒有
/// 工作、沒有校驗在跑（登入完的自動校驗也算）。
bool canAiRepair(String sourceUrl, {required bool checking}) {
  final current = RepairRuns.instance.current;
  if (current is SingleRepairRun &&
      !current.isDone &&
      current.sourceUrl == sourceUrl) {
    return true;
  }
  return !checking && RepairRuns.instance.canStartNew && backgroundWorkIdle();
}

/// 「修復異常書源」能不能按：有一批正在修或還沒看結果（推回那一批），或
/// 沒有工作在跑。
bool canRepairBatch() {
  final current = RepairRuns.instance.current;
  if (current is BatchRepairRun && !current.isDone) return true;
  return RepairRuns.instance.canStartNew && backgroundWorkIdle();
}

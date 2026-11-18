import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:night_reader/core/ai_repair/ai_repair_session.dart';
import 'package:night_reader/core/ai_repair/source_repair_batch.dart';
import 'package:night_reader/core/ai_repair/ai_repair_settings.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/background_work/background_work.dart';
import 'package:night_reader/core/services/background_work/paused_work_file.dart';
import 'package:night_reader/shared/navigation/root_navigator.dart';

import 'ai_repair_page.dart';
import 'source_repair_page.dart';

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
  RepairStage.moving => '換網址',
  RepairStage.repairing || RepairStage.sharing => 'AI 修',
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

/// 一件背景工作的頁面那一半：頁面關了照跑，入口再按推回同一件（ADR 0058）。
/// 做完、而且有頁面開著看過結果之後，最後一頁關掉才算結束。
///
/// 能暫停的（[canPause]）：按暫停、從最近使用滑掉或被系統收掉都停在做完的
/// 那一步，位置空出來；按繼續（[resume]）從那裡接著做，按結束（[end]）收尾、
/// 結果留著。暫停中的還沒結束：入口推回它，不開新的一件。
abstract class RepairRun extends ChangeNotifier implements BackgroundJob {
  RepairRun({
    BackgroundWork? work,
    NavigatorState? Function()? navigator,
    bool paused = false,
  }) : _work = work ?? BackgroundWork.instance,
       _navigator = navigator ?? (() => rootNavigatorKey.currentState),
       _started = paused,
       _paused = paused {
    // 暫停中的頁面要知道位置空出來了沒，「繼續」才跟著能按。
    _work.addListener(_slotChanged);
  }

  void _slotChanged() {
    if (_paused) notifyListeners();
  }

  @override
  void dispose() {
    _work.removeListener(_slotChanged);
    super.dispose();
  }

  final BackgroundWork _work;
  final NavigatorState? Function() _navigator;

  bool _started;
  bool _finished = false;
  bool _seen = false;
  bool _paused;
  bool _resuming = false;
  bool _ending = false;
  int _pages = 0;
  Route<void>? _topRoute;

  bool get isFinished => _finished;

  /// 停在做完的那一步，等使用者按繼續或結束。
  bool get isPaused => _paused;

  /// 正在跑（含按了暫停或結束、還沒停好）。
  bool get isRunning => _started && !_finished && !_paused;

  /// 暫停中按了繼續、正在讀回存檔，或按了結束、正在收尾。
  bool get isSettling => _resuming || _ending;

  /// 暫停中按了結束、正在收尾。
  bool get isEnding => _ending;

  /// 做完而且看過了：入口可以收掉它、下次重開一件。
  bool get isDone => _finished && _seen && _pages == 0;

  /// 頁面的「繼續」能不能按：暫停中，而且沒有別的背景工作在跑。
  bool get canResume => _paused && !isSettling && !_work.isBusy;

  /// 這件工作暫停後能接著做。不能的，暫停照結束處理。
  bool get canPause => false;

  /// 通知欄這時要顯示的樣子。
  BackgroundWorkStatus get status;

  /// 開始做或接著做；回傳做完（結束、出錯也算）或暫停好的時刻。
  Future<void> run();

  /// [run] 回來時是暫停好了（不是做完）。
  bool get workPaused => false;

  /// 結束：正在做的那一件不改書源，已經存的照存。
  void stop();

  /// 暫停：停在做完的那一步。能暫停的才會叫。
  void pause() {}

  /// 暫停中按了結束：收尾、結果留著（找書存成過去的找書）。
  Future<void> endPaused() async {}

  /// 按了繼續：讀回存檔、建好接著做要換上的新工作（還不換上）；接不下去
  /// （例如 AI 服務被刪了）傳回 false。
  Future<bool> prepareResume() async => false;

  /// 換上 [prepareResume] 建好的新工作：位置空著、等的時候沒按結束才叫。
  void commitResume() {}

  /// [prepareResume] 建好的不用了（等的時候按了結束、位置被別件佔了）：放掉。
  void discardResume() {}

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
    _launch();
  }

  void _launch() {
    _work.begin(this, status);
    unawaited(
      run().whenComplete(() {
        if (workPaused && !_finished) {
          _paused = true;
        } else {
          _finish();
        }
        _work.end(this);
        notifyListeners();
      }),
    );
  }

  void _finish() {
    _finished = true;
    if (_pages > 0) _seen = true;
  }

  /// 頁面的「繼續」：位置空著才接著做。
  Future<void> resume() async {
    if (!canResume) return;
    _resuming = true;
    notifyListeners();
    try {
      if (!await prepareResume()) return;
      if (!_paused || _ending || _finished || _work.isBusy) {
        discardResume();
        return;
      }
      commitResume();
      _paused = false;
      _launch();
    } finally {
      _resuming = false;
      notifyListeners();
    }
  }

  /// 頁面的「暫停」：不能暫停的工作照結束處理。
  void pauseNow() {
    if (!isRunning) return;
    canPause ? pause() : stop();
    changed();
  }

  /// 頁面與通知的「結束」：做著的停下收尾，暫停中的直接收尾。
  Future<void> end() async {
    if (_finished || _ending) return;
    if (!_paused) {
      if (!_started) return;
      stop();
      changed();
      return;
    }
    _ending = true;
    notifyListeners();
    try {
      await endPaused();
    } finally {
      _ending = false;
      _paused = false;
      _finish();
      notifyListeners();
    }
  }

  /// 工作的內容變了：更新通知。
  @protected
  void changed() {
    if (isRunning) _work.update(this, status);
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
  void pauseFromSystem() => pauseNow();

  @override
  void endFromSystem() => unawaited(end());

  @override
  void openFromNotification() {
    final navigator = _navigator();
    if (navigator == null) return;
    final top = _topRoute;
    if (top != null && top.isCurrent) return;
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => page())));
  }
}

/// 暫停的修復存在哪個檔（[PausedWorkFile.name]）：單一書源與一批共用，一次只有
/// 一件修復。
const String repairProgressName = 'repair';

/// 存檔的格式版本：改了存什麼就加一，舊版的讀不回來。
const int _repairProgressVersion = 1;

/// 一批修復暫停時存的：這批的書源（現在的網址）、已經有結果的、沿用校驗的
/// 書源與用了多少 token（含沒定案的書源已經花掉的）。
typedef BatchRepairProgress = ({
  List<String> urls,
  Map<String, RepairDone> done,
  Set<String> reused,
  int tokensUsed,
});

/// 接著修一批：照存的書源與結果建新的一批，用現在的 AI 服務設定；沒有 AI
/// 服務是 null。
typedef BatchRepairReopen = Future<SourceRepairBatch?> Function(
  BatchRepairProgress progress,
);

/// 修復異常書源（一批）。每有書源定案就存一次（哪些書源、各自的結果）：暫停
/// （按暫停、從最近使用滑掉、被系統收掉）後按繼續用同一批書源重開，已經有
/// 結果的帶著結果不再處理；暫停時正在 AI 修的書源從頭重修（使用者
/// 2026-11-15 選，ADR 0058）。
class BatchRepairRun extends RepairRun {
  BatchRepairRun(
    this._batch, {
    required this.title,
    PausedWorkFile? progress,
    BatchRepairReopen? reopen,
    super.work,
    super.navigator,
  }) : _file = progress ?? PausedWorkFile(repairProgressName),
       _reopen = reopen ?? _reopenWithService {
    _adopt(_batch);
  }

  /// 開 App 時讀回的暫停中的那一批：照存檔顯示，還沒開始。
  BatchRepairRun.paused(
    this._batch, {
    required this.title,
    required this._file,
    BatchRepairReopen? reopen,
    super.work,
    super.navigator,
  }) : _reopen = reopen ?? _reopenWithService,
       super(paused: true) {
    _adopt(_batch);
  }

  SourceRepairBatch _batch;

  /// 現在這一批：暫停後接著做時換成新建的一批。
  SourceRepairBatch get batch => _batch;
  final String title;
  final PausedWorkFile _file;
  final BatchRepairReopen _reopen;
  int _seenEdits = 0;
  int _savedDone = -1;
  bool _pausedWork = false;
  SourceRepairBatch? _next;

  static Future<SourceRepairBatch?> _reopenWithService(
    BatchRepairProgress progress,
  ) async {
    final settings = AiRepairSettings();
    final service = await settings.service();
    if (service == null) return null;
    final concurrency = await settings.concurrency();
    final sources = await _loadSources(progress.urls);
    return SourceRepairBatch(
      sources: sources,
      service: service,
      aiConcurrency: concurrency,
      done: progress.done,
      reused: progress.reused,
      tokensUsed: progress.tokensUsed,
    );
  }

  void _adopt(SourceRepairBatch batch) {
    _batch = batch
      ..addListener(changed)
      ..addListener(_watchEdits)
      ..addListener(_watchDone);
    _seenEdits = batch.sourceEdits;
  }

  void _drop(SourceRepairBatch batch) {
    batch
      ..removeListener(changed)
      ..removeListener(_watchEdits)
      ..removeListener(_watchDone);
  }

  @override
  int get sourceEdits => _batch.sourceEdits;

  void _watchEdits() {
    if (_batch.sourceEdits == _seenEdits) return;
    _seenEdits = _batch.sourceEdits;
    notifyListeners();
  }

  /// 有書源定案就存一次（只在跑的時候）。
  void _watchDone() {
    if (!isRunning || _file.isClosed) return;
    final done = _batch.items.where((item) => item.isFinished).length;
    if (done == _savedDone) return;
    _savedDone = done;
    _save();
  }

  void _save() {
    final service = _batch.service;
    _file.save(
      jsonEncode({
        'version': _repairProgressVersion,
        'kind': 'batch',
        'title': title,
        'baseUrl': service.baseUrl,
        'model': service.model,
        'urls': [for (final item in _batch.items) item.source.bookSourceUrl],
        'done': {
          for (final MapEntry(:key, :value) in _batch.done.entries)
            key: [value.outcome.name, value.detail, value.tokens],
        },
        'reused': [..._batch.reused],
        'tokensUsed': _batch.tokensUsed,
      }),
    );
  }

  @override
  bool get canPause => true;

  @override
  bool get workPaused => _pausedWork;

  @override
  BackgroundWorkStatus get status =>
      _batch.isStopped || (_batch.isPaused && _batch.isRunning)
      ? BackgroundWorkStatus.settling(
          title,
          pausing: _batch.isPaused,
          progress: repairBatchProgress(_batch),
        )
      : BackgroundWorkStatus(
          title: title,
          text:
              '${_repairStageShortTitle(_batch.stage)}，${repairStageProgress(_batch)}',
          progress: repairBatchProgress(_batch),
          pausable: true,
        );

  @override
  Future<void> run() async {
    _pausedWork = false;
    _savedDone = -1;
    _save();
    await _batch.start();
    if (_batch.isPaused) {
      _pausedWork = true;
      return;
    }
    await _file.close();
  }

  @override
  void stop() {
    unawaited(_file.close());
    _batch.stop();
  }

  @override
  void pause() => _batch.pause();

  @override
  Future<void> endPaused() async {
    _batch.stop();
    await _file.close();
  }

  @override
  Future<bool> prepareResume() async {
    _next = await _reopen((
      urls: [for (final item in _batch.items) item.source.bookSourceUrl],
      done: _batch.done,
      reused: _batch.reused,
      tokensUsed: _batch.tokensUsed,
    ));
    return _next != null;
  }

  @override
  void commitResume() {
    final next = _next;
    if (next == null) return;
    _next = null;
    final previous = _batch;
    // 已經有結果的書源經手的 AI 修復交給新的一批：照舊點得進去、打包得到。
    for (final session in next.adoptSessions(previous.takeFinishedSessions())) {
      session.dispose();
    }
    _drop(previous);
    _adopt(next);
    notifyListeners();
    scheduleMicrotask(previous.dispose);
  }

  @override
  void discardResume() {
    _next?.dispose();
    _next = null;
  }

  @override
  Widget page() => SourceRepairPage(run: this);

  @override
  void disposeWork() {
    _drop(_batch);
    _batch.dispose();
  }
}

/// 接著修一個書源：照網址讀回書源、用現在的 AI 服務設定建新的一段修復；
/// 書源不在了或沒有 AI 服務是 null。
typedef SingleRepairReopen = Future<AiRepairSession?> Function(String url);

/// 單一書源的 AI 修復（用 AI 服務的；剪貼簿的要使用者來回貼，留在頁面上）。
/// 暫停後按繼續是這個書源從頭重修（使用者 2026-11-15 選，ADR 0058）。
class SingleRepairRun extends RepairRun {
  SingleRepairRun(
    this._session, {
    PausedWorkFile? progress,
    SingleRepairReopen? reopen,
    Future<void> Function(BookSource source, String? reason)? markUnfixable,
    super.work,
    super.navigator,
  }) : _file = progress ?? PausedWorkFile(repairProgressName),
       _reopen = reopen ?? _reopenWithService,
       _markUnfixable = markUnfixable ?? markAiUnfixable {
    _session.addListener(changed);
  }

  /// 開 App 時讀回的暫停中的那一件：照存的書源顯示，還沒開始。
  SingleRepairRun.paused(
    this._session, {
    required this._file,
    SingleRepairReopen? reopen,
    Future<void> Function(BookSource source, String? reason)? markUnfixable,
    super.work,
    super.navigator,
  }) : _reopen = reopen ?? _reopenWithService,
       _markUnfixable = markUnfixable ?? markAiUnfixable,
       super(paused: true) {
    _session.addListener(changed);
  }

  AiRepairSession _session;

  /// 現在這一段修復：暫停後接著做時換成新的一段。
  AiRepairSession get session => _session;
  final PausedWorkFile _file;
  final SingleRepairReopen _reopen;
  final Future<void> Function(BookSource source, String? reason) _markUnfixable;
  bool _pausedWork = false;
  int _sourceEdits = 0;

  @override
  int get sourceEdits => _sourceEdits;

  String get sourceUrl => _session.job.original.bookSourceUrl;

  static Future<AiRepairSession?> _reopenWithService(String url) async {
    final service = await AiRepairSettings().service();
    if (service == null) return null;
    final source = await getIt<BookSourceDao>().getByUrl(url);
    if (source == null) return null;
    return AiRepairSession(source: source, service: service);
  }

  @override
  bool get canPause => true;

  @override
  bool get workPaused => _pausedWork;

  @override
  BackgroundWorkStatus get status {
    final title = 'AI 修復 · ${_session.job.original.bookSourceName}';
    if (_session.isStopped || (_session.isPaused && _session.isRunning)) {
      return BackgroundWorkStatus.settling(title, pausing: _session.isPaused);
    }
    return BackgroundWorkStatus(
      title: title,
      text: _session.job.steps.lastOrNull?.line ?? '準備中…',
      pausable: true,
    );
  }

  @override
  Future<void> run() async {
    _pausedWork = false;
    _file.save(
      jsonEncode({
        'version': _repairProgressVersion,
        'kind': 'single',
        'url': sourceUrl,
      }),
    );
    await _session.start();
    if (_session.isPaused) {
      _pausedWork = true;
      return;
    }
    // 單一修復也必須保留「網站不穩定＝無法修復」的可移除狀態。
    if (_session.job.confirmedUnfixable &&
        _session.job.giveUpWhy == 'site_unstable') {
      await _markUnfixable(_session.job.original, _session.job.giveUpWhy);
      _sourceEdits++;
    }
    await _file.close();
  }

  @override
  void stop() {
    unawaited(_file.close());
    _session.stop();
  }

  @override
  void pause() => _session.pause();

  @override
  Future<void> endPaused() async {
    _session.stop();
    await _file.close();
  }

  AiRepairSession? _next;

  @override
  Future<bool> prepareResume() async {
    _next = await _reopen(sourceUrl);
    return _next != null;
  }

  @override
  void commitResume() {
    final next = _next;
    if (next == null) return;
    _next = null;
    final previous = _session..removeListener(changed);
    _session = next..addListener(changed);
    notifyListeners();
    scheduleMicrotask(previous.dispose);
  }

  @override
  void discardResume() {
    _next?.dispose();
    _next = null;
  }

  @override
  Widget page() => AiRepairPage(session: _session, owned: false, run: this);

  @override
  void disposeWork() {
    _session.removeListener(changed);
    _session.dispose();
  }
}

/// 照網址讀回書源，照原本的順序；不在了的略過。
Future<List<BookSource>> _loadSources(List<String> urls) async {
  final dao = getIt<BookSourceDao>();
  return [for (final url in urls) ?await dao.getByUrl(url)];
}

/// 開 App 時讀回暫停的修復（被系統收掉、從最近使用滑掉都算暫停，ADR 0058）：
/// 書源管理的入口推回它，頁面顯示已暫停。書源都不在了、或存檔讀不出來時
/// 存檔刪掉。
Future<void> restorePausedRepair({
  PausedWorkFile? file,
  RepairRuns? runs,
  Future<List<BookSource>> Function(List<String> urls)? load,
  SingleRepairReopen? reopenSingle,
  BatchRepairReopen? reopenBatch,
  BackgroundWork? work,
}) async {
  final store = file ?? PausedWorkFile(repairProgressName);
  final repairs = runs ?? RepairRuns.instance;
  final text = await store.read();
  if (text == null || repairs.current != null) return;
  final loadSources = load ?? _loadSources;
  RepairRun? run;
  try {
    final json = jsonDecode(text);
    if (json case {
      'version': _repairProgressVersion,
      'kind': 'single',
      'url': final String url,
    }) {
      final source = (await loadSources([url])).firstOrNull;
      if (source != null) {
        run = SingleRepairRun.paused(
          AiRepairSession(source: source, service: null),
          file: store,
          reopen: reopenSingle,
          work: work,
        );
      }
    } else if (json case {
      'version': _repairProgressVersion,
      'kind': 'batch',
      'title': final String title,
      'baseUrl': final String baseUrl,
      'model': final String model,
      'urls': final List<Object?> urls,
      'done': final Map<String, Object?> done,
      'reused': final List<Object?> reused,
      'tokensUsed': final int tokensUsed,
    }) {
      final sources = await loadSources([for (final url in urls) '$url']);
      if (sources.isNotEmpty) {
        run = BatchRepairRun.paused(
          SourceRepairBatch(
            sources: sources,
            service: (baseUrl: baseUrl, apiKey: '', model: model, effort: ''),
            done: {
              for (final MapEntry(:key, :value) in done.entries)
                if (value case [
                  final String outcome,
                  final String detail,
                  final int tokens,
                ])
                  key: (
                    outcome: RepairOutcome.values.firstWhere(
                      (value) => value.name == outcome,
                      orElse: () => RepairOutcome.notTried,
                    ),
                    detail: detail,
                    tokens: tokens,
                  ),
            },
            reused: {for (final url in reused) '$url'},
            tokensUsed: tokensUsed,
          ),
          title: title,
          file: store,
          reopen: reopenBatch,
          work: work,
        );
      }
    }
  } on FormatException catch (error) {
    AppLog.w('restorePausedRepair: 讀不出來：$error');
  }
  // 讀書源的時候使用者開始了新的修復：讓它照舊，這份不讀（存檔由
  // PausedWorkFile 判斷是不是新的那件的，不會刪錯）。
  if (repairs.current != null) {
    run
      ?..disposeWork()
      ..dispose();
    return;
  }
  if (run == null) {
    await store.close();
    return;
  }
  if (!repairs.adopt(run)) {
    run
      ..disposeWork()
      ..dispose();
  }
}

/// 正在跑、或做完還沒看過結果的那一件修復。書源管理的入口照它決定推回
/// 同一件還是開新的；它做完時書源管理重讀清單。
class RepairRuns extends ChangeNotifier {
  RepairRuns({this.newEndsPaused = false});

  /// 書源管理的修復：暫停中的那件不擋新的一件，開始新的時候它就結束（使用者
  /// 2026-11-15 選，同校驗）。
  static final RepairRuns instance = RepairRuns(newEndsPaused: true);

  /// 開始新的一件時，暫停中的那件就結束。沒開時暫停中的擋著新的，入口推回它
  /// （AI 找書的 ✦）。
  final bool newEndsPaused;

  RepairRun? _current;

  RepairRun? get current => _current;

  /// 舊結果已經看過、頁面也關了（或暫停中、而且開新的會結束它），才可以開始
  /// 下一件。
  bool get canStartNew {
    final run = _current;
    return run == null ||
        run.isDone ||
        (newEndsPaused && run.isPaused && !run.isSettling);
  }

  /// 修完但還沒看過結果時，不允許新工作覆蓋舊結果。
  /// 回傳 false 時由呼叫端收掉尚未開始的新工作。
  bool adopt(RepairRun run) {
    if (!canStartNew) return false;
    final previous = _current;
    if (previous != null && previous.isPaused) {
      _current = null;
      previous.removeListener(_changed);
      // 收尾完才放掉：結束要刪存檔、寫結果，途中還會通知。
      unawaited(
        previous.end().whenComplete(() {
          previous
            ..disposeWork()
            ..dispose();
        }),
      );
    }
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
    run.removeListener(_changed);
    // 常是在這一件自己的通知裡走到這裡（看過結果、頁面關掉）：等它通知完
    // 再放掉，不然是在通知中途拆掉它的監聽清單。
    scheduleMicrotask(() {
      run
        ..disposeWork()
        ..dispose();
    });
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

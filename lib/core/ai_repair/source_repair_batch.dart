import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:night_reader/core/background_work/work_phase.dart';
import 'package:night_reader/core/models/source/source_site.dart';
import 'package:flutter/foundation.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/source/base_source.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/source_check/check_source_service.dart';
import 'package:night_reader/core/diagnostics/crash_trail.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';
import 'package:night_reader/core/utils/public_suffix.dart';
import 'package:uuid/uuid.dart';

import 'ai_repair_backups.dart';
import 'ai_repair_defaults.dart';
import 'ai_repair_apply.dart';
import 'ai_repair_prompt.dart';
import 'ai_repair_session.dart';
import 'ai_repair_settings.dart';
import 'repair_verdict.dart';
import 'site_check.dart';

/// 整批修復做到哪一段。
enum RepairStage {
  /// 重新校驗：標記可能過時了，先用現在的版本校驗一次。
  checking,

  /// 檢查每個網站：不在了、搬家、還是規則壞了。
  checkingSites,

  /// 搬家的網站換成新網址再校驗。
  moving,

  /// 每個網站挑一個書源交給 AI。
  repairing,

  /// AI 修好的規則套到同網站的其他書源。
  sharing,

  done,
}

/// 一個書源修完的結果。
enum RepairOutcome {
  /// 重新校驗就沒問題了。
  healthy,

  /// 換成網站的新網址就好了。
  moved,

  /// AI 修好了。
  aiFixed,

  /// 套用同網站 AI 修好的規則就好了。
  shared,

  /// 網站不在了：網域查不到、停放或出售、只剩空殼。
  siteGone,

  /// 試過了沒修好。
  notFixed,

  /// 不修：需要登入、在網頁驗證、只能下載、夜讀不支援的類型、只有發現頁。
  skipped,

  /// AI 之前試過修不好（書源帶「AI 修不好」），這次跳過。
  aiUnfixable,

  /// 未處理：校驗沒有結果、花費到了上限，或按了結束。
  notTried,
}

/// 暫停前已經有結果的一個書源（背景工作接著做，ADR 0058）：接著做時直接
/// 帶著這個結果，不再處理。
typedef RepairDone = ({RepairOutcome outcome, String detail, int tokens});

/// 整批修復裡的一個書源。
class RepairItem {
  RepairItem(this.source);

  /// 這個書源；修好存進去後換成存的那份（網址可能換了開頭）。
  BookSource source;

  RepairOutcome? outcome;

  /// 結果的一句說明：校驗的結論、網站的狀況或 AI 最後說的話。
  String? detail;

  /// 網站檢查的結果（同網站的書源共用一份）。
  SiteCheck? site;

  /// 交給 AI 修時的那段修復，看得到每一步。
  AiRepairSession? session;

  /// 這個書源用了多少 token。
  int tokens = 0;

  /// 重新校驗出來壞在哪；判斷修好了沒要用（[usableFix]）。
  SourceHealthCategory? before;

  /// 這一批剛重新校驗的完整結果，交給 AI 時沿用（沿用 24 小時內校驗的沒有）；
  /// 交出去就放掉。
  AiRepairPriorCheck? priorCheck;

  /// 套用了同網站哪一個 AI 修好的規則（[RepairOutcome.shared]）。
  RepairItem? sharedFrom;

  /// 網站不在了、已經刪掉了（[SourceRepairBatch.deleteGone]）。
  bool deleted = false;

  bool get isFinished => outcome != null;
}

/// 重新校驗時每完成一個書源就回報進度，不必等整批結束；[onResult] 收到
/// 每個書源的完整結果（含診斷），交給 AI 時沿用。
typedef BatchRecheck = Future<List<SourceCheckEntry>> Function(
  List<String> urls,
  void Function(int completed) onProgress,
  SourceCheckResultListener onResult,
);

/// 修復異常書源（ADR 0054）：一批書源先重新校驗、檢查網站，網站不在了的
/// 標「網站失效」，搬家的換網址；剩下的每個網站挑一個交給 AI，同時修
/// [aiConcurrency] 個，修好的規則再套到同網站的其他書源。每一步存進去的
/// 都是校驗通過的，留改前版本可以還原。做完之後可以刪掉網站不在了的
/// （[deleteGone]）；同網站的重複書源回到書源管理時自動併成一個（ADR 0062）。
class SourceRepairBatch extends ChangeNotifier {
  SourceRepairBatch({
    required List<BookSource> sources,
    required this.service,
    this.aiConcurrency = defaultAiConcurrency,
    this._recheck,
    this._checkSite,
    AiRepairChecker? check,
    Future<void> Function(BookSource repaired, BookSource original)? save,
    Future<void> Function(BookSource source, SiteCheck site)? markGone,
    Future<void> Function(BookSource source, String? reason)? markUnfixable,
    Future<void> Function(List<String> urls)? delete,
    AiRepairSession Function(BookSource source, RepairItem item)? session,
    DateTime Function()? now,
    Map<String, RepairDone> done = const {},
    Set<String> reused = const {},
    int? tokensUsed,
  }) : _reused = {...reused},
       items = [
         for (final source in sources)
           if (done[source.bookSourceUrl] case final result?)
             RepairItem(source)
               ..outcome = result.outcome
               ..detail = result.detail
               ..tokens = result.tokens
           else
             RepairItem(source),
       ],
       tokensUsed =
           tokensUsed ??
           done.values.fold(0, (sum, result) => sum + result.tokens),
       _now = now ?? DateTime.now,
       _check = check ?? _defaultCheck,
       _save = save ?? _defaultSave,
       _markGone = markGone ?? _defaultMarkGone,
       _markUnfixable = markUnfixable ?? markAiUnfixable,
       _delete = delete ?? _defaultDelete {
    _session = session ?? _defaultSession;
  }

  /// 沒指定時同時交給 AI 修幾個網站（[aiDefaultConcurrency]）。
  static const int defaultAiConcurrency = aiDefaultConcurrency;

  /// 同時交給 AI 修幾個網站：App 照 AI 服務頁的設定，實跑測試照
  /// `NR_AI_CONCURRENCY`。
  final int aiConcurrency;

  /// 同時檢查幾個網站。
  static const int siteConcurrency = 8;

  /// 這段時間內校驗過的書源沿用那次的結果，不重新校驗：剛按完「校驗所有
  /// 書源」、或修到一半停了再按一次時不重跑（ADR 0054）。
  static const Duration freshCheck = Duration(hours: 24);

  final AiService service;

  final List<RepairItem> items;
  final BatchRecheck? _recheck;
  final Future<SiteCheck> Function(BookSource source)? _checkSite;
  final AiRepairChecker _check;
  final Future<void> Function(BookSource repaired, BookSource original) _save;
  final Future<void> Function(BookSource source, SiteCheck site) _markGone;
  final Future<void> Function(BookSource source, String? reason) _markUnfixable;
  final Future<void> Function(List<String> urls) _delete;
  final DateTime Function() _now;
  late final AiRepairSession Function(BookSource source, RepairItem item)
  _session;

  RepairStage stage = RepairStage.checking;

  /// 這一段做完幾件、共幾件。
  int stageDone = 0;
  int stageTotal = 0;

  /// AI 一共用了多少 token。
  int tokensUsed;

  /// 沿用上次校驗結果、沒有重新校驗的書源（[freshCheck]），照網址；暫停後
  /// 接著做時同一個書源不重算。
  final Set<String> _reused;

  /// 沿用上次校驗結果的書源。
  Set<String> get reused => {..._reused};

  /// 沿用上次校驗結果、沒有重新校驗的書源數。
  int get reusedChecks => _reused.length;

  /// 做完之後刪了幾次書源：書源管理看到它變了就重讀清單。
  int sourceEdits = 0;

  bool _editing = false;

  /// 正在刪：按鈕先不能再按。
  bool get isEditing => _editing;

  final CancelToken _cancelToken = CancelToken();
  CheckSourceService? _activeRecheckService;
  Future<void>? _startTask;
  WorkPhase _phase = WorkPhase.ready;
  bool _disposed = false;
  final List<AiRepairSession> _sessions = [];

  /// 走到哪：還沒開始、做著、正在暫停、正在結束、已暫停（已經有結果的留著，
  /// 接著做時用同一批書源重開，有結果的不再處理，ADR 0058）、做完。
  WorkPhase get phase => _phase;
  bool get isRunning => _phase.active;

  /// 按了結束、還沒停好（正在暫停時按的也算：結束蓋過暫停）。
  bool get isStopped => _phase == WorkPhase.ending;

  bool get isPaused => _phase == WorkPhase.paused;

  /// 按了暫停或結束、還沒停好：做著的那一段看到就收手。
  bool get _halting => _phase.settling;

  bool get isFinished => stage == RepairStage.done;

  /// 已經有結果的書源經手的 AI 修復，照現在的網址：接著做時交給新的一批
  /// （[adoptSessions]），頁面照舊點得進去看每一步、整批紀錄照舊打包得到。
  /// 拿走的不跟著這一批放掉。
  Map<String, AiRepairSession> takeFinishedSessions() {
    final taken = <String, AiRepairSession>{};
    for (final item in items) {
      final session = item.session;
      if (session == null || !item.isFinished) continue;
      taken[item.source.bookSourceUrl] = session;
      _sessions.remove(session);
      session.removeListener(_notify);
    }
    return taken;
  }

  /// 接手上一批 [takeFinishedSessions] 交出的；對不上書源的傳回，由呼叫端放掉。
  List<AiRepairSession> adoptSessions(Map<String, AiRepairSession> sessions) {
    final left = {...sessions};
    for (final item in items) {
      if (!item.isFinished) continue;
      final session = left.remove(item.source.bookSourceUrl);
      if (session == null) continue;
      item.session = session;
      _sessions.add(session);
    }
    return left.values.toList();
  }

  /// 已經有結果的書源（照現在的網址）：暫停的存檔存它。
  Map<String, RepairDone> get done => {
    for (final item in items)
      if (item.outcome case final outcome?)
        item.source.bookSourceUrl: (
          outcome: outcome,
          detail: item.detail ?? '',
          tokens: item.tokens,
        ),
  };
  Future<void> get completion => _startTask ?? Future<void>.value();

  /// 未預期錯誤顯示在結果頁，避免把沒校驗的書源送去 AI。
  String? errorMessage;
  RepairStage? failedStage;

  /// 按「結束」時做到的那一步；它和後面的步驟沒做完。
  RepairStage? stoppedStage;

  int count(RepairOutcome outcome) =>
      items.where((item) => item.outcome == outcome).length;

  Future<void> start() {
    if (_startTask != null) return _startTask!;
    if (_phase != WorkPhase.ready || _disposed || isFinished) {
      return Future<void>.value();
    }
    return _startTask = _run();
  }

  Future<void> _run() async {
    _phase = WorkPhase.running;
    CrashTrail.action('開始修復異常書源（${items.length} 個）');
    _notify();
    try {
      await _recheckAll();
      if (!_halting) await _checkSites();
      if (!_halting) await _moveSites();
      if (!_halting) await _repairWithAi();
    } catch (error, stack) {
      AppLog.e('修復異常書源失敗', error: error, stackTrace: stack);
      if (!_halting) {
        errorMessage = '$error';
        failedStage = stage;
      }
    } finally {
      for (final item in items) {
        item.priorCheck = null;
      }
      if (_phase == WorkPhase.pausing) {
        // 暫停：沒結果的留著，接著做時再處理。
        _phase = WorkPhase.paused;
        CrashTrail.action('修復異常書源暫停了');
        _notify();
      } else {
        final ended = _phase == WorkPhase.ending;
        _closeUnfinished(ended ? '已結束' : errorMessage ?? '沒輪到');
        _phase = WorkPhase.finished;
        CrashTrail.action(ended ? '修復異常書源結束了' : '修復異常書源做完了');
        _notify();
      }
    }
  }

  void _closeUnfinished(String detail) {
    for (final item in items) {
      if (item.outcome == null) {
        item
          ..outcome = RepairOutcome.notTried
          ..detail = detail;
      }
    }
    stage = RepairStage.done;
  }

  /// 結束：做著的那一個 AI 修復停下、書源不改，還沒輪到的不做。暫停中的
  /// （或還沒開始接著做的）直接收尾。
  void stop() {
    if (isFinished) return;
    switch (_phase) {
      case WorkPhase.ending || WorkPhase.finished:
        return;
      case WorkPhase.running || WorkPhase.pausing:
        // 正在暫停時按結束：結束蓋過暫停，照做著時按結束的走。
        CrashTrail.action('按了結束：修復異常書源（做到${_stageName(stage)}）');
        _phase = WorkPhase.ending;
        stoppedStage = stage;
        _cancelAll('已結束', pause: false);
        _notify();
        return;
      case _:
        // 已暫停或還沒開始：直接收尾，暫停時停在半途的 AI 修復跟著結束，
        // 點進去看到的是已結束。
        _phase = WorkPhase.finished;
        stoppedStage = _startTask == null ? null : stage;
        // 先定好整批的結果再結束那幾件修復：它們結束時會通知整批，聽的人
        // 看到的已經是做完。
        _closeUnfinished('已結束');
        for (final session in _sessions) {
          session.stop();
        }
        _notify();
    }
  }

  /// 暫停：做著的 AI 修復與校驗停下、書源不改，已經有結果的留著。
  void pause() {
    if (_phase != WorkPhase.running || isFinished) return;
    CrashTrail.action('按了暫停：修復異常書源（做到${_stageName(stage)}）');
    _phase = WorkPhase.pausing;
    _cancelAll('已暫停', pause: true);
    _notify();
  }

  void _cancelAll(String why, {required bool pause}) {
    if (!_cancelToken.isCancelled) _cancelToken.cancel(why);
    _activeRecheckService?.cancel();
    for (final session in _sessions) {
      pause ? session.pause() : session.stop();
    }
  }

  static String _stageName(RepairStage stage) => switch (stage) {
    RepairStage.checking => '重新校驗',
    RepairStage.checkingSites => '檢查網站',
    RepairStage.moving => '換網址',
    RepairStage.repairing || RepairStage.sharing => 'AI 修',
    RepairStage.done => '做完',
  };

  // ── 1. 重新校驗 ────────────────────────────────────────────────────────

  /// 先分出不用重新校驗的：AI 試過修不好、網站不在了、需要登入這類本來
  /// 就不修的，照書源上的標記直接定案；[freshCheck] 內校驗過的沿用那次的
  /// 結果。剩下的才重新校驗（ADR 0054）。
  Future<void> _recheckAll() async {
    final now = _now().millisecondsSinceEpoch;
    final toCheck = <RepairItem>[];
    for (final item in items) {
      // 暫停前已經有結果的（接著做）不再處理。
      if (item.isFinished) continue;
      final source = item.source;
      final health = source.runtimeHealth;
      if (source.hasGroupTag(aiUnfixableSourceGroupTag)) {
        _finish(
          item,
          RepairOutcome.aiUnfixable,
          'AI 之前試過說修不好，這次跳過、不花用量。要再試，先清除這個書源的校驗標記。',
        );
      } else if (source.hasGroupTag(siteBrokenSourceGroupTag)) {
        _finish(
          item,
          RepairOutcome.siteGone,
          source.errorComment ?? health.description,
        );
      } else if (_notRepairable.contains(health.category)) {
        _finish(item, RepairOutcome.skipped, '${health.label}：不修');
      } else if (source.lastCheckTime > 0 &&
          now - source.lastCheckTime < freshCheck.inMilliseconds) {
        _reused.add(source.bookSourceUrl);
        _judge(item, health, source.errorComment ?? health.description);
      } else {
        toCheck.add(item);
      }
    }

    _enter(RepairStage.checking, toCheck.length);
    if (toCheck.isEmpty) return;
    void progress(int completed) {
      if (_halting || _disposed || stage != RepairStage.checking) return;
      final done = completed.clamp(0, toCheck.length);
      if (stageDone == done) return;
      stageDone = done;
      _notify();
    }

    final byUrl = {for (final item in toCheck) item.source.bookSourceUrl: item};
    void keep(String url, SourceCheckIsolateResult? result) {
      final item = byUrl[url];
      if (item == null) return;
      if (result != null) {
        // 校驗把結果寫回書源（標記，照正文改的類型，ADR 0051）：之後交給
        // AI 與存檔前的比對都照寫回去的那一份，不然自己改的類型會被當成
        // 修的期間別處改過，修好的規則存不進去。
        final checked = BookSource.fromJson(result.updatedSourceJson);
        item.source = CheckSourceService.withCheckMarks(
          BookSource.fromJson(item.source.toJson()),
          checked,
          typeChanged: checked.bookSourceType != item.source.bookSourceType,
        );
      }
      // 沒問題的不送 AI，不留。
      if (result?.isHealthy ?? false) return;
      item.priorCheck = (result: result);
    }

    final checked = await (_recheck ?? _recheckWithProgress)(
      [for (final item in toCheck) item.source.bookSourceUrl],
      progress,
      keep,
    );
    if (_halting) return;
    final entries = {for (final entry in checked) entry.sourceUrl: entry};
    for (final item in toCheck) {
      final entry = entries[item.source.bookSourceUrl];
      if (entry == null) {
        _finish(item, RepairOutcome.notTried, '校驗沒有取得結果，這次不修');
      } else if (entry.isHealthy) {
        item.before = entry.health.category;
        _finish(item, RepairOutcome.healthy, '重新校驗就沒問題了');
      } else {
        _judge(item, entry.health, entry.message);
      }
    }
    stageDone = toCheck.length;
    _notify();
  }

  /// 照校驗的結論決定這個書源送不送 AI；送的話 [RepairItem.detail] 是壞在
  /// 哪裡。
  void _judge(RepairItem item, SourceRuntimeHealth health, String message) {
    item.before = health.category;
    final source = item.source;
    if (health.category == SourceHealthCategory.healthy) {
      _finish(item, RepairOutcome.healthy, '校驗過了，沒問題');
    } else if (_notRepairable.contains(health.category)) {
      _finish(item, RepairOutcome.skipped, '${health.label}：不修');
    } else if ((source.searchUrl?.trim() ?? '').isEmpty &&
        (source.exploreUrl?.trim() ?? '').isNotEmpty &&
        health.category == SourceHealthCategory.searchBroken) {
      _finish(item, RepairOutcome.skipped, '沒有搜尋規則，本來就只能從發現頁找書');
    } else {
      item.detail = '${health.label}：$message';
    }
  }

  // ── 2. 檢查網站 ────────────────────────────────────────────────────────

  Future<void> _checkSites() async {
    final bySite = _pendingBySite();
    _enter(RepairStage.checkingSites, bySite.length);
    await _pool(bySite.entries.toList(), siteConcurrency, (entry) async {
      final source = entry.value.first.source;
      final checker = _checkSite;
      final site = checker == null
          ? await checkSite(source, cancelToken: _cancelToken)
          : await checker(source);
      if (_halting) return;
      for (final item in entry.value) {
        if (_halting) return;
        item.site = site;
        if (site.verdict == SiteVerdict.gone) {
          await _markGone(item.source, site);
          _finish(item, RepairOutcome.siteGone, site.detail);
        }
      }
    });
  }

  // ── 3. 搬家的網站換網址 ────────────────────────────────────────────────

  Future<void> _moveSites() async {
    final moving = [
      for (final item in _pending())
        if (item.site?.verdict == SiteVerdict.moved &&
            item.site?.movedTo != null)
          item,
    ];
    _enter(RepairStage.moving, moving.length);
    await _pool(moving, siteConcurrency, (item) async {
      if (_halting) return;
      final candidate = movedSource(item.source, item.site!.movedTo!);
      if (await _passes(item, candidate)) {
        _finish(item, RepairOutcome.moved, '換成 ${candidate.bookSourceUrl}');
      }
    });
  }

  // ── 4. AI 修，每個網站一個；5. 套用到同網站的其他書源 ──────────────────

  Future<void> _repairWithAi() async {
    final bySite = _pendingBySite().values.toList()
      ..sort((a, b) => _aiOrder(a.first).compareTo(_aiOrder(b.first)));
    _enter(RepairStage.repairing, bySite.length);
    await _pool(bySite, aiConcurrency, (group) async {
      if (_halting) return;
      final lead = group.first;
      final others = group.skip(1).toList();
      final session = _session(lead.source, lead);
      lead
        ..session = session
        ..priorCheck = null;
      for (final item in others) {
        item.priorCheck = null;
      }
      _sessions.add(session);
      session.addListener(_notify);
      await session.start();
      final job = session.job;
      final fixed = job.repairedSource;
      if (job.outcome == AiRepairOutcome.repaired && fixed != null) {
        // 先換成存進去的那份（網址可能換了開頭）再定案：定案時存的進度要是
        // 現在的網址。
        lead.source = fixed;
        _finish(lead, RepairOutcome.aiFixed, job.explanation ?? 'AI 修好了');
        await _share(lead, others, fixed);
      } else if (!_halting) {
        _finish(lead, RepairOutcome.notFixed, job.explanation ?? '沒修好');
        if (job.confirmedUnfixable) {
          await _markUnfixable(lead.source, job.giveUpWhy);
          for (final item in others) {
            if (_halting) return;
            _finish(
              item,
              RepairOutcome.notFixed,
              '同網站的「${lead.source.bookSourceName}」沒修好',
            );
            await _markUnfixable(item.source, job.giveUpWhy);
          }
        } else {
          for (final item in others) {
            _finish(item, RepairOutcome.notTried, '同網站的 AI 修復中斷，這次尚未嘗試');
          }
        }
      }
    });
  }

  /// [fixed] 的規則套到同網站的其他書源 [siblings]，各自校驗，通過才存。
  Future<void> _share(
    RepairItem lead,
    List<RepairItem> siblings,
    BookSource fixed,
  ) async {
    for (final item in siblings) {
      if (_halting) return;
      final candidate = sharedSource(item.source, fixed);
      if (await _passes(item, candidate)) {
        item.sharedFrom = lead;
        _finish(
          item,
          RepairOutcome.shared,
          '套用「${lead.source.bookSourceName}」修好的規則',
        );
      } else if (!_halting) {
        _finish(
          item,
          RepairOutcome.notFixed,
          '套用「${lead.source.bookSourceName}」修好的規則也沒過校驗，可以單獨修',
        );
      }
    }
  }

  /// 校驗 [candidate]，通過（或只剩原本就壞的發現頁）就存進去，傳回存了沒。
  ///
  /// 候選書源（換了網址、套用同網站修好的規則）還沒採用：校驗時規則存的
  /// 變數寫在它自己的一份草稿（[BaseSource.inDraftVariables]，同 AI 修書源），
  /// 存好了才寫回改過的，沒採用就丟掉。
  Future<bool> _passes(RepairItem item, BookSource candidate) async {
    if (_halting) return false;
    final draft = const Uuid().v4();
    try {
      // 抄到一半出錯時，已經抄進草稿的也在下面丟掉。
      final started = await BaseSource.startDraftVariables(
        draft,
        item.source.getKey(),
      );
      final checked = await BaseSource.inDraftVariables(
        draft,
        () => _check(candidate, _cancelToken),
      );
      if (_halting ||
          checked == null ||
          !usableFix(checked, item.source, candidate, before: item.before)) {
        return false;
      }
      final saved = BookSource.fromJson(checked.updatedSourceJson);
      try {
        await _save(saved, item.source);
      } catch (error) {
        item.detail = '$error';
        return false;
      }
      item.source = saved;
      // 寫不回去只記下來：書源已經存好了。
      try {
        await BaseSource.commitDraftVariables(
          draft,
          saved.getKey(),
          started: started,
        );
      } catch (error) {
        AppLog.w('修復異常書源的草稿變數沒寫回書源: $error');
      }
      return true;
    } finally {
      try {
        await BaseSource.discardDraftVariables(draft);
      } catch (error) {
        AppLog.w('修復異常書源的草稿變數沒丟掉: $error');
      }
    }
  }

  // ── 做完之後：使用者自行刪掉網站失效、不穩定的書源 ──────────────────

  /// 網站不在了、還沒刪的書源。
  List<RepairItem> get goneLeft => [
    for (final item in items)
      if (item.outcome == RepairOutcome.siteGone && !item.deleted) item,
  ];

  /// 網站不在了的書源全部刪掉（使用者 2026-11-13：不停用，直接刪）。修到
  /// 一半就刪的，之後才判定網站不在了的照樣列著、可以再刪。
  Future<void> deleteGone() async => _deleteItems(goneLeft);

  /// AI 已確認網站不穩定、無法修復的書源：列為可移除，不自動刪除。
  /// 同網站的其他書源也在 AI 放棄時一起標記。
  List<RepairItem> get unstableItems {
    final unstableSites = {
      for (final item in items)
        if (item.session?.job.giveUpWhy == 'site_unstable')
          siteKey(item.source),
    };
    return [
      for (final item in items)
        if ((item.outcome == RepairOutcome.notFixed ||
                item.outcome == RepairOutcome.aiUnfixable) &&
            (item.source.hasGroupTag(unstableSourceGroupTag) ||
                unstableSites.contains(siteKey(item.source))))
          item,
    ];
  }

  List<RepairItem> get unstableLeft => [
    for (final item in unstableItems)
      if (!item.deleted) item,
  ];

  Future<void> deleteUnstable() async => _deleteItems(unstableLeft);

  Future<void> _deleteItems(List<RepairItem> toDelete) async {
    if (toDelete.isEmpty || _editing) return;
    await _edit(() async {
      await _delete([for (final item in toDelete) item.source.bookSourceUrl]);
      for (final item in toDelete) {
        item.deleted = true;
      }
    });
  }

  Future<void> _edit(Future<void> Function() work) async {
    _editing = true;
    _notify();
    try {
      await work();
    } finally {
      _editing = false;
      sourceEdits++;
      _notify();
    }
  }

  // ── 工具 ──────────────────────────────────────────────────────────────

  Iterable<RepairItem> _pending() => items.where((item) => !item.isFinished);

  /// 還沒結果的書源照網站（書源網址的主機，[siteKey]）分組，照原本的順序。
  Map<String, List<RepairItem>> _pendingBySite() {
    final groups = <String, List<RepairItem>>{};
    for (final item in _pending()) {
      groups.putIfAbsent(siteKey(item.source), () => []).add(item);
    }
    return groups;
  }

  /// AI 先修網站正常的：連不上、被擋的修好的機會小一些。
  static int _aiOrder(RepairItem item) => switch (item.site?.verdict) {
    SiteVerdict.alive || null => 0,
    SiteVerdict.moved => 1,
    SiteVerdict.blocked => 2,
    SiteVerdict.unreachable => 3,
    SiteVerdict.gone => 4,
  };

  void _enter(RepairStage next, int total) {
    stage = next;
    stageDone = 0;
    stageTotal = total;
    _notify();
  }

  void _finish(RepairItem item, RepairOutcome outcome, String detail) {
    item
      ..outcome = outcome
      ..detail = detail
      ..priorCheck = null;
    _notify();
  }

  /// [count] 個工人輪流做 [work]；停下時還沒開始的不做。
  Future<void> _pool<T>(
    List<T> list,
    int count,
    Future<void> Function(T value) work,
  ) async {
    var next = 0;
    Future<void> worker() async {
      while (next < list.length && !_halting) {
        final value = list[next++];
        // 一件出錯只算那一件：其他工人照做，整批等全部做完才結束。
        try {
          await work(value);
        } catch (error, stack) {
          AppLog.e('修復異常書源有一件出錯', error: error, stackTrace: stack);
        } finally {
          stageDone++;
          _notify();
        }
      }
    }

    await Future.wait([for (var i = 0; i < count; i++) worker()]);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (_phase != WorkPhase.paused && _phase != WorkPhase.pausing) stop();
    _disposed = true;
    for (final session in _sessions) {
      session
        ..removeListener(_notify)
        ..dispose();
    }
    super.dispose();
  }

  static const Set<SourceHealthCategory> _notRepairable = {
    SourceHealthCategory.loginRequired,
    SourceHealthCategory.verificationRequired,
    SourceHealthCategory.downloadOnly,
    SourceHealthCategory.paid,
    SourceHealthCategory.nonNovel,
  };

  // ── 預設的實作 ────────────────────────────────────────────────────────

  /// 監看這次校驗的逐筆進度；只取消自己啟動的校驗，不干擾別的頁面。
  Future<List<SourceCheckEntry>> _recheckWithProgress(
    List<String> urls,
    void Function(int completed) onProgress,
    SourceCheckResultListener onResult,
  ) async {
    final checking = getIt<CheckSourceService>();
    if (checking.isChecking) {
      throw StateError('目前還有其他書源校驗正在執行，請等它結束後再修復');
    }
    _activeRecheckService = checking;
    void update() => onProgress(checking.currentCount);
    checking.addListener(update);
    try {
      return (await checking.check(urls, onResult: onResult)).entries;
    } finally {
      checking.removeListener(update);
      _activeRecheckService = null;
    }
  }

  static Future<SourceCheckIsolateResult?> _defaultCheck(
    BookSource source,
    CancelToken cancelToken,
  ) => AiRepairDefaults.check(source, cancelToken);

  static Future<void> _defaultSave(BookSource repaired, BookSource original) =>
      saveRepairedSource(repaired, original, backups: AiRepairBackups.instance);

  /// 網站不在了：標「網站失效」，原因寫進錯誤註解。
  static Future<void> _defaultMarkGone(BookSource source, SiteCheck site) =>
      markSiteGone(source, site.detail);

  static Future<void> _defaultDelete(List<String> urls) =>
      getIt<BookSourceDao>().deleteByUrls(urls);

  AiRepairSession _defaultSession(BookSource source, RepairItem item) =>
      AiRepairSession(
        source: source,
        service: service,
        priorCheck: item.priorCheck,
        onUsage: (usage) {
          final used = usage.prompt + usage.completion;
          item.tokens += used;
          tokensUsed += used;
          _notify();
        },
      );
}

/// AI 確認無法修復：標「AI 修不好」，下次整批修復跳過（ADR 0054）。
/// 網站不穩定時另外標狀態並列入建議清理，讓使用者自行選擇移除。
/// 這段時間已刪掉的書源不寫。
Future<void> markAiUnfixable(BookSource source, String? reason) async {
  final dao = getIt<BookSourceDao>();
  final current = await dao.getByUrl(source.bookSourceUrl);
  if (current == null) return;
  final unstable = reason == 'site_unstable';
  if (current.hasGroupTag(aiUnfixableSourceGroupTag) &&
      (!unstable || current.hasGroupTag(unstableSourceGroupTag))) {
    return;
  }
  if (unstable) {
    current
      ..removeInvalidGroups()
      ..removeErrorComment()
      ..addHealthGroups(upstreamHealth(unstableSourceGroupTag))
      ..addErrorComment('AI：網站不穩定，無法修復');
  }
  current.addGroup(aiUnfixableSourceGroupTag);
  await dao.upsert(current);
}

/// 網站不在了：書源標「網站失效」（ADR 0054），原因寫進錯誤註解；書源在這
/// 段時間被刪掉了就不寫。
Future<void> markSiteGone(BookSource source, String detail) async {
  final dao = getIt<BookSourceDao>();
  final current = await dao.getByUrl(source.bookSourceUrl);
  if (current == null) return;
  current
    ..removeInvalidGroups()
    ..removeErrorComment()
    ..addHealthGroups(upstreamHealth(siteBrokenSourceGroupTag))
    ..addErrorComment('網站: $detail');
  await dao.upsert(current);
}

/// 網站搬到 [movedTo]（`https://www.new.com`）：書源網址換開頭，規則裡寫死的
/// 舊網域也換成新的，規則改了就記下時間。名稱、分組與註解照舊。
BookSource movedSource(BookSource source, String movedTo) {
  final from = Uri.parse(siteOrigin(source.bookSourceUrl)!).host;
  final to = Uri.parse(movedTo).host;
  final fromSite = registrableDomain(from) ?? from;
  final toSite = registrableDomain(to) ?? to;
  final json = source.toJson();
  final keep = {
    for (final key in const [
      'bookSourceName',
      'bookSourceGroup',
      'bookSourceComment',
    ])
      key: json[key],
  };
  final moved = jsonDecode(
    _replaceDomain(
      _replaceDomain(jsonEncode(json), from, to),
      fromSite,
      toSite,
    ),
  ) as Map<String, dynamic>..addAll(keep);
  return BookSource.fromJson(moved)
    ..bookSourceUrl = siteMovedUrl(source.bookSourceUrl, movedTo)
    ..lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
}

/// [text] 裡完整的網域 [from] 換成 [to]：前後不能接著網域的字，`old.com`
/// 不會改到 `ebook.com` 或 `old.com.cn`。
String _replaceDomain(String text, String from, String to) => text.replaceAll(
  RegExp(
    '(?<![A-Za-z0-9-])${RegExp.escape(from)}(?![A-Za-z0-9-]|\\.[A-Za-z0-9])',
    caseSensitive: false,
  ),
  to,
);

/// [source] 套用同網站 [fixed] 的規則：規則、標頭、程式庫與類型照 [fixed]，
/// 網址開頭跟著 [fixed] 換；名稱、分組、網址後面的標記與使用者的設定照
/// [source]。
BookSource sharedSource(BookSource source, BookSource fixed) {
  final rules = sourceForAi(fixed)
    ..remove('bookSourceName')
    ..remove('bookSourceGroup')
    ..remove('bookSourceComment');
  return candidateFrom(source, {
    ...rules,
    'bookSourceUrl': siteOrigin(fixed.bookSourceUrl) ?? fixed.bookSourceUrl,
  });
}

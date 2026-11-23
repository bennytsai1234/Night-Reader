import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:night_reader/core/background_work/work_phase.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/diagnostics/app_log_service.dart';
import 'package:night_reader/core/diagnostics/crash_trail.dart';
import 'package:night_reader/core/source_check/source_check_isolate.dart';

import 'agent_loop.dart';
import 'ai_chat_client.dart';
import 'ai_repair_apply.dart';
import 'ai_create_prompt.dart';
import 'ai_repair_backups.dart';
import 'ai_repair_defaults.dart';
import 'ai_repair_log.dart';
import 'ai_repair_prompt.dart';
import 'ai_repair_secrets.dart';
import 'ai_repair_settings.dart';
import 'ai_repair_step.dart';
import 'repair_pages.dart';
import 'repair_agent.dart';
import 'repair_rule_tools.dart';
import 'repair_verdict.dart';
import 'opening_facts.dart';
import 'site_check.dart';
import 'source_probe.dart';

/// 一個書源修完的結果。
enum AiRepairOutcome { repaired, failed }

/// 一個書源的修復：做過的步驟與結果。
class AiRepairJob {
  AiRepairJob(this.original, {this.create});

  /// 修的書源；從空白建立時是只有網址開頭的空白書源（[aiCreateBlankSource]）。
  final BookSource original;

  /// 從空白建立書源時使用者貼的網址與樣本書名；修書源是 null。
  final AiCreateRequest? create;
  final List<AiRepairStep> steps = [];
  AiRepairOutcome? outcome;

  /// 結果的說明：AI 最後說的話，或卡在哪。
  String? explanation;

  /// AI 明確放棄時才標「AI 修不好」；網路、金鑰、系統錯誤、校驗超過時間與
  /// 按暫停、結束都不標。
  bool confirmedUnfixable = false;

  /// AI 放棄時選的原因（[aiGiveUpLabels] 的 key）。
  String? giveUpWhy;

  /// 剪貼簿：已複製給 AI，等使用者貼回修好的書源。
  bool awaitingPaste = false;

  /// 修好之後又還原了。
  bool restored = false;

  /// 修好存進去的那份：AI 換了網址開頭時網址和原本的不同。
  BookSource? repairedSource;

  /// 修好存進去時的網址。
  String? get repairedUrl => repairedSource?.bookSourceUrl;

  /// 給 AI 與剪貼簿用的現況：原本的校驗結果與試抓。
  String? _checkResult;

  /// 原本的書源校驗出來壞在哪；校驗逾時是 null。
  SourceHealthCategory? _before;

  /// 原本的書源校驗時網站沒回內容：這次開場或上一次的校驗是「上游異常」
  /// （連不上、回錯誤）或「校驗超時」的那個標記，其他是 null。AI 沒改規則、
  /// 再校驗就通過時，網站是時好時壞（[AiRepairSession._validate]，使用者
  /// 2026-11-16）。
  String? _beforeUnreachable;

  /// 開場的試抓抓到的原樣；標上頁碼、給 AI 的那份在 [RepairAgent]，整件
  /// 重跑時照這份重新標頁碼。
  SourceProbeReport? _firstProbe;

  /// 這個書源的登入資料、Cookie 與變數的值，送出前遮掉（[aiRepairSecretsOf]）。
  Set<String> _secrets = const {};

  /// 問了 AI 幾輪，跨重跑接著數。
  int _rounds = 0;

  /// 開始存修好的書源了：這時按暫停或結束也停不下來，結果照存的結果。
  bool _committing = false;
}

/// 一次校驗的結果；逾時是 null（同書源校驗，ADR 0051）。
typedef AiRepairChecker = Future<SourceCheckIsolateResult?> Function(
  BookSource source,
  CancelToken cancelToken,
);

/// 一次試抓（[probeSource]）：[start] 是 null 時用校驗的關鍵字從搜尋開始，
/// 不然照書源除錯的寫法從那一段開始（[probeStart]）。
typedef AiRepairProber = Future<SourceProbeReport> Function(
  BookSource source,
  CancelToken cancelToken, {
  String? start,
});

/// 把已經抓到的一頁當成某一段解析（[parseRepairPage]）。
typedef AiRepairPageParser = Future<String> Function(
  BookSource source,
  String stage,
  RepairPage page,
  CancelToken cancelToken,
);

/// 在書源規則 JS 的環境跑一段程式（[runRepairJs]）；[pages] 是程式用到的
/// 頁碼與原文。
typedef AiRepairJsRunner = Future<String> Function(
  BookSource source,
  String code,
  Map<int, String> pages,
  CancelToken cancelToken,
);

/// AI 要看的一頁（[fetchPageForAi]）。
typedef AiRepairFetcher = Future<AiPage> Function(
  BookSource source,
  String url,
  CancelToken cancelToken,
);

/// 問 AI 一次（測試用的假 AI）；真的服務用 [AiChatClient]，帶著
/// [aiRepairTools]。
typedef AiRepairAsker = AgentAsk;

/// 檢查一個網站（[checkSite]）。
typedef AiSiteChecker = Future<SiteCheck> Function(
  BookSource source,
  CancelToken cancelToken,
);

/// 整批修復剛校驗過原本的書源：修復頁沿用，不再校驗一次；`result` 是 null
/// 表示那次校驗逾時。
typedef AiRepairPriorCheck = ({SourceCheckIsolateResult? result});

/// AI 修一個書源（ADR 0054）：先校驗（整批修復剛校驗過的沿用 [priorCheck]）、
/// 抓網頁；有 AI 服務時讓 AI 邊看網頁邊
/// 改、試抓，交出後再校驗，通過才存進去並留下改前版本。沒有 AI 服務時把
/// 提示詞複製下來，等使用者貼回 AI 修好的書源（[submitPaste]）。一批書源
/// 由整批修復（[SourceRepairBatch]）每個網站開一個。
class AiRepairSession extends ChangeNotifier {
  AiRepairSession({
    required BookSource source,
    required this.service,
    AiRepairChecker? check,
    AiRepairProber? probe,
    AiRepairAsker? ask,
    AiRepairFetcher? fetchPage,
    AiRepairPageParser? parsePage,
    AiRepairJsRunner? runJs,
    Future<void> Function(BookSource repaired, BookSource original)? apply,
    Future<void> Function(String text)? copy,
    AiRepairBackups? backups,
    Future<Set<String>> Function(BookSource source)? secrets,
    this.recheckDelay = const Duration(seconds: 30),
    this._priorCheck,
    void Function(AiUsage usage)? onUsage,
    Future<Directory> Function()? logDirectory,
    AiCreateRequest? create,
    AiSiteChecker? siteCheck,
  }) : job = AiRepairJob(source, create: create),
       log = AiRepairLog(
         sourceName: source.bookSourceName,
         sourceUrl: source.bookSourceUrl,
         directory: logDirectory,
       ),
       _check = check ?? AiRepairDefaults.check,
       _probe = probe ?? AiRepairDefaults.probe,
       _fetchPage = fetchPage ?? AiRepairDefaults.fetchPage,
       _parsePage = parsePage ?? AiRepairDefaults.parsePage,
       _runJs = runJs ?? AiRepairDefaults.runJs,
       _copy = copy ?? AiRepairDefaults.copy,
       _secretsOf = secrets ?? aiRepairSecretsOf,
       _siteCheck =
           siteCheck ??
           ((source, cancelToken) =>
               checkSite(source, cancelToken: cancelToken)),
       _backups = backups ?? AiRepairBackups.instance {
    _apply =
        apply ??
        (create != null
            ? (created, _) => saveCreatedSource(created, create.url)
            : (repaired, original) =>
                  saveRepairedSource(repaired, original, backups: _backups));
    _onUsage = onUsage;
    _ask = ask ?? (service == null ? null : AiRepairDefaults.ask(service!));
  }

  void Function(AiUsage usage)? _onUsage;

  /// 試抓成功、校驗沒過時，隔多久再校驗一次。
  final Duration recheckDelay;

  /// 整批修復剛做的校驗；null 時修復頁自己校驗原本的書源。開場用完就放掉
  /// （帶著整份診斷與書源 JSON）。
  AiRepairPriorCheck? _priorCheck;

  /// 使用者的 AI 服務；null 時用剪貼簿。
  final AiService? service;
  final AiRepairJob job;
  final AiRepairChecker _check;
  final AiRepairProber _probe;
  final AiRepairFetcher _fetchPage;
  final AiRepairPageParser _parsePage;
  final AiRepairJsRunner _runJs;
  late final AgentAsk? _ask;

  /// 這次修復抓到的網頁，AI 用頁碼指（[RepairPages]）；修完就丟。
  final RepairPages _pages = RepairPages();
  final Future<void> Function(String text) _copy;
  final Future<Set<String>> Function(BookSource source) _secretsOf;
  final AiSiteChecker _siteCheck;
  final AiRepairBackups _backups;
  late final Future<void> Function(BookSource repaired, BookSource original)
  _apply;

  final CancelToken _cancelToken = CancelToken();

  /// 這次修復的紀錄：「複製摘要」與「分享完整紀錄」（[AiRepairLog]）。
  final AiRepairLog log;

  /// 這次修復的統計（輪數、用量、時間），跑完 AI 才有。
  AgentStats? _stats;

  /// 這次修復問 AI 的統計；沒問過 AI（剪貼簿、還沒跑到）是 null。
  AgentStats? get stats => _stats;
  Future<void>? _startTask;
  Completer<void>? _pasteCompletion;
  WorkPhase _phase = WorkPhase.ready;
  bool _disposed = false;

  bool get usesClipboard => service == null;

  /// 走到哪：還沒開始、做著、正在暫停、正在結束、已暫停（停下、書源不改，
  /// 不算結束；接著做是這個書源從頭重修，ADR 0058）、等貼回（剪貼簿）、做完
  /// （含結束）。
  WorkPhase get phase => _phase;
  bool get isRunning => _phase.active;

  /// 按了結束、還沒停好（正在暫停時按的也算：結束蓋過暫停）。
  bool get isStopped => _phase == WorkPhase.ending;

  bool get isPaused => _phase == WorkPhase.paused;

  /// 做完（或結束）。剪貼簿等使用者貼回時不算。
  bool get isFinished => _phase == WorkPhase.finished;

  /// 按了暫停或結束、還沒停好：做著的那一步看到就收手。
  bool get _halting => _phase.settling;

  /// 一段跑完（[_run] 或貼回的校驗）：照結果與按了什麼定下一個階段。暫停時
  /// 正好在存修好的書源：存完就算做完，不再是暫停。
  void _settle() {
    _phase = switch (_phase) {
      _ when job.outcome != null => WorkPhase.finished,
      WorkPhase.pausing => WorkPhase.paused,
      WorkPhase.ending => WorkPhase.finished,
      _ => job.awaitingPaste ? WorkPhase.waiting : WorkPhase.finished,
    };
  }

  Future<void> get completion =>
      _pasteCompletion?.future ?? _startTask ?? Future<void>.value();

  /// 有紀錄可以複製、分享。
  bool get hasLog => !log.isEmpty;

  Future<void> start() {
    if (_startTask != null) return _startTask!;
    if (_phase != WorkPhase.ready || _disposed || job.outcome != null) {
      return Future<void>.value();
    }
    return _startTask = _run();
  }

  Future<void> _run() async {
    _phase = WorkPhase.running;
    CrashTrail.action('開始 AI 修復：${job.original.bookSourceName}');
    _notify();
    try {
      await _repair(job);
    } catch (error, stack) {
      // 校驗、試抓或存檔丟出沒料到的錯：記成沒修好，做著的步驟標失敗，
      // 不讓畫面停在轉圈。
      AppLog.e('AI 修書源出錯', error: error, stackTrace: stack);
      if (job.outcome == null && !_halting) {
        for (final step in job.steps) {
          if (step.state == AiRepairStepState.running) {
            step
              ..state = AiRepairStepState.failed
              ..detail = '出錯';
          }
        }
        _fail(job, '修復出錯，書源沒有改：$error');
      }
    } finally {
      final ended = _phase == WorkPhase.ending;
      _settle();
      // 抓到的網頁只給這次的 AI 用；整批修復一次開幾十段，不留在記憶體。
      // 開場試抓的報告也帶著整頁原文：做完了（等貼回書源的不算）一起放掉。
      _pages.clear();
      if (job.outcome != null) {
        log.finish();
        job._firstProbe = null;
        // 迴圈到了未收斂的門檻直接結束，那一輪的步驟還是執行中：標成沒做完，
        // 畫面不停在轉圈。
        for (final step in job.steps) {
          if (step.state == AiRepairStepState.running) {
            step
              ..state = AiRepairStepState.failed
              ..detail = step.detail ?? '沒有做完';
          }
        }
      }
      CrashTrail.action(
        'AI 修復${_phase == WorkPhase.paused
            ? '暫停了'
            : ended
            ? '結束了'
            : '做完了'}：${job.original.bookSourceName}',
      );
      _notify();
    }
  }

  /// 結束：做著的那一步標成結束，修到一半的不改。暫停中的直接收尾。
  void stop() {
    if (job.outcome != null) return;
    switch (_phase) {
      case WorkPhase.paused:
        _phase = WorkPhase.finished;
        _endSteps();
        _notify();
        return;
      case WorkPhase.ending || WorkPhase.finished:
        return;
      case WorkPhase.running || WorkPhase.pausing:
        // 正在暫停時按結束：結束蓋過暫停，照做著時按結束的走。
        _phase = WorkPhase.ending;
      case _:
        _phase = WorkPhase.finished;
    }
    CrashTrail.action('按了結束：AI 修復 ${job.original.bookSourceName}');
    if (!_cancelToken.isCancelled) _cancelToken.cancel('已結束');
    if (!job._committing) _endSteps();
    _notify();
  }

  void _endSteps() {
    for (final step in job.steps) {
      if (step.state == AiRepairStepState.running) {
        step
          ..state = AiRepairStepState.failed
          ..detail = '已結束';
      }
    }
    if (job.steps.isNotEmpty && job.outcome == null) {
      job
        ..awaitingPaste = false
        ..outcome = AiRepairOutcome.failed
        ..explanation = '已結束，書源沒有改。';
      _logOutcome('已結束，書源沒有改。');
    }
  }

  /// 暫停：做著的那一步停下、書源不改，結果不寫（背景工作接著做，ADR 0058）。
  /// 正在存修好的書源時停不下來，存完就算做完。剪貼簿的修復不暫停。
  void pause() {
    if (job.outcome != null || usesClipboard) return;
    switch (_phase) {
      case WorkPhase.running:
        _phase = WorkPhase.pausing;
      case WorkPhase.ready:
        // 還沒輪到就暫停（整批暫停時）：直接停好。
        _phase = WorkPhase.paused;
      case _:
        return;
    }
    CrashTrail.action('按了暫停：AI 修復 ${job.original.bookSourceName}');
    if (!_cancelToken.isCancelled) _cancelToken.cancel('已暫停');
    if (!job._committing) {
      for (final step in job.steps) {
        if (step.state == AiRepairStepState.running) {
          step
            ..state = AiRepairStepState.failed
            ..detail = '已暫停';
        }
      }
    }
    _notify();
  }

  /// 剪貼簿：使用者貼回 AI 修好的書源。讀不出書源時傳回原因、什麼都不做。
  Future<String?> submitPaste(String text) async {
    if (!job.awaitingPaste || _phase != WorkPhase.waiting || _disposed) {
      return null;
    }
    if (text.length > aiRepairMaxReplyLength) return '貼回的內容太長';
    final json = pastedSourceJson(text);
    final candidate = json == null
        ? null
        : candidateOrNull(job.original, json, creating: job.create != null);
    if (candidate == null) return '讀不出書源 JSON';
    job.awaitingPaste = false;
    final pending = Completer<void>();
    _pasteCompletion = pending;
    _phase = WorkPhase.running;
    _notify();
    try {
      log
        ..section('貼回的書源')
        ..both(text);
      await _validate(job, candidate, '');
    } catch (error, stack) {
      AppLog.e('AI 貼回書源出錯', error: error, stackTrace: stack);
      if (!_halting) {
        _fail(job, '校驗貼回的書源出錯，書源沒有改：$error');
      }
    } finally {
      _settle();
      _notify();
      pending.complete();
      if (identical(_pasteCompletion, pending)) _pasteCompletion = null;
    }
    return null;
  }

  /// 修好之後還原成改前的版本。
  /// 傳回真的還原了沒：書源在這段時間被刪掉了就沒有。
  Future<bool> restore() async {
    if (job.outcome != AiRepairOutcome.repaired || job.restored) return false;
    final restored = await restoreAiRepair(
      job.repairedUrl ?? job.original.bookSourceUrl,
      backups: _backups,
    );
    job.restored = restored;
    _notify();
    return restored;
  }

  Future<void> _repair(AiRepairJob job) async {
    final original = job.original;
    await _refreshSecrets(job);
    log
      ..redact = ((text) => _redact(job, text))
      ..header(_serviceText, prompt: _promptVersion);
    if (_halting) return;
    if (job.create case final request?) return _create(job, request);

    final checkStep = _addStep(job, aiRepairCheckStage);
    log.section(aiRepairCheckStage);
    final checkWatch = Stopwatch()..start();
    final prior = _priorCheck;
    _priorCheck = null;
    final checked = prior != null
        ? prior.result
        : await _guard(() => _check(original, _cancelToken));
    if (_halting) return;
    final checkText = _checkText(checked);
    final before = checked == null
        ? null
        : BookSource.fromJson(checked.updatedSourceJson).runtimeHealth;
    String? unreachable(String? label) =>
        const {
          upstreamBlockedSourceGroupTag,
          timeoutSourceGroupTag,
        }.contains(label)
        ? label
        : null;
    // 這次開場的校驗，或送來修的原因（書源上留著的上一次校驗的結論）：
    // 整批沿用一天內校驗過的書源時，開場重校驗可能已經過了。開場校驗整個
    // 超過時間也算校驗超時。
    job
      .._before = before?.category
      .._beforeUnreachable = checked == null
          ? timeoutSourceGroupTag
          : unreachable(before?.label) ??
                unreachable(original.runtimeHealth.label);
    job._checkResult = [checkText, ...?checked?.diagnostics].join('\n\n');
    _finish(checkStep, prior == null ? checkText : '沿用剛才的校驗：$checkText');
    log
      ..both(
        prior == null
            ? '${AiRepairLog.seconds(checkWatch)}：$checkText'
            : '沿用整批修復剛才的校驗：$checkText',
      )
      ..both([...?checked?.diagnostics].join('\n\n'));

    final fetchStep = _addStep(job, aiRepairFetchStage);
    log.section(aiRepairFetchStage);
    final probeWatch = Stopwatch()..start();
    final probe = await _guard(() => _probe(original, _cancelToken));
    if (_halting || probe == null) return;
    job._firstProbe = probe;
    final numbered = withPageIds(_pages, probe);
    _finish(fetchStep, _fetchText(probe));
    _logProbe('${AiRepairLog.seconds(probeWatch)}：${_fetchText(probe)}', probe);

    // 程式讀得到、AI 要好幾輪才推得出來的事實，寫進開場。
    for (final fact in openingFacts(original, probe)) {
      job._checkResult = '${job._checkResult}\n\n$fact';
      log.both(fact);
    }

    if (usesClipboard) {
      final prompt = _redact(
        job,
        aiRepairClipboardPrompt(
          source: original,
          checkResult: job._checkResult!,
          probe: probe.withoutPages,
        ),
      );
      log
        ..section('複製給 AI')
        ..note('${prompt.length} 字，全文見完整紀錄')
        ..full(prompt);
      await _copy(prompt);
      _finish(_addStep(job, '已複製給 AI'), null);
      job.awaitingPaste = true;
      _notify();
      return;
    }
    await _converse(job, numbered);
  }

  /// 從空白建立書源：檢查網站、抓使用者貼的那一頁，交給 AI 從空白寫。網站
  /// 不在了就不問 AI。
  Future<void> _create(AiRepairJob job, AiCreateRequest request) async {
    final siteStep = _addStep(job, aiCreateSiteStage);
    log.section(aiCreateSiteStage);
    final site = await _guard(() => _siteCheck(job.original, _cancelToken));
    if (_halting || site == null) return;
    final siteText = '${_siteVerdictLabel(site.verdict)}：${site.detail}';
    final gone = site.verdict == SiteVerdict.gone;
    _finish(siteStep, siteText, failed: gone);
    log.both(siteText);
    if (gone) {
      _fail(job, '網站失效：${site.detail}');
      return;
    }
    job._checkResult = siteText;

    final fetchStep = _addStep(job, aiCreateFetchStage);
    log.section(aiCreateFetchStage);
    final watch = Stopwatch()..start();
    final page = await _guard(
      () => _fetchPage(job.original, request.url, _cancelToken),
    );
    if (_halting || page == null) return;
    final probe = SourceProbeReport(
      logs: const [],
      requests: page.lines,
      pages: page.pages,
    );
    job._firstProbe = probe;
    final numbered = withPageIds(_pages, probe);
    _finish(fetchStep, request.url);
    _logProbe('${AiRepairLog.seconds(watch)}：${request.url}', probe);
    if (usesClipboard) {
      _fail(job, '還沒設定 AI 服務');
      return;
    }
    await _converse(job, numbered);
  }

  static String _siteVerdictLabel(SiteVerdict verdict) => switch (verdict) {
    SiteVerdict.alive => '網站在',
    SiteVerdict.gone => '網站失效',
    SiteVerdict.unreachable => '首頁連不上',
    SiteVerdict.moved => '首頁轉到別的網域',
    SiteVerdict.blocked => '首頁要驗證才放行',
  };

  String get _promptVersion =>
      job.create == null ? aiRepairPromptVersion : aiCreatePromptVersion;

  /// 和 AI 來回（ADR 0054）：交給和任務無關的迴圈（[runAgent]），書源修復
  /// 的開場、指令與驗收在 [RepairAgent]。對話照原樣一路接下去，前面的內容
  /// 不改寫：AI 要靠前面看過的網頁推下一步，開頭不變也讓服務的快取打得中。
  /// 卡住、失控、沒收斂時整件換新對話重跑，次數照 [AiAgentKnobs]。
  Future<void> _converse(AiRepairJob job, SourceProbeReport probe) async {
    final agent = RepairAgent(
      _AgentHost(this, job),
      job,
      log: log,
      pages: _pages,
      prober: _probe,
      fetchPage: _fetchPage,
      parsePage: _parsePage,
      runJs: _runJs,
      onUsage: _onUsage,
      checkResult: job._checkResult!,
      firstProbe: job._firstProbe!,
      openingProbe: probe,
    );
    log.full('（迴圈的設定：${AiAgentKnobs.summary}）');
    log.tools(
      const JsonEncoder.withIndent('  ').convert(aiToolsJson(aiRepairTools)),
    );
    final end = await runAgent(agent, ask: _ask!, cancelToken: _cancelToken);
    _stats = end.stats;
    if (_halting || job.outcome != null) {
      _logStats(end);
      return;
    }
    switch (end.kind) {
      case AgentEndKind.completed || AgentEndKind.cancelled:
        break;
      case AgentEndKind.unconfirmed:
        _fail(job, '沒有修完，書源沒有改：${end.reason}。');
      case AgentEndKind.failed:
        _fail(
          job,
          end.reason == '整批的 AI 用量到了上限'
              ? '整批的 AI 用量到了上限，沒修完，書源沒有改。'
              : end.reason,
        );
    }
    _logStats(end);
  }

  /// 這一件的統計寫進紀錄最後；完整紀錄另寫一行 JSON 給評估表
  /// （`tool/ai_repair_table.dart`）。
  void _logStats(AgentEnd end) {
    final stats = end.stats;
    String time(Duration value) =>
        '${(value.inMilliseconds / 1000).toStringAsFixed(1)} 秒';
    log
      ..section('統計')
      ..both(
        '${_endLabel(end.kind)}：${end.reason}；跑了 ${stats.attempts} 次、'
        '${stats.rounds} 輪、${stats.toolCalls} 個指令（交出被退 '
        '${stats.rejections} 次、讀不懂 ${stats.badCommands} 次、沒有指令 '
        '${stats.noCommands} 次、卡住 ${stats.stalls} 次）；時間：等 AI '
        '${time(stats.model)}、跑工具 ${time(stats.tools)}、其他 '
        '${time(stats.other)}',
      );
    if (stats.restarts.isNotEmpty) {
      log.both('重跑的原因：${stats.restarts.join('；')}');
    }
    final row = {
      'source': job.original.bookSourceName,
      'url': job.original.bookSourceUrl,
      'end': end.kind.name,
      'reason': end.reason,
      'outcome': job.outcome?.name,
      'unfixable': job.confirmedUnfixable,
      'why': job.giveUpWhy,
      'promptVersion': _promptVersion,
      ...stats.toMap(),
    };
    log.full('$aiRepairStatsMarker${jsonEncode(row)}');
  }

  static String _endLabel(AgentEndKind kind) => switch (kind) {
    AgentEndKind.completed => '完成',
    AgentEndKind.unconfirmed => '無法確認',
    AgentEndKind.cancelled => '取消',
    AgentEndKind.failed => '停下',
  };

  /// 校驗 AI 交出（或貼回）的書源，通過才存進去。
  ///
  /// 試抓一路抓到了正文、校驗卻沒過時（網站限流、偶爾回慢），隔
  /// [recheckDelay] 再校驗一次。
  ///
  /// 沒通過時傳回要回給 AI 的校驗結果，讓它接著改；[last]（貼回的書源，沒有
  /// AI 可以接著改）就記成沒修好，傳回 null。修好、存不進去或停下時是 null。
  Future<String?> _validate(
    AiRepairJob job,
    BookSource candidate,
    String note, {
    bool probeSucceeded = false,
    bool last = true,
  }) async {
    final stage = job.create == null
        ? aiRepairVerifyStage
        : aiCreateVerifyStage;
    final step = _addStep(job, stage);
    log.section(stage);
    final checkWatch = Stopwatch()..start();
    var checked = await _guard(() => _check(candidate, _cancelToken));
    if (_halting) return null;
    bool usable(SourceCheckIsolateResult? result) =>
        usableFix(result, job.original, candidate, before: job._before);
    if (probeSucceeded && !usable(checked)) {
      step.detail = '${_checkText(checked)}；稍後再校驗一次…';
      log
        ..both(
          '${AiRepairLog.seconds(checkWatch)}：${_checkText(checked)}，'
          '${recheckDelay.inSeconds} 秒後再校驗一次',
        )
        ..full([...?checked?.diagnostics].join('\n\n'));
      _notify();
      await Future.any<Object?>([
        Future<void>.delayed(recheckDelay),
        _cancelToken.whenCancel,
      ]);
      if (_halting) return null;
      checkWatch.reset();
      checked = await _guard<SourceCheckIsolateResult?>(
        () => _check(candidate, _cancelToken),
      );
      if (_halting) return null;
    }
    final checkText = _checkText(checked);
    log.both('${AiRepairLog.seconds(checkWatch)}：$checkText');
    if (checked != null && !usable(checked)) {
      log.both(checked.diagnostics.join('\n\n'));
    }
    if (checked == null || !usable(checked)) {
      _finish(step, checkText, failed: true);
      if (!last) {
        final discovery = discoveryNote(checked, job.original, candidate);
        return aiRepairCheckReply(checkText, [
          ?discovery,
          ...?checked?.diagnostics,
        ]);
      }
      _fail(job, ['校驗：$checkText', if (note.isNotEmpty) 'AI：$note'].join('\n'));
      return null;
    }
    // 網站時好時壞：原本校驗時沒回內容，規則沒改再校驗就過了。偶爾通過不算
    // 能用（網站不穩定＝修不好，使用者 2026-11-16），不存回去當成沒問題。
    if (job._beforeUnreachable case final before?
        when job.create == null &&
            changedParts(job.original, candidate).isEmpty) {
      _finish(step, checkText);
      job
        ..confirmedUnfixable = true
        ..giveUpWhy = 'site_unstable';
      _fail(
        job,
        'AI：${aiGiveUpLabels['site_unstable']}。原本的校驗是「$before」，'
        '規則沒改再校驗就通過，網站時好時壞',
      );
      return null;
    }
    job._committing = true;
    final saved = BookSource.fromJson(checked.updatedSourceJson);
    try {
      await _apply(saved, job.original);
    } on AiRepairConflict catch (error) {
      _finish(step, error.message, failed: true);
      _fail(job, error.message);
      return null;
    } catch (error, stack) {
      AppLog.e('存 AI 修好的書源失敗', error: error, stackTrace: stack);
      _finish(step, '存不進去', failed: true);
      _fail(job, '校驗通過了，但存不進去：$error');
      return null;
    } finally {
      job._committing = false;
    }
    _finish(step, checkText);
    // 交出的規則和原本一樣（2026-11-13 品书楼：AI 查過每一段都沒問題）：照樣
    // 存回去拿掉舊的標記，但不說修好了。
    final unchanged =
        job.create == null && changedParts(job.original, candidate).isEmpty;
    final result = job.create != null
        ? '建立好了，已加入書源'
        : unchanged
        ? 'AI 查過，沒有要改的規則；重新校驗沒有問題'
        : '修好了，已套用';
    final explanation = [
      if (unchanged) 'AI 查過，沒有要改的規則',
      if (note.isNotEmpty) 'AI：$note',
    ].join('\n');
    job
      ..outcome = AiRepairOutcome.repaired
      ..repairedSource = saved
      ..explanation = explanation.isEmpty ? null : explanation;
    _logOutcome('$result${note.isEmpty ? '' : '\nAI：$note'}');
    _notify();
    return null;
  }

  /// 送給 AI、寫進紀錄的文字都經過這裡：開始時讀到的秘密、修復途中重讀
  /// 的（[_refreshSecrets]），加上記憶體裡現在的 Cookie 值。
  String _redact(AiRepairJob job, String text) => redactAiRepairSecrets(text, {
    ...job._secrets,
    ...aiRepairLiveCookieSecrets({job.original.getKey(), ?job.repairedUrl}),
  });

  /// 重讀這個書源的秘密，併進已知的：修復途中規則可能寫了新的 Cookie、登入
  /// 標頭或書源變數，舊的也照樣遮（ADR 0054）。AI 服務的金鑰也算。
  Future<void> _refreshSecrets(AiRepairJob job) async {
    job._secrets = {
      ...job._secrets,
      ...await _secretsOf(job.original),
      if (service?.apiKey case final key? when key.length >= 6) key,
    };
  }

  /// 一次試抓寫進紀錄：[title] 一句結果、除錯紀錄與送出的請求；完整紀錄
  /// 另外寫每個回應的整頁原文。
  void _logProbe(String title, SourceProbeReport probe) {
    log.both(title);
    if (probe.logs.isNotEmpty) {
      log.both(probe.logs.map((entry) => entry.$2).join('\n'));
    }
    log.requests(probe.requests, pages: probe.pages);
  }

  /// 結果與這次的用量，寫在紀錄最後。
  void _logOutcome(String result) {
    log
      ..section('結果')
      ..both(result);
    if (job._rounds == 0) return;
    final stats = _stats;
    final usage = stats == null || stats.prompt + stats.completion == 0
        ? ''
        : '；用量：送出 ${_tokens(stats.prompt)} token（打中快取 '
              '${_tokens(stats.cached)}）、回覆 ${_tokens(stats.completion)}'
              '（思考 ${_tokens(stats.reasoning)}）';
    log.both('問了 AI ${job._rounds} 輪$usage');
  }

  String get _serviceText {
    final service = this.service;
    if (service == null) return '沒有 AI 服務，用剪貼簿';
    final host = Uri.tryParse(service.baseUrl)?.host ?? service.baseUrl;
    return 'AI：$host · ${service.model}'
        '${service.effort.isEmpty ? '' : '（思考程度 ${service.effort}）'}';
  }

  static String _tokens(int count) =>
      NumberFormat.decimalPattern().format(count);

  AiRepairStep _addStep(
    AiRepairJob job,
    String title, {
    String? detail,
    AiRepairStepKind kind = AiRepairStepKind.stage,
  }) {
    final step = AiRepairStep(title, detail: detail, kind: kind);
    job.steps.add(step);
    _notify();
    return step;
  }

  void _finish(AiRepairStep step, String? detail, {bool failed = false}) {
    step
      ..detail = detail
      ..state = failed ? AiRepairStepState.failed : AiRepairStepState.done;
    _notify();
  }

  void _fail(AiRepairJob job, String explanation) {
    job
      ..outcome = AiRepairOutcome.failed
      ..explanation = explanation;
    _logOutcome('沒修好：$explanation');
    _notify();
  }

  /// 停下時正在等的那件事以取消結束，當成 null。
  Future<T?> _guard<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || _halting) return null;
      rethrow;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }

  static String _checkText(SourceCheckIsolateResult? result) {
    if (result == null) return '校驗超過時間';
    if (result.isHealthy) return '沒有問題';
    final health = BookSource.fromJson(result.updatedSourceJson).runtimeHealth;
    return '${health.label}：${result.message}';
  }

  static String _fetchText(SourceProbeReport probe) {
    if (probe.pageCount == 0) return probe.summary;
    final stages = probe.stagesReached;
    return '${stages.isEmpty ? '' : '$stages，'}共 ${probe.pageCount} 頁';
  }
}

/// 修復流程給 AI 對話的事（[RepairAgentHost]）：轉給 [AiRepairSession] 的
/// 私有成員，修復頁看不到。
final class _AgentHost implements RepairAgentHost {
  _AgentHost(this.s, this.job);

  final AiRepairSession s;
  final AiRepairJob job;

  @override
  bool get stopped => s._halting;

  @override
  Future<T?> guard<T>(Future<T> Function(CancelToken cancelToken) work) =>
      s._guard(() => work(s._cancelToken));

  @override
  AiRepairStep addStep(
    String title, {
    String? detail,
    AiRepairStepKind kind = AiRepairStepKind.stage,
  }) => s._addStep(job, title, detail: detail, kind: kind);

  @override
  void finish(AiRepairStep step, String? detail, {bool failed = false}) =>
      s._finish(step, detail, failed: failed);

  @override
  void fail(String explanation) => s._fail(job, explanation);

  @override
  void notify() => s._notify();

  @override
  void logProbe(String title, SourceProbeReport probe) =>
      s._logProbe(title, probe);

  @override
  String redact(String text) => s._redact(job, text);

  @override
  Future<void> refreshSecrets() => s._refreshSecrets(job);

  @override
  Future<String?> validate(
    BookSource candidate,
    String note, {
    required bool probeSucceeded,
  }) => s._validate(
    job,
    candidate,
    note,
    probeSucceeded: probeSucceeded,
    last: false,
  );

  @override
  void countRound() => job._rounds++;
}

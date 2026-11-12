import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/engine/web_book/book_list_parser.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/core/services/crash_trail.dart';
import 'package:night_reader/core/services/source_check_isolate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'agent_loop.dart';
import 'ai_chat_client.dart';
import 'ai_repair_backups.dart';
import 'ai_repair_log.dart';
import 'ai_repair_prompt.dart';
import 'ai_repair_secrets.dart';
import 'ai_repair_settings.dart';
import 'repair_pages.dart';
import 'repair_rule_tools.dart';
import 'source_probe.dart';

/// 一步的狀態：還沒開始、做著、做完、失敗。
enum AiRepairStepState { waiting, running, done, failed }

/// 修復頁上的一列（docs/design/screens.md「AI 修書源」）。
class AiRepairStep {
  AiRepairStep(
    this.title, {
    this.detail,
    this.state = AiRepairStepState.running,
  });

  final String title;
  String? detail;
  AiRepairStepState state;
}

/// 一個書源修完的結果。
enum AiRepairOutcome { repaired, failed }

/// 一個書源的修復：做過的步驟與結果。
class AiRepairJob {
  AiRepairJob(this.original);

  final BookSource original;
  final List<AiRepairStep> steps = [];
  AiRepairOutcome? outcome;

  /// 結果的說明：AI 最後說的話，或卡在哪。
  String? explanation;

  /// AI 明確放棄時才標「AI 修不好」；網路、金鑰、系統錯誤、校驗超過時間與
  /// 按停止都不標。
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

  /// 開場的試抓：[_firstProbe] 是抓到的原樣，[_probe] 是標上頁碼、給 AI 的
  /// 那份。整件重跑時照 [_firstProbe] 重新標頁碼，開場一字不差。
  SourceProbeReport? _firstProbe;
  SourceProbeReport? _probe;

  /// 這個書源的登入資料、Cookie 與變數的值，送出前遮掉（[aiRepairSecretsOf]）。
  Set<String> _secrets = const {};

  /// 問了 AI 幾輪，跨重跑接著數。
  int _rounds = 0;

  /// 開始存修好的書源了：這時按停止也停不下來，結果照存的結果。
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

/// 搜尋結果跟關鍵字有沒有關係（[searchFollowsKeyword]）。
typedef AiRepairKeywordCheck = Future<bool> Function(
  BookSource source,
  CancelToken cancelToken,
);

/// 問 AI 一次（測試用的假 AI）；真的服務用 [AiChatClient]，帶著
/// [aiRepairTools]。
typedef AiRepairAsker = AgentAsk;

/// AI 修一個書源（ADR 0054）：先校驗、抓網頁；有 AI 服務時讓 AI 邊看網頁邊
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
    AiRepairKeywordCheck? keywordCheck,
    AiRepairPageParser? parsePage,
    AiRepairJsRunner? runJs,
    Future<void> Function(BookSource repaired, BookSource original)? apply,
    Future<void> Function(String text)? copy,
    AiRepairBackups? backups,
    Future<Set<String>> Function(BookSource source)? secrets,
    this.recheckDelay = const Duration(seconds: 30),
    bool Function()? hasBudget,
    void Function(AiUsage usage)? onUsage,
    Future<Directory> Function()? logDirectory,
  }) : job = AiRepairJob(source),
       log = AiRepairLog(
         sourceName: source.bookSourceName,
         sourceUrl: source.bookSourceUrl,
         directory: logDirectory,
       ),
       _check = check ?? defaultCheck,
       _probe = probe ?? _defaultProbe,
       _fetchPage = fetchPage ?? _defaultFetchPage,
       _keywordCheck = keywordCheck ?? _defaultKeywordCheck,
       _parsePage = parsePage ?? _defaultParsePage,
       _runJs = runJs ?? _defaultRunJs,
       _hasBudget = hasBudget ?? _always,
       _copy = copy ?? _defaultCopy,
       _secretsOf = secrets ?? aiRepairSecretsOf,
       _backups = backups ?? AiRepairBackups.instance {
    _apply =
        apply ??
        (repaired, original) =>
            saveRepairedSource(repaired, original, backups: _backups);
    _onUsage = onUsage;
    _ask = ask ?? (service == null ? null : _defaultAsk(service!));
  }

  void Function(AiUsage usage)? _onUsage;

  /// 試抓成功、校驗沒過時，隔多久再校驗一次。
  final Duration recheckDelay;

  /// 還能再問 AI：整批修復有花費上限時，到了就不再問（[SourceRepairBatch]）。
  final bool Function() _hasBudget;

  static bool _always() => true;

  /// 使用者的 AI 服務；null 時用剪貼簿。
  final AiService? service;
  final AiRepairJob job;
  final AiRepairChecker _check;
  final AiRepairProber _probe;
  final AiRepairFetcher _fetchPage;
  final AiRepairKeywordCheck _keywordCheck;
  final AiRepairPageParser _parsePage;
  final AiRepairJsRunner _runJs;
  late final AgentAsk? _ask;

  /// 這次修復抓到的網頁，AI 用頁碼指（[RepairPages]）；修完就丟。
  final RepairPages _pages = RepairPages();
  final Future<void> Function(String text) _copy;
  final Future<Set<String>> Function(BookSource source) _secretsOf;
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
  bool _running = false;
  bool _stopped = false;
  bool _disposed = false;

  bool get usesClipboard => service == null;
  bool get isRunning => _running;
  bool get isStopped => _stopped;

  /// 做完（或停下）。剪貼簿等使用者貼回時不算。
  bool get isFinished => !_running && (_stopped || job.outcome != null);
  Future<void> get completion =>
      _pasteCompletion?.future ?? _startTask ?? Future<void>.value();

  /// 有紀錄可以複製、分享。
  bool get hasLog => !log.isEmpty;

  Future<void> start() {
    if (_startTask != null) return _startTask!;
    if (_stopped || _disposed || job.outcome != null) {
      return Future<void>.value();
    }
    return _startTask = _run();
  }

  Future<void> _run() async {
    _running = true;
    CrashTrail.action('開始 AI 修復：${job.original.bookSourceName}');
    _notify();
    try {
      await _repair(job);
    } catch (error, stack) {
      // 校驗、試抓或存檔丟出沒料到的錯：記成沒修好，做著的步驟標失敗，
      // 不讓畫面停在轉圈。
      AppLog.e('AI 修書源出錯', error: error, stackTrace: stack);
      if (job.outcome == null && !_stopped) {
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
      _running = false;
      // 抓到的網頁只給這次的 AI 用；整批修復一次開幾十段，不留在記憶體。
      _pages.clear();
      CrashTrail.action(
        'AI 修復${_stopped ? '停下了' : '做完了'}：${job.original.bookSourceName}',
      );
      _notify();
    }
  }

  /// 停下：做著的那一步標成停止，修到一半的不改。
  void stop() {
    if (_stopped || job.outcome != null) return;
    CrashTrail.action('按了停止：AI 修復 ${job.original.bookSourceName}');
    _stopped = true;
    if (!_cancelToken.isCancelled) _cancelToken.cancel('已停止');
    if (!job._committing) {
      for (final step in job.steps) {
        if (step.state == AiRepairStepState.running) {
          step
            ..state = AiRepairStepState.failed
            ..detail = '已停止';
        }
      }
      if (job.steps.isNotEmpty && job.outcome == null) {
        job
          ..awaitingPaste = false
          ..outcome = AiRepairOutcome.failed
          ..explanation = '已停止，書源沒有改。';
        _logOutcome('已停止，書源沒有改。');
      }
    }
    _notify();
  }

  /// 剪貼簿：使用者貼回 AI 修好的書源。讀不出書源時傳回原因、什麼都不做。
  Future<String?> submitPaste(String text) async {
    if (!job.awaitingPaste || _running || _stopped || _disposed) return null;
    if (text.length > aiRepairMaxReplyLength) return '貼回的內容太長';
    final json = pastedSourceJson(text);
    final candidate = json == null
        ? null
        : _candidateOrNull(job.original, json);
    if (candidate == null) return '讀不出書源 JSON';
    job.awaitingPaste = false;
    final pending = Completer<void>();
    _pasteCompletion = pending;
    _running = true;
    _notify();
    try {
      log
        ..section('貼回的書源')
        ..both(text);
      await _validate(job, candidate, '');
    } catch (error, stack) {
      AppLog.e('AI 貼回書源出錯', error: error, stackTrace: stack);
      if (!_stopped) {
        _fail(job, '校驗貼回的書源出錯，書源沒有改：$error');
      }
    } finally {
      _running = false;
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
    job._secrets = await _secretsOf(original);
    log
      ..redact = ((text) => _redact(job, text))
      ..header(_serviceText, prompt: aiRepairPromptVersion);
    if (_stopped) return;

    final checkStep = _addStep(job, '校驗原本的書源');
    log.section('校驗原本的書源');
    final checkWatch = Stopwatch()..start();
    final checked = await _guard(() => _check(original, _cancelToken));
    if (_stopped) return;
    final checkText = _checkText(checked);
    job._before = checked == null
        ? null
        : BookSource.fromJson(checked.updatedSourceJson).runtimeHealth.category;
    job._checkResult = [checkText, ...?checked?.diagnostics].join('\n\n');
    _finish(checkStep, checkText);
    log
      ..both('${_seconds(checkWatch)}：$checkText')
      ..both([...?checked?.diagnostics].join('\n\n'));
    // 校驗只看搜尋有沒有回書：原本的書源抓的就是頁面上固定的書時，開場就
    // 說，AI 才會連搜尋一起修（2026-11-12 涨姿势兩次都是修好正文、交出被退
    // 才知道網站的 ?s= 一律回首頁）。搜不到書時不多搜。
    if ((original.searchUrl ?? '').trim().isNotEmpty) {
      final follows = await _guard(() => _keywordCheck(original, _cancelToken));
      if (_stopped) return;
      if (follows == false) {
        const fact = '$aiRepairUnrelatedSearch（用「$nonsenseKeyword」搜尋也得到同樣的書）';
        job._checkResult = '${job._checkResult}\n\n$fact';
        log.both(fact);
      }
    }

    final fetchStep = _addStep(job, '抓網頁');
    log.section('抓網頁');
    final probeWatch = Stopwatch()..start();
    final probe = await _guard(() => _probe(original, _cancelToken));
    if (_stopped || probe == null) return;
    job
      .._firstProbe = probe
      .._probe = _withPageIds(probe);
    _finish(fetchStep, _fetchText(probe));
    _logProbe('${_seconds(probeWatch)}：${_fetchText(probe)}', probe);

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
    await _converse(job);
  }

  /// 試抓抓到的網頁登記進 [_pages]，給 AI 的那份每個回應標上頁碼；整頁原文
  /// 只留在 [_pages]。
  SourceProbeReport _withPageIds(SourceProbeReport probe) => SourceProbeReport(
    logs: probe.logs,
    requests: _pages.add(probe.requests, probe.pages),
    timedOut: probe.timedOut,
    contentUsable: probe.contentUsable,
  );

  /// 和 AI 來回（ADR 0054）：交給和任務無關的迴圈（[runAgent]），書源修復
  /// 的開場、指令與驗收在 [_RepairAgent]。對話照原樣一路接下去，前面的內容
  /// 不改寫：AI 要靠前面看過的網頁推下一步，開頭不變也讓服務的快取打得中。
  /// 卡住、失控、沒收斂時整件換新對話重跑，次數照 [AiAgentKnobs]。
  Future<void> _converse(AiRepairJob job) async {
    final agent = _RepairAgent(this, job);
    log.full('（迴圈的設定：${AiAgentKnobs.summary}）');
    log.tools(
      const JsonEncoder.withIndent('  ').convert(aiToolsJson(aiRepairTools)),
    );
    final end = await runAgent(
      agent,
      ask: _ask!,
      cancelToken: _cancelToken,
      hasBudget: _hasBudget,
    );
    _stats = end.stats;
    if (_stopped || job.outcome != null) {
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
      'promptVersion': aiRepairPromptVersion,
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

  /// 不連網站的指令做完：步驟的副標與紀錄。
  void _local(AiRepairStep step, String title, String reply) {
    _finish(step, title);
    log
      ..note(title)
      ..full(reply);
  }

  String _noPage(int page) => '# 沒有頁 $page：目前抓到的網頁是頁 1 到頁 ${_pages.length}。';

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
    final step = _addStep(job, '校驗修好的書源');
    log.section('校驗修好的書源');
    final checkWatch = Stopwatch()..start();
    var checked = await _guard(() => _check(candidate, _cancelToken));
    if (_stopped) return null;
    bool usable(SourceCheckIsolateResult? result) =>
        usableFix(result, job.original, candidate, before: job._before);
    if (probeSucceeded && !usable(checked)) {
      step.detail = '${_checkText(checked)}；稍後再校驗一次…';
      log
        ..both(
          '${_seconds(checkWatch)}：${_checkText(checked)}，'
          '${recheckDelay.inSeconds} 秒後再校驗一次',
        )
        ..full([...?checked?.diagnostics].join('\n\n'));
      _notify();
      await Future.any<Object?>([
        Future<void>.delayed(recheckDelay),
        _cancelToken.whenCancel,
      ]);
      if (_stopped) return null;
      checkWatch.reset();
      checked = await _guard<SourceCheckIsolateResult?>(
        () => _check(candidate, _cancelToken),
      );
      if (_stopped) return null;
    }
    final checkText = _checkText(checked);
    log.both('${_seconds(checkWatch)}：$checkText');
    if (checked != null && !usable(checked)) {
      log.both(checked.diagnostics.join('\n\n'));
    }
    if (checked == null || !usable(checked)) {
      _finish(step, checkText, failed: true);
      if (!last) {
        final discovery = _discoveryNote(checked, job.original, candidate);
        return aiRepairCheckReply(checkText, [
          ?discovery,
          ...?checked?.diagnostics,
        ]);
      }
      _fail(job, ['校驗：$checkText', if (note.isNotEmpty) 'AI：$note'].join('\n'));
      return null;
    }
    // 校驗只看搜尋有沒有回書：規則抓的是頁面上固定的推薦書也會過。
    step.detail = '$checkText；確認搜尋結果跟關鍵字有關…';
    _notify();
    final keywordWatch = Stopwatch()..start();
    final follows = await _guard(() => _keywordCheck(candidate, _cancelToken));
    if (_stopped) return null;
    if (follows == false) {
      const unrelated = aiRepairUnrelatedSearch;
      log.both('確認搜尋結果跟關鍵字有關（${_seconds(keywordWatch)}）：$unrelated');
      _finish(step, unrelated, failed: true);
      if (!last) {
        return '# 書源校驗沒過：$unrelated（用「$nonsenseKeyword」搜尋也得到同樣的書）';
      }
      _fail(job, ['校驗：$unrelated', if (note.isNotEmpty) 'AI：$note'].join('\n'));
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
    job
      ..outcome = AiRepairOutcome.repaired
      ..repairedSource = saved
      ..explanation = note.isEmpty ? null : 'AI：$note';
    _logOutcome('修好了，已套用${note.isEmpty ? '' : '\nAI：$note'}');
    _notify();
    return null;
  }

  /// 校驗的結果可以存：沒問題；或原本搜尋、閱讀有壞（[before] 不是只壞
  /// 發現頁），現在只剩發現頁失效、而 AI 沒動發現頁用的規則（[touchedDiscovery]）
  /// ——發現頁原本就壞了，搜尋與閱讀修好了還是比原本好。原本就只壞發現頁、
  /// 或不知道原本壞在哪（[before] 是 null）的，要整個沒問題才算。
  static bool usableFix(
    SourceCheckIsolateResult? result,
    BookSource original,
    BookSource candidate, {
    required SourceHealthCategory? before,
  }) {
    if (result == null) return false;
    if (result.isHealthy) return true;
    if (before == null || _discoveryOnly.contains(before)) return false;
    return _onlyDiscoveryFails(result) &&
        !touchedDiscovery(original, candidate);
  }

  static bool _onlyDiscoveryFails(SourceCheckIsolateResult result) =>
      _discoveryOnly.contains(
        BookSource.fromJson(result.updatedSourceJson).runtimeHealth.category,
      );

  /// AI 動了發現頁用的規則：改了發現的規則，或改了搜尋規則、而發現頁用搜尋
  /// 規則解析（[BookListParser.exploreUsesSearchRule]）。2026-11-12 實跑
  /// 涨姿势：發現沒有自己的書單規則，AI 把搜尋改成網站的 API，發現頁跟著
  /// 抓不到書，卻照「AI 沒動發現」收下。
  static bool touchedDiscovery(BookSource original, BookSource candidate) {
    final parts = changedParts(original, candidate);
    if (parts.contains('發現')) return true;
    return parts.contains('搜尋') &&
        (BookListParser.exploreUsesSearchRule(original) ||
            BookListParser.exploreUsesSearchRule(candidate));
  }

  /// 只剩發現頁沒過、是 AI 改搜尋規則連帶弄壞的時，回給 AI 的那一句。
  static String? _discoveryNote(
    SourceCheckIsolateResult? result,
    BookSource original,
    BookSource candidate,
  ) {
    if (result == null || !_onlyDiscoveryFails(result)) return null;
    final parts = changedParts(original, candidate);
    if (parts.contains('發現') || !parts.contains('搜尋')) return null;
    if (!touchedDiscovery(original, candidate)) return null;
    return aiRepairExploreBorrowsSearch;
  }

  static const Set<SourceHealthCategory> _discoveryOnly = {
    SourceHealthCategory.discoveryBroken,
    SourceHealthCategory.discoveryDetailBroken,
    SourceHealthCategory.discoveryTocBroken,
    SourceHealthCategory.discoveryContentBroken,
  };

  /// AI 回的書源照原本的身分組起來；欄位的型別或數值不對（例如超出範圍的
  /// 數字）時是 null，當成讀不懂。
  static BookSource? _candidateOrNull(
    BookSource original,
    Map<String, dynamic> json,
  ) {
    try {
      return candidateFrom(original, json);
    } catch (error) {
      AppLog.d('AI 回的書源讀不出來: $error');
      return null;
    }
  }

  String _redact(AiRepairJob job, String text) =>
      redactAiRepairSecrets(text, job._secrets);

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

  /// 一輪問 AI 的紀錄：送出多少、等到第一段資料的時間、花的時間與這輪的
  /// 用量（服務有回報時；沒回完就斷了時是估的）。
  static String _askText(AgentRoundRecord record) {
    final reply = record.reply;
    final seconds =
        '${(record.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} 秒';
    final sent = '送出 ${record.sentMessages} 句 ${_tokens(record.sentChars)} 字';
    final head = reply == null
        ? 'AI 回覆 $seconds（$sent）'
        : 'AI 回覆 $seconds（$sent，第一段資料 '
              '${(reply.firstData.inMilliseconds / 1000).toStringAsFixed(1)} 秒）';
    final usage = record.usage;
    if (usage == null) return head;
    return '$head；${record.estimated ? '沒回完，照字數估：' : ''}'
        '送出 ${_tokens(usage.prompt)} token'
        '（打中快取 ${_tokens(usage.cached)}）、回覆 ${_tokens(usage.completion)}'
        '（思考 ${_tokens(usage.reasoning)}）';
  }

  static String _seconds(Stopwatch watch) =>
      '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} 秒';

  static String _tokens(int count) =>
      NumberFormat.decimalPattern().format(count);

  AiRepairStep _addStep(AiRepairJob job, String title, {String? detail}) {
    final step = AiRepairStep(title, detail: detail);
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
      if (CancelToken.isCancel(error) || _stopped) return null;
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

  static String _changedText(BookSource before, BookSource after) {
    final parts = changedParts(before, after);
    return parts.isEmpty ? 'AI 沒改規則' : 'AI 改了$parts';
  }

  // ── 預設的實作：真的校驗、試抓、問 AI、存檔 ──────────────────────────

  static Future<SourceCheckConfig> _config() async =>
      SourceCheckConfig.fromPreferences(await SharedPreferences.getInstance());

  /// 照校驗設定校驗一次（在自己的 isolate 裡，ADR 0051）；逾時是 null。
  static Future<SourceCheckIsolateResult?> defaultCheck(
    BookSource source,
    CancelToken cancelToken,
  ) async {
    final config = await _config();
    final handle = await spawnSourceCheck(
      source,
      config.forIsolate,
      config.sourceTimeoutDuration,
    );
    unawaited(cancelToken.whenCancel.then((_) => handle.abort()));
    return handle.result;
  }

  static Future<SourceProbeReport> _defaultProbe(
    BookSource source,
    CancelToken cancelToken, {
    String? start,
  }) async {
    final config = await _config();
    return probeSource(
      source,
      keyword: start ?? source.getCheckKeyword(config.keyword),
      timeout: config.sourceTimeoutDuration,
      cancelToken: cancelToken,
    );
  }

  static Future<bool> _defaultKeywordCheck(
    BookSource source,
    CancelToken cancelToken,
  ) async {
    final config = await _config();
    return searchFollowsKeyword(
      source,
      keyword: source.getCheckKeyword(config.keyword),
      timeout: config.sourceTimeoutDuration,
      cancelToken: cancelToken,
    );
  }

  static Future<AiPage> _defaultFetchPage(
    BookSource source,
    String url,
    CancelToken cancelToken,
  ) async {
    final config = await _config();
    return fetchPageForAi(
      source,
      url,
      keyword: source.getCheckKeyword(config.keyword),
      timeout: config.sourceTimeoutDuration,
      cancelToken: cancelToken,
    );
  }

  static Future<String> _defaultParsePage(
    BookSource source,
    String stage,
    RepairPage page,
    CancelToken cancelToken,
  ) async => parseRepairPage(
    source,
    stage: stage,
    body: page.body,
    url: page.url,
    timeout: (await _config()).sourceTimeoutDuration,
    cancelToken: cancelToken,
  );

  static Future<String> _defaultRunJs(
    BookSource source,
    String code,
    Map<int, String> pages,
    CancelToken cancelToken,
  ) async => runRepairJs(
    source,
    code: code,
    pages: pages,
    timeout: (await _config()).sourceTimeoutDuration,
    cancelToken: cancelToken,
  );

  static AgentAsk _defaultAsk(AiService service) {
    final client = AiChatClient(service);
    return (messages, cancelToken) => client.complete(
      messages,
      tools: aiRepairTools,
      cancelToken: cancelToken,
    );
  }

  static Future<void> _defaultCopy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

/// AI 修一個書源這件事（[AgentTask]）：開場是書源、校驗結果與試抓，指令是
/// [AiRepairCommand]，交出與放棄由這裡驗收。工具的結果寫進紀錄、遮掉秘密
/// 後交給迴圈接進對話。
final class _RepairAgent implements AgentTask<AiRepairCommand> {
  _RepairAgent(this.s, this.job) : current = sourceForAi(job.original);

  final AiRepairSession s;
  final AiRepairJob job;

  /// 目前的書源（[sourceForAi] 的格式）：試抓或交出過的那份。
  Map<String, dynamic> current;

  /// 試抓或交出過修改了。
  bool tested = false;

  /// 自己查過網站了：看過網頁或跑過程式。
  bool looked = false;

  /// 沒試過就放棄、已經退回過一次了。
  bool pushedBack = false;

  /// 這一輪在修復頁上的那一列。
  AiRepairStep? step;

  /// 完整紀錄寫到對話的第幾句：每句只寫一次。
  int logged = 0;

  BookSource get original => job.original;

  @override
  String redact(String text) => s._redact(job, text);

  @override
  List<AiMessage> opening() => aiRepairOpening(
    source: original,
    checkResult: job._checkResult!,
    probe: job._probe!,
  );

  @override
  void restart(int attempt, String why) {
    // 全新的工具狀態：抓過的頁清掉，開場的試抓照原樣重新標頁碼。
    s._pages.clear();
    job._probe = s._withPageIds(job._firstProbe!);
    current = sourceForAi(original);
    tested = false;
    looked = false;
    pushedBack = false;
    logged = 0;
    s._finish(s._addStep(job, '重新開始（第 $attempt 次）', detail: why), why);
    s.log
      ..section('重新開始（第 $attempt 次）')
      ..both('上一次沒跑完：$why；換一段新的對話，從開場重來');
  }

  @override
  void roundStarted(int attempt, int round, List<AiMessage> messages) {
    job._rounds++;
    final title = attempt == 1 ? '第 $round 輪' : '第 $attempt 次 · 第 $round 輪';
    step = s._addStep(job, title, detail: 'AI 回覆中…');
    s.log.section(title, round: true);
    // 完整紀錄照順序寫下每一句，每句只寫一次：對話照原樣一路接下去，每輪
    // 送出的就是到那時為止的全部。
    for (final message in messages.skip(logged)) {
      s.log.message(message.role, message.content);
    }
    logged = messages.length;
  }

  @override
  void roundEnded(AgentRoundRecord record) {
    // 按了停止：做著的那一步已經標成停止（[AiRepairSession.stop]）。
    if (s._stopped) return;
    final reply = record.reply;
    if (record.usage case final usage?) s._onUsage?.call(usage);
    s.log.both(AiRepairSession._askText(record));
    if (reply == null) {
      final error = record.error ?? '沒有回覆';
      if (step case final step?) {
        s._finish(step, error.split('\n').first, failed: true);
      }
      s.log.full(error);
      return;
    }
    if (reply.reasoning.isNotEmpty) s.log.thinking(reply.reasoning);
    if (reply.content.trim().isNotEmpty) s.log.reply(reply.content);
    for (final call in reply.toolCalls) {
      s.log.toolCall(call.name, call.arguments);
    }
    // AI 回的話接進對話（迴圈做），完整紀錄已經寫了。
    logged = record.sentMessages + 1;
  }

  @override
  void factAdded(String fact) {}

  @override
  AgentParse<AiRepairCommand> parse(AiToolCall call) {
    final read = readAiRepairCall(call);
    if (read.command case final command?) {
      return AgentCommand(command, read.key);
    }
    if (step case final step?) s._finish(step, '讀不懂工具呼叫', failed: true);
    s.log.both('讀不懂工具呼叫：${read.fact}');
    return AgentBadCommand(read.fact);
  }

  @override
  String noToolCall(AiReply reply) {
    if (step case final step?) s._finish(step, '沒有呼叫工具', failed: true);
    s.log.both('沒有呼叫工具');
    return '# 這一輪沒有呼叫工具';
  }

  /// 讀不懂指令裡的東西：步驟標失敗，回 AI 哪裡不對。
  AgentInvalid invalid(String what, String fact) {
    if (step case final step?) s._finish(step, what, failed: true);
    s.log.both(what);
    return AgentInvalid(fact);
  }

  /// 指令改過的書源；用了書源沒有的欄位或組不起來是 null（[badChangeReply]
  /// 說哪裡不對）。
  (Map<String, dynamic>, BookSource)? candidateOf(AiChange change) {
    if (aiChangeProblem(change) != null) return null;
    final json = applyAiChange(current, change);
    final candidate = AiRepairSession._candidateOrNull(original, json);
    return candidate == null ? null : (json, candidate);
  }

  /// [candidateOf] 是 null 時回給 AI 的話。
  static String badChangeReply(AiChange change) =>
      switch (aiChangeProblem(change)) {
        final problem? => '$aiRepairBadCall：$problem',
        null => aiRepairBadSourceReply,
      };

  static const AgentStopped _cancelled = AgentStopped(
    AgentEndKind.cancelled,
    '已停止',
  );

  /// 工具的結果；比「結果與前幾次相同」時不看頁碼：同樣的網頁每抓一次就
  /// 多一個頁碼（2026-11-12 實跑時，一樣的回應因為頁 4、頁 6 被說成不同）。
  /// [same] 是拿來比的那一份，沒給時比 [text]。
  AgentToolResult answer(String text, {String? same}) => AgentToolResult(
    text,
    same: (same ?? text).replaceAll(RegExp(r'頁 \d+'), '頁 N'),
  );

  @override
  Future<AgentResult> execute(AiRepairCommand command) async {
    final step = this.step!;
    switch (command) {
      case AiGiveUp(:final reason, :final why)
          when !tested && !looked && !pushedBack && why != 'site_gone':
        // 只看了開場就放棄，多半是看了一眼就下結論：退回一次。查過網站的
        // 不退：2026-11-13 蜘蛛小说网查了 33 輪才放棄，被退回後只好交一個
        // 沒改的書源去試抓，多花 2 輪。
        pushedBack = true;
        s._finish(step, 'AI 想放棄，退回一次');
        s.log.both('AI 想放棄（$why：$reason），還沒查過網站，退回一次');
        return const AgentRejected(aiRepairGiveUpPushBack);
      case AiGiveUp(:final reason, :final why):
        s._finish(step, 'AI 說修不好');
        s.log.both('AI 說修不好（$why）');
        job
          ..confirmedUnfixable = true
          ..giveUpWhy = why;
        final label = aiGiveUpLabels[why] ?? why;
        s._fail(job, 'AI：$label${reason.isEmpty ? '' : '。$reason'}');
        return const AgentAccepted();
      case AiFetch(:final url):
        looked = true;
        step.detail = '看網頁 $url…';
        s._notify();
        final base =
            AiRepairSession._candidateOrNull(original, current) ?? original;
        final watch = Stopwatch()..start();
        final page = await s._guard(
          () => s._fetchPage(base, url, s._cancelToken),
        );
        if (s._stopped || page == null) return _cancelled;
        s._finish(step, '看網頁 $url');
        s.log
          ..both('看網頁 $url（${AiRepairSession._seconds(watch)}）')
          ..requests(page.lines, pages: page.pages);
        // 和抓過的同一頁只給頁碼（[RepairPages.add]）；比前後結果時照完整
        // 的回應比。
        return answer(
          aiRepairFetchReply(url, s._pages.add(page.lines, page.pages)),
          same: aiRepairFetchReply(url, page.lines),
        );
      case AiRead(:final page, :final from, :final length, :final raw):
        final found = s._pages[page];
        final reply = found == null
            ? s._noPage(page)
            : await readRepairPage(found, from: from, length: length, raw: raw);
        s._local(step, '讀頁 $page', reply);
        return answer(reply);
      case AiFind(:final page, text: final query, :final from):
        final found = s._pages[page];
        final reply = found == null
            ? s._noPage(page)
            : await findInRepairPage(found, query, from: from);
        s._local(step, '在頁 $page 找「$query」', reply);
        return answer(reply);
      case AiParse(:final page, :final stage, :final change):
        final found = s._pages[page];
        if (found == null) {
          s._local(step, '解析頁 $page', s._noPage(page));
          return answer(s._noPage(page));
        }
        final BookSource source;
        if (change == null) {
          source =
              AiRepairSession._candidateOrNull(original, current) ?? original;
        } else {
          final parsed = candidateOf(change);
          if (parsed == null) {
            return invalid('讀不懂 AI 回的書源', badChangeReply(change));
          }
          source = parsed.$2;
        }
        step.detail = '解析頁 $page…';
        s._notify();
        final result = await s._guard(
          () => s._parsePage(source, stage, found, s._cancelToken),
        );
        if (s._stopped || result == null) return _cancelled;
        final reply =
            '# 用${change == null ? '目前的' : '改過的'}規則把頁 $page 當成 '
            '$stage 解析\n$result';
        s._local(step, '解析頁 $page（$stage）', reply);
        return answer(reply);
      case AiJs(:final code):
        looked = true;
        final source =
            AiRepairSession._candidateOrNull(original, current) ?? original;
        final pages = {
          for (final match in RegExp(r'page\(\s*(\d+)\s*\)').allMatches(code))
            if (s._pages[int.parse(match.group(1)!)] case final page?)
              page.id: page.body,
        };
        step.detail = '跑程式…';
        s._notify();
        final result = await s._guard(
          () => s._runJs(source, code, pages, s._cancelToken),
        );
        if (s._stopped || result == null) return _cancelled;
        s.log.full('### 程式\n$code');
        s._local(step, '跑程式', '# 程式結果\n$result');
        return answer('# 程式結果\n$result');
      case AiTest(:final change, :final note, :final from, :final url):
        final parsed = candidateOf(change);
        if (parsed == null) {
          return invalid('讀不懂 AI 回的書源', badChangeReply(change));
        }
        final (json, candidate) = parsed;
        final start = from == 'search'
            ? null
            : probeStart(
                from,
                keyword: '',
                url: url,
                baseUrl: candidate.bookSourceUrl,
              );
        if (from != 'search' && start == null) {
          return invalid(
            '試抓的 from 不對，或少了 url',
            '# 讀不懂這個 test：from 要是 search、info、toc 或 content，'
                '不是 search 時要有 url',
          );
        }
        tested = true;
        current = json;
        final changed = AiRepairSession._changedText(original, candidate);
        final where = from == 'search' ? '' : '從 $from 開始';
        step.detail = '$changed，$where試抓中…';
        s._notify();
        final watch = Stopwatch()..start();
        final probe = await s._guard(
          () => s._probe(candidate, s._cancelToken, start: start),
        );
        if (s._stopped || probe == null) return _cancelled;
        s._logProbe(
          '$changed，$where試抓（${AiRepairSession._seconds(watch)}）：'
          '${probe.summary}',
          probe,
        );
        if (!probe.succeeded) {
          s._finish(step, '$changed，$where試抓：${probe.summary}');
          return answer(aiRepairProbeReply(s._withPageIds(probe)));
        }
        if (unjoinedContentPage(probe, candidate) case final next?) {
          final fact =
              '正文頁有指向同一章下一頁的連結（$next），ruleContent 沒有 '
              'nextContentUrl，每章只抓到第一頁';
          s._finish(step, '$changed，$where試抓：$fact', failed: true);
          s.log.both('試抓：$fact');
          return AgentRejected('# 書源校驗沒過：$fact');
        }
        s._finish(step, '$changed，$where試抓：${probe.summary}，交出');
        return submitted(
          await s._validate(
            job,
            candidate,
            note,
            probeSucceeded: true,
            last: false,
          ),
        );
      case AiSubmit(:final change, :final note):
        final parsed = candidateOf(change);
        if (parsed == null) {
          return invalid('讀不懂 AI 回的書源', badChangeReply(change));
        }
        final (json, candidate) = parsed;
        tested = true;
        current = json;
        final changed = AiRepairSession._changedText(original, candidate);
        s._finish(step, '$changed，交出');
        s.log.both('$changed，交出');
        return submitted(await s._validate(job, candidate, note, last: false));
    }
  }

  /// 交出後的驗收結果：[failure] 是沒過的原因（[AiRepairSession._validate]）。
  AgentResult submitted(String? failure) {
    if (failure != null) return AgentRejected(failure);
    if (s._stopped) return _cancelled;
    if (job.outcome == AiRepairOutcome.repaired) return const AgentAccepted();
    // 校驗過了卻存不進去（書源在修的時候被改過或刪掉）。
    return AgentStopped(AgentEndKind.failed, job.explanation ?? '存不進去');
  }
}

/// 存修好的書源（AI 修好、換網址或套用同網站修好的規則，ADR 0054）。修的
/// 這段時間書源被刪掉或改過（例如同步）時不存：存了會蓋掉別處的改動、或把
/// 刪掉的書源加回來。網址換了開頭時照書源編輯改網址的做法搬過去，書架上的
/// 書跟著搬；新網址已經有別的書源時不存。存之前留下改前的版本。
Future<void> saveRepairedSource(
  BookSource repaired,
  BookSource original, {
  AiRepairBackups? backups,
}) async {
  final dao = getIt<BookSourceDao>();
  final current = await dao.getByUrl(original.bookSourceUrl);
  if (current == null) {
    throw const AiRepairConflict('修的這段時間書源被刪掉了，沒有存。');
  }
  if (changedParts(original, current).isNotEmpty ||
      current.bookSourceName != original.bookSourceName) {
    throw const AiRepairConflict('修的這段時間書源被改過了（例如同步），沒有存。');
  }
  // 修好了：之前標的「AI 修不好」拿掉。開關、排序與權重照現在的：修的這段
  // 時間在別處（例如同步）改了，不蓋回修之前的值。
  repaired
    ..removeGroup(aiUnfixableSourceGroupTag)
    ..enabled = current.enabled
    ..enabledExplore = current.enabledExplore
    ..customOrder = current.customOrder
    ..weight = current.weight;
  final moved = repaired.bookSourceUrl != original.bookSourceUrl;
  if (moved && await dao.getByUrl(repaired.bookSourceUrl) != null) {
    throw AiRepairConflict('新網址 ${repaired.bookSourceUrl} 已經有別的書源，沒有存。');
  }
  await (backups ?? AiRepairBackups.instance).put(
    repaired.bookSourceUrl,
    current.toJson(),
  );
  await BookSourceService().saveEditedSource(
    repaired,
    previousUrl: moved ? original.bookSourceUrl : null,
  );
}

/// 修好的書源存不進去：修的這段時間書源被刪掉或改過。
class AiRepairConflict implements Exception {
  const AiRepairConflict(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 把書源還原成 AI 改之前的那份，並刪掉留著的改前版本。AI 換過網址開頭
/// 的，網址也換回去，書架上的書跟著搬回去。
///
/// 傳回真的還原了沒：沒有改前版本、或書源已經刪掉了是 false。
Future<bool> restoreAiRepair(
  String sourceUrl, {
  AiRepairBackups? backups,
}) async {
  final store = backups ?? AiRepairBackups.instance;
  final json = await store.get(sourceUrl);
  if (json == null) return false;
  // 書源已經刪掉了（例如另一台同步刪的）：不還原，免得把它加回來。
  if (await getIt<BookSourceDao>().getByUrl(sourceUrl) == null) {
    await store.remove(sourceUrl);
    return false;
  }
  final previous = BookSource.fromJson(json);
  await BookSourceService().saveEditedSource(
    previous,
    previousUrl: previous.bookSourceUrl == sourceUrl ? null : sourceUrl,
  );
  await store.remove(sourceUrl);
  return true;
}

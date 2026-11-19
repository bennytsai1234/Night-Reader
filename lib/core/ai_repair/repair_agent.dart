import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:night_reader/core/models/source/book_source.dart';

import 'agent_loop.dart';
import 'ai_chat_client.dart';
import 'ai_repair_log.dart';
import 'ai_repair_prompt.dart';
import 'ai_repair_session.dart';
import 'ai_repair_step.dart';
import 'repair_pages.dart';
import 'repair_verdict.dart';
import 'request_answers.dart';
import 'source_probe.dart';

/// AI 對話（[RepairAgent]）要修復流程（[AiRepairSession]）給的事：停了沒、
/// 帶著取消做連網站的事、修復頁的步驟與結果、試抓的紀錄、遮秘密、驗收
/// 交出，與數一輪。由修復流程裡一個私有的類別提供，修復頁看不到。
abstract interface class RepairAgentHost {
  /// 按了暫停或結束。
  bool get stopped;

  /// 帶著這次修復的取消做 [work]；停下時正在等的那件事以取消結束，當成
  /// null。
  Future<T?> guard<T>(Future<T> Function(CancelToken cancelToken) work);

  /// 修復頁上加一步。
  AiRepairStep addStep(
    String title, {
    String? detail,
    AiRepairStepKind kind = AiRepairStepKind.stage,
  });

  /// 一步做完（或失敗），[detail] 是它的結果。
  void finish(AiRepairStep step, String? detail, {bool failed = false});

  /// 記成沒修好，[explanation] 是原因。
  void fail(String explanation);

  /// 畫面要重畫（步驟的副標改了）。
  void notify();

  /// 一次試抓寫進紀錄。
  void logProbe(String title, SourceProbeReport probe);

  /// 送給 AI、寫進紀錄的文字遮掉秘密。
  String redact(String text);

  /// 重讀這個書源的秘密：工具可能寫了新的 Cookie 或變數。
  Future<void> refreshSecrets();

  /// 校驗 AI 交出的書源，通過才存進去；沒通過時傳回要回給 AI 的校驗結果，
  /// 修好、存不進去或停下時是 null。
  Future<String?> validate(
    BookSource candidate,
    String note, {
    required bool probeSucceeded,
  });

  /// 問了 AI 一輪。
  void countRound();
}

/// 試抓抓到的網頁登記進 [pages]，給 AI 的那份每個回應標上頁碼；整頁原文
/// 只留在 [pages]。
SourceProbeReport withPageIds(RepairPages pages, SourceProbeReport probe) =>
    SourceProbeReport(
      logs: probe.logs,
      requests: pages.add(probe.requests, probe.pages),
      timedOut: probe.timedOut,
      contentUsable: probe.contentUsable,
      unjoinedNextPage: probe.unjoinedNextPage,
    );

/// AI 修一個書源這件事（[AgentTask]）：開場是書源、校驗結果與試抓，指令是
/// [AiRepairCommand]，交出與放棄由這裡驗收。工具的結果寫進紀錄、遮掉秘密
/// 後交給迴圈接進對話。
final class RepairAgent implements AgentTask<AiRepairCommand> {
  RepairAgent(
    this._host,
    this._job, {
    required this._log,
    required this._pages,
    required this._prober,
    required this._fetchPage,
    required this._parsePage,
    required this._runJs,
    required this._onUsage,
    required this._checkResult,
    required this._firstProbe,
    required this._openingProbe,
  }) : _current = sourceForAi(_job.original);

  final RepairAgentHost _host;
  final AiRepairJob _job;

  /// 這次修復的紀錄（[AiRepairSession.log]）。
  final AiRepairLog _log;

  /// 這次修復抓到的網頁，AI 用頁碼指（[RepairPages]）。
  final RepairPages _pages;
  final AiRepairProber _prober;
  final AiRepairFetcher _fetchPage;
  final AiRepairPageParser _parsePage;
  final AiRepairJsRunner _runJs;
  final void Function(AiUsage usage)? _onUsage;

  /// 給 AI 的現況：原本的校驗結果與程式讀到的事實。
  final String _checkResult;

  /// 開場的試抓：[_firstProbe] 是抓到的原樣，[_openingProbe] 是標上頁碼、
  /// 給 AI 的那份。整件重跑時照 [_firstProbe] 重新標頁碼，開場一字不差。
  final SourceProbeReport _firstProbe;
  SourceProbeReport _openingProbe;

  /// 目前的書源（[sourceForAi] 的格式）：試抓或交出過的那份。
  Map<String, dynamic> _current;

  /// 這一輪在修復頁上的那一列。
  AiRepairStep? _step;

  /// 完整紀錄寫到對話的第幾句：每句只寫一次。
  int _logged = 0;

  /// 最後一次試抓到正文的那份書源（JSON 字串）：AI 交出的是同一份時，校驗
  /// 照「試抓抓到過正文」做（沒過先隔一段時間再校驗一次）。
  String? _probedOk;

  BookSource get _original => _job.original;

  /// 不連網站的指令做完：步驟的副標與紀錄。
  void _local(AiRepairStep step, String title, String reply) {
    _host.finish(step, title);
    _log
      ..note(title)
      ..full(reply);
  }

  String _noPage(int page) => '# 沒有頁 $page：目前抓到的網頁是頁 1 到頁 ${_pages.length}。';

  static String _changedText(BookSource before, BookSource after) {
    final parts = changedParts(before, after);
    return parts.isEmpty ? 'AI 沒改規則' : 'AI 改了$parts';
  }

  /// 這件修復裡每個請求回過什麼（[RequestAnswers]）：整件重跑也不清。
  final RequestAnswers _answers = RequestAnswers();

  /// 開場的校驗與試抓裡時好時壞的那一段（[RequestAnswers.record]）：只算
  /// 一次，整件重跑時開場一字不差。
  String? _openingMixed;

  @override
  String redact(String text) => _host.redact(text);

  @override
  List<AiMessage> opening() => aiRepairOpening(
    source: _original,
    checkResult: _checkResult,
    probe: _openingProbe,
    mixedAnswers: _openingMixed ??= _answers.record(
      '$_checkResult\n${_firstProbe.requests.join('\n')}',
    ),
  );

  @override
  void restart(int attempt, String why) {
    // 全新的工具狀態：抓過的頁清掉，開場的試抓照原樣重新標頁碼。
    _pages.clear();
    _openingProbe = withPageIds(_pages, _firstProbe);
    _current = sourceForAi(_original);
    _logged = 0;
    _probedOk = null;
    // 上一次最後一輪被打斷時還是做著的：收成失敗，「經過」裡不留轉圈的步。
    for (final last in _job.steps) {
      if (last.state == AiRepairStepState.running) {
        last.state = AiRepairStepState.failed;
      }
    }
    _host.finish(
      _host.addStep(
        '重新開始（第 $attempt 次）',
        detail: why,
        kind: AiRepairStepKind.restart,
      ),
      why,
    );
    _log
      ..section('重新開始（第 $attempt 次）')
      ..both('上一次沒跑完：$why；換一段新的對話，從開場重來');
  }

  @override
  void roundStarted(int attempt, int round, List<AiMessage> messages) {
    _host.countRound();
    final title = attempt == 1 ? '第 $round 輪' : '第 $attempt 次 · 第 $round 輪';
    _step = _host.addStep(
      title,
      detail: 'AI 回覆中…',
      kind: AiRepairStepKind.round,
    );
    _log.section(title, round: true);
    // 完整紀錄照順序寫下每一句，每句只寫一次：對話照原樣一路接下去，每輪
    // 送出的就是到那時為止的全部。
    for (final message in messages.skip(_logged)) {
      _log.message(message.role, message.content);
    }
    _logged = messages.length;
  }

  @override
  void roundEnded(AgentRoundRecord record) {
    // 按了暫停或結束：做著的那一步已經標好（[AiRepairSession.stop]、[AiRepairSession.pause]）。
    if (_host.stopped) return;
    final reply = record.reply;
    if (record.usage case final usage?) _onUsage?.call(usage);
    _log.both(agentRoundText(record));
    if (reply == null) {
      final error = record.error ?? '沒有回覆';
      if (_step case final step?) {
        _host.finish(step, error.split('\n').first, failed: true);
      }
      _log.full(error);
      return;
    }
    if (reply.reasoning.isNotEmpty) _log.thinking(reply.reasoning);
    if (reply.content.trim().isNotEmpty) _log.reply(reply.content);
    for (final call in reply.toolCalls) {
      _log.toolCall(call.name, call.arguments);
    }
    // AI 回的話接進對話（迴圈做），完整紀錄已經寫了。
    _logged = record.sentMessages + 1;
  }

  @override
  void factAdded(String fact) {}

  @override
  void checkpoint(AgentCheckpoint state) {}

  /// 修書源的工具會改正在修的書源（改了再試抓），照順序執行。
  @override
  bool runsAlongside(AiRepairCommand command) => false;

  @override
  AgentParse<AiRepairCommand> parse(AiToolCall call) {
    final read = readAiRepairCall(call);
    if (read.command case final command?) {
      return AgentCommand(command, read.key);
    }
    final malformed = read.malformed;
    if (_step case final step?) _host.finish(step, '讀不懂工具呼叫', failed: true);
    _log.both(
      '讀不懂工具呼叫：${read.fact}'
      '${malformed ? '（這則回覆不接進對話，同一段對話重送）' : ''}',
    );
    return AgentBadCommand(read.fact, malformed: malformed);
  }

  @override
  String noToolCall(AiReply reply) {
    if (_step case final step?) _host.finish(step, '沒有呼叫工具', failed: true);
    _log.both('沒有呼叫工具');
    return '# 這一輪沒有呼叫工具';
  }

  /// 讀不懂指令裡的東西：步驟標失敗，回 AI 哪裡不對。
  AgentInvalid _invalid(String what, String fact) {
    if (_step case final step?) _host.finish(step, what, failed: true);
    _log.both(what);
    return AgentInvalid(fact);
  }

  /// 指令改過的書源；用了書源沒有的欄位或組不起來是 null（[_badChangeReply]
  /// 說哪裡不對）。
  (Map<String, dynamic>, BookSource)? _candidateOf(AiChange change) {
    if (aiChangeProblem(change) != null) return null;
    final json = applyAiChange(_current, change);
    final candidate = candidateOrNull(_original, json);
    return candidate == null ? null : (json, candidate);
  }

  /// [_candidateOf] 是 null 時回給 AI 的話。
  static String _badChangeReply(AiChange change) =>
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
  AgentToolResult _answer(String text, {String? same}) => AgentToolResult(
    text,
    same: (same ?? text).replaceAll(RegExp(r'頁 \d+'), '頁 N'),
  );

  @override
  Future<AgentResult> execute(AiRepairCommand command) async {
    final result = await _run(command);
    // 工具跑完、結果接進對話之前重讀秘密：這一步可能寫了新的 Cookie 或變數。
    await _host.refreshSecrets();
    return switch (result) {
      // 比「結果與前幾次相同」照工具本身的結果，不算後面附的這段。
      AgentToolResult(:final text, :final same) => AgentToolResult(
        '$text${_answers.record(text)}',
        same: same ?? text,
      ),
      AgentRejected(:final reason) => AgentRejected(
        '$reason${_answers.record(reason)}',
      ),
      _ => result,
    };
  }

  Future<AgentResult> _run(AiRepairCommand command) async {
    final step = _step!;
    switch (command) {
      case AiGiveUp(:final reason, :final why):
        _host.finish(step, 'AI 說修不好');
        _log.both('AI 說修不好（$why）');
        _job
          ..confirmedUnfixable = true
          ..giveUpWhy = why;
        final label = aiGiveUpLabels[why] ?? why;
        _host.fail('AI：$label${reason.isEmpty ? '' : '。$reason'}');
        return const AgentAccepted.gaveUp();
      case AiFetch(:final url):
        step.detail = '看網頁 $url…';
        _host.notify();
        final base = candidateOrNull(_original, _current) ?? _original;
        final watch = Stopwatch()..start();
        final page = await _host.guard(
          (cancelToken) => _fetchPage(base, url, cancelToken),
        );
        if (_host.stopped || page == null) return _cancelled;
        _host.finish(step, '看網頁 $url');
        _log
          ..both('看網頁 $url（${AiRepairLog.seconds(watch)}）')
          ..requests(page.lines, pages: page.pages);
        // 和抓過的同一頁只給頁碼（[RepairPages.add]）；比前後結果時照完整
        // 的回應比。
        return _answer(
          aiRepairFetchReply(url, _pages.add(page.lines, page.pages)),
          same: aiRepairFetchReply(url, page.lines),
        );
      case AiRead(:final page, :final from, :final length, :final raw):
        final found = _pages[page];
        final reply = found == null
            ? _noPage(page)
            : await readRepairPage(found, from: from, length: length, raw: raw);
        // 讀頁在別的 isolate 做，回來前按了暫停或結束：步驟已經收成失敗，
        // 不再蓋回去（同解析頁、跑程式）。
        if (_host.stopped) return _cancelled;
        _local(step, '讀頁 $page', reply);
        return _answer(reply);
      case AiFind(:final page, text: final query, :final from):
        final found = _pages[page];
        final reply = found == null
            ? _noPage(page)
            : await findInRepairPage(found, query, from: from);
        if (_host.stopped) return _cancelled;
        _local(step, '在頁 $page 找「$query」', reply);
        return _answer(reply);
      case AiParse(:final page, :final stage, :final change):
        final found = _pages[page];
        if (found == null) {
          _local(step, '解析頁 $page', _noPage(page));
          return _answer(_noPage(page));
        }
        final BookSource source;
        if (change == null) {
          source = candidateOrNull(_original, _current) ?? _original;
        } else {
          final parsed = _candidateOf(change);
          if (parsed == null) {
            return _invalid('讀不懂 AI 回的書源', _badChangeReply(change));
          }
          source = parsed.$2;
        }
        step.detail = '解析頁 $page…';
        _host.notify();
        final result = await _host.guard(
          (cancelToken) => _parsePage(source, stage, found, cancelToken),
        );
        if (_host.stopped || result == null) return _cancelled;
        final reply =
            '# 用${change == null ? '目前的' : '改過的'}規則把頁 $page 當成 '
            '$stage 解析\n$result';
        _local(step, '解析頁 $page（$stage）', reply);
        return _answer(reply);
      case AiJs(:final code):
        final source = candidateOrNull(_original, _current) ?? _original;
        final pages = {
          for (final match in RegExp(r'page\(\s*(\d+)\s*\)').allMatches(code))
            if (_pages[int.parse(match.group(1)!)] case final page?)
              page.id: page.body,
        };
        step.detail = '跑程式…';
        _host.notify();
        final result = await _host.guard(
          (cancelToken) => _runJs(source, code, pages, cancelToken),
        );
        if (_host.stopped || result == null) return _cancelled;
        _log.full('### 程式\n$code');
        _local(step, '跑程式', '# 程式結果\n$result');
        return _answer('# 程式結果\n$result');
      case AiTest(:final change, :final from, :final url):
        final parsed = _candidateOf(change);
        if (parsed == null) {
          return _invalid('讀不懂 AI 回的書源', _badChangeReply(change));
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
          return _invalid(
            '試抓的 from 不對，或少了 url',
            '# 讀不懂這個 test：from 要是 search、explore、info、toc 或 content，'
                '不是 search 時要有 url',
          );
        }
        _current = json;
        final changed = _changedText(_original, candidate);
        final where = from == 'search' ? '' : '從 $from 開始';
        step.detail = '$changed，$where試抓中…';
        _host.notify();
        final watch = Stopwatch()..start();
        final probe = await _host.guard(
          (cancelToken) => _prober(candidate, cancelToken, start: start),
        );
        if (_host.stopped || probe == null) return _cancelled;
        _host.logProbe(
          '$changed，$where試抓（${AiRepairLog.seconds(watch)}）：'
          '${probe.summary}',
          probe,
        );
        if (!probe.succeeded) {
          _host.finish(step, '$changed，$where試抓：${probe.summary}');
          return _answer(aiRepairProbeReply(withPageIds(_pages, probe)));
        }
        if (probe.unjoinedNextPage case final next?) {
          final hasRule = (candidate.ruleContent?.nextContentUrl ?? '')
              .trim()
              .isNotEmpty;
          final fact =
              '正文頁有指向同一章下一頁的連結（$next），'
              '${hasRule ? 'nextContentUrl 沒有抓到它' : 'ruleContent 沒有 nextContentUrl'}'
              '，每章只抓到第一頁';
          _host.finish(step, '$changed，$where試抓：$fact', failed: true);
          _log.both('試抓：$fact');
          return AgentRejected('# 書源校驗沒過：$fact');
        }
        // 試抓不交出：AI 看過結果自己 submit（使用者 2026-11-13，ADR 0054）。
        _probedOk = jsonEncode(json);
        final mismatch = searchInfoMismatch(probe);
        _host.finish(step, '$changed，$where試抓：${probe.summary}');
        if (mismatch != null) _log.both('試抓：$mismatch');
        return _answer(
          aiRepairProbeReply(withPageIds(_pages, probe), mismatch: mismatch),
        );
      case AiSubmit(:final change, :final note):
        final parsed = _candidateOf(change);
        if (parsed == null) {
          return _invalid('讀不懂 AI 回的書源', _badChangeReply(change));
        }
        final (json, candidate) = parsed;
        _current = json;
        final changed = _changedText(_original, candidate);
        _host.finish(step, '$changed，交出');
        _log.both('$changed，交出');
        return _submitted(
          await _host.validate(
            candidate,
            note,
            probeSucceeded: _probedOk == jsonEncode(json),
          ),
        );
    }
  }

  /// 交出後的驗收結果：[failure] 是沒過的原因（[RepairAgentHost.validate]）。
  AgentResult _submitted(String? failure) {
    if (failure != null) return AgentRejected(failure);
    if (_host.stopped) return _cancelled;
    if (_job.outcome == AiRepairOutcome.repaired) return const AgentAccepted();
    // 規則沒改、只是網站時好時壞（[RepairAgentHost.validate]）：算放棄。
    if (_job.confirmedUnfixable) return const AgentAccepted.gaveUp();
    // 校驗過了卻存不進去（書源在修的時候被改過或刪掉）。
    return AgentStopped(AgentEndKind.failed, _job.explanation ?? '存不進去');
  }
}

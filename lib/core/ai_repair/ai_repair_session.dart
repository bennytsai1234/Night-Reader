import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/services/app_log_service.dart';
import 'package:night_reader/core/services/book_source_service.dart';
import 'package:night_reader/core/services/check_source_service.dart';
import 'package:night_reader/core/services/source_check_isolate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_chat_client.dart';
import 'ai_repair_backups.dart';
import 'ai_repair_prompt.dart';
import 'ai_repair_secrets.dart';
import 'ai_repair_settings.dart';
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
enum AiRepairOutcome { repaired, failed, skipped }

/// 一個書源的修復：做過的步驟與結果。
class AiRepairJob {
  AiRepairJob(this.original);

  final BookSource original;
  final List<AiRepairStep> steps = [];
  AiRepairOutcome? outcome;

  /// 結果的說明：AI 最後說的話，或卡在哪。
  String? explanation;

  /// 剪貼簿：已複製給 AI，等使用者貼回修好的書源。
  bool awaitingPaste = false;

  /// 修好之後又還原了。
  bool restored = false;

  /// 修好存進去時的網址：AI 換了網址開頭時和原本的不同。
  String? repairedUrl;

  /// 給 AI 與剪貼簿用的現況：原本的校驗結果與試抓。
  String? _checkResult;
  SourceProbeReport? _probe;

  /// 這個書源的登入資料、Cookie 與變數的值，送出前遮掉（[aiRepairSecretsOf]）。
  Set<String> _secrets = const {};

  /// AI 回了幾次話，跨兩回接著數。
  int _rounds = 0;

  /// 開始存修好的書源了：這時按停止也停不下來，結果照存的結果。
  bool _committing = false;
}

/// 一次校驗的結果；逾時是 null（同書源校驗，ADR 0051）。
typedef AiRepairChecker = Future<SourceCheckIsolateResult?> Function(
  BookSource source,
  CancelToken cancelToken,
);

/// 一次試抓（[probeSource]）。
typedef AiRepairProber = Future<SourceProbeReport> Function(
  BookSource source,
  CancelToken cancelToken,
);

/// AI 要看的一頁（[fetchPageForAi]）。
typedef AiRepairFetcher = Future<String> Function(
  BookSource source,
  String url,
  CancelToken cancelToken,
);

/// 問 AI 一次。
typedef AiRepairAsker = Future<String> Function(
  List<AiMessage> messages,
  CancelToken cancelToken,
);

/// AI 修書源（ADR 0054）：一個或多選的一批書源，一個接一個修。每個先校驗、
/// 抓網頁；有 AI 服務時讓 AI 邊改邊試抓，最多 [aiRepairMaxRounds] 輪，交出後
/// 再校驗，通過才存進去並留下改前版本。沒有 AI 服務時（只限一個書源）把
/// 提示詞複製下來，等使用者貼回 AI 修好的書源（[submitPaste]）。
class AiRepairSession extends ChangeNotifier {
  AiRepairSession({
    required List<BookSource> sources,
    required this.service,
    AiRepairChecker? check,
    AiRepairProber? probe,
    AiRepairAsker? ask,
    AiRepairFetcher? fetchPage,
    Future<void> Function(BookSource repaired, BookSource original)? apply,
    Future<void> Function(String text)? copy,
    AiRepairBackups? backups,
    Future<Set<String>> Function(BookSource source)? secrets,
    this.recheckDelay = const Duration(seconds: 30),
  }) : assert(service != null || sources.length == 1),
       jobs = [for (final source in sources) AiRepairJob(source)],
       _check = check ?? _defaultCheck,
       _probe = probe ?? _defaultProbe,
       _fetchPage = fetchPage ?? _defaultFetchPage,
       _ask = ask ?? (service == null ? null : _defaultAsk(service)),
       _copy = copy ?? _defaultCopy,
       _secretsOf = secrets ?? aiRepairSecretsOf,
       _backups = backups ?? AiRepairBackups.instance {
    _apply = apply ?? _defaultApply;
  }

  /// 試抓成功、校驗沒過時，隔多久再校驗一次。
  final Duration recheckDelay;

  /// 使用者的 AI 服務；null 時用剪貼簿。
  final AiService? service;
  final List<AiRepairJob> jobs;
  final AiRepairChecker _check;
  final AiRepairProber _probe;
  final AiRepairFetcher _fetchPage;
  final AiRepairAsker? _ask;
  final Future<void> Function(String text) _copy;
  final Future<Set<String>> Function(BookSource source) _secretsOf;
  final AiRepairBackups _backups;
  late final Future<void> Function(BookSource repaired, BookSource original)
  _apply;

  final CancelToken _cancelToken = CancelToken();
  final StringBuffer _transcript = StringBuffer();
  bool _running = false;
  bool _stopped = false;
  bool _disposed = false;
  int _current = 0;

  bool get usesClipboard => service == null;
  bool get isRunning => _running;
  bool get isStopped => _stopped;

  /// 正在修第幾個（從 0 起）。
  int get current => _current;

  /// 全部做完（或停下）。剪貼簿等使用者貼回時不算。
  bool get isFinished => _stopped || jobs.every((job) => job.outcome != null);

  int count(AiRepairOutcome outcome) =>
      jobs.where((job) => job.outcome == outcome).length;

  /// 「複製紀錄」：每一步、AI 每一輪說的話與試抓結果。
  String get transcript => _transcript.toString().trimRight();

  /// 從第一個書源開始修。
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _notify();
    try {
      for (var i = 0; i < jobs.length && !_stopped; i++) {
        _current = i;
        _notify();
        await _repair(jobs[i]);
        if (jobs[i].awaitingPaste) return;
      }
    } finally {
      _running = false;
      _notify();
    }
  }

  /// 停下：做著的那一步標成停止，還沒修的書源不修，修到一半的不改。
  void stop() {
    if (_stopped || isFinished) return;
    _stopped = true;
    if (!_cancelToken.isCancelled) _cancelToken.cancel('已停止');
    for (final job in jobs) {
      if (job._committing) continue;
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
      }
    }
    _notify();
  }

  /// 剪貼簿：使用者貼回 AI 修好的書源。讀不出書源時傳回原因、什麼都不做。
  Future<String?> submitPaste(String text) async {
    final job = jobs.single;
    if (!job.awaitingPaste || _running) return null;
    if (text.length > aiRepairMaxReplyLength) return '貼回的內容太長';
    final json = pastedSourceJson(text);
    final candidate = json == null
        ? null
        : _candidateOrNull(job.original, json);
    if (candidate == null) return '讀不出書源 JSON';
    job.awaitingPaste = false;
    _running = true;
    _notify();
    try {
      _record('## 貼回的書源\n$text');
      await _validate(job, candidate, '');
    } finally {
      _running = false;
      _notify();
    }
    return null;
  }

  /// 修好之後還原成改前的版本。
  Future<void> restore(AiRepairJob job) async {
    if (job.outcome != AiRepairOutcome.repaired || job.restored) return;
    await restoreAiRepair(
      job.repairedUrl ?? job.original.bookSourceUrl,
      backups: _backups,
    );
    job.restored = true;
    _notify();
  }

  Future<void> _repair(AiRepairJob job) async {
    final original = job.original;
    _record('# ${original.bookSourceName}（${original.bookSourceUrl}）');
    job._secrets = await _secretsOf(original);
    if (_stopped) return;

    final checkStep = _addStep(job, '校驗原本的書源');
    final checked = await _guard(() => _check(original, _cancelToken));
    if (_stopped) return;
    final health = checked == null
        ? null
        : BookSource.fromJson(checked.updatedSourceJson).runtimeHealth;
    final checkText = _checkText(checked);
    job._checkResult = _redact(
      job,
      [checkText, ...?checked?.diagnostics].join('\n\n'),
    );
    _finish(checkStep, checkText);
    _record('校驗原本的書源：${job._checkResult}');

    if (jobs.length > 1) {
      final skip = health == null
          ? '跳過：校驗超過時間'
          : health.category == SourceHealthCategory.healthy
          ? '沒問題，跳過'
          : _unfixable.contains(health.category)
          ? '跳過：${health.label}'
          : null;
      if (skip != null) {
        checkStep.detail = skip;
        job
          ..outcome = AiRepairOutcome.skipped
          ..explanation = skip;
        _notify();
        return;
      }
    }

    final fetchStep = _addStep(job, '抓網頁');
    final probe = await _guard(() => _probe(original, _cancelToken));
    if (_stopped || probe == null) return;
    job._probe = probe;
    _finish(fetchStep, _fetchText(probe));
    _record('抓網頁：${_fetchText(probe)}\n${_probeText(job, probe)}');

    if (usesClipboard) {
      await _copy(
        _redact(
          job,
          aiRepairClipboardPrompt(
            source: original,
            checkResult: job._checkResult!,
            probe: probe,
          ),
        ),
      );
      _finish(_addStep(job, '已複製給 AI'), null);
      job.awaitingPaste = true;
      _notify();
      return;
    }
    final tried = await _converse(job);
    if (tried == null || _stopped) return;
    // 試抓用完還沒修好：AI 常卡在同一個方向，重開一段對話、告訴它上一次
    // 試過什麼，再給一次機會。
    _finish(_addStep(job, '重新來一次', detail: '換個方向再試'), '換個方向再試');
    await _converse(job, earlier: tried);
  }

  /// 和 AI 來回：每一輪 AI 回一個指令，試抓或看網頁的結果回給它，直到交出、
  /// 放棄或次數用完。試抓最多 [aiRepairMaxTests] 次、看網頁最多
  /// [aiRepairMaxFetches] 次，各算各的：先看網頁找出網站現在的樣子，不會
  /// 用掉試抓的機會。只留最近一輪的書源與網頁全文，前面的換成一句摘要，
  /// 送出的內容不會一輪比一輪長。
  ///
  /// 第一回試抓過、但試抓用完還沒修好時，傳回這一回試過什麼（給下一回的
  /// [earlier]）；其他結果（修好、沒過校驗、放棄、停下、第二回也沒修好）
  /// 都在這裡記好，傳回 null。
  Future<String?> _converse(AiRepairJob job, {String? earlier}) async {
    final original = job.original;
    final tried = StringBuffer();
    final messages = [
      for (final message in aiRepairOpening(
        source: original,
        checkResult: job._checkResult!,
        probe: job._probe!,
        earlier: earlier,
      ))
        (role: message.role, content: _redact(job, message.content)),
    ];
    final opening = messages.length;
    var current = sourceForAi(original);
    var tests = 0;
    var fetches = 0;
    var pushedBack = false;
    String budget() => aiRepairBudget(
      testsLeft: aiRepairMaxTests - tests,
      fetchesLeft: aiRepairMaxFetches - fetches,
    );
    for (var reply = 1; reply <= aiRepairMaxReplies; reply++) {
      final round = ++job._rounds;
      final step = _addStep(job, '第 $round 輪', detail: 'AI 回覆中…');
      final String text;
      try {
        text = await _ask!(messages, _cancelToken);
      } on AiServiceException catch (error) {
        _finish(step, error.message, failed: true);
        _fail(job, error.message);
        return null;
      } on DioException catch (error) {
        if (_stopped) return null;
        _finish(step, '連不上 AI 服務', failed: true);
        _fail(job, '連不上 AI 服務：${error.message}');
        return null;
      }
      if (_stopped) return null;
      _record('## 第 $round 輪 AI 回覆\n$text');
      _shrinkEarlierRounds(messages, opening);
      messages.add((role: 'assistant', content: text));
      void answer(String text) =>
          messages.add((role: 'user', content: _redact(job, text)));
      switch (AiRepairCommand.parse(text)) {
        case null:
          _finish(step, '讀不懂 AI 回的內容', failed: true);
          answer('${aiRepairBadReplyFor(text)}\n${budget()}');
        case AiGiveUp(:final reason) when tests == 0 && !pushedBack:
          // 還沒試過任何修改就放棄，多半是看了一眼就下結論：退回一次。
          pushedBack = true;
          _finish(step, 'AI 想放棄，請它先試一次');
          _record('AI 想放棄：$reason');
          answer('$aiRepairTryFirst\n${budget()}');
        case AiGiveUp(:final reason):
          _finish(step, 'AI 說修不好');
          _fail(job, reason.isEmpty ? 'AI 說修不好。' : 'AI：$reason');
          return null;
        case AiFetch() when fetches >= aiRepairMaxFetches:
          _finish(step, '看網頁的次數用完了', failed: true);
          answer('看網頁的次數用完了，請試抓或放棄。\n${budget()}');
        case AiFetch(:final url):
          fetches++;
          step.detail = '看網頁 $url…';
          _notify();
          final base = _candidateOrNull(original, current) ?? original;
          final page = await _guard(() => _fetchPage(base, url, _cancelToken));
          if (_stopped || page == null) return null;
          _finish(step, '看網頁 $url');
          tried.writeln('- 看了 $url');
          _record('看網頁 $url\n${_redact(job, page)}');
          answer('${aiRepairFetchReply(url, page)}\n\n${budget()}');
        case AiTest(:final change, :final note):
          final json = applyAiChange(current, change);
          final candidate = _candidateOrNull(original, json);
          if (candidate == null) {
            _finish(step, '讀不懂 AI 回的書源', failed: true);
            answer('${aiRepairBadReplyFor(text)}\n${budget()}');
            continue;
          }
          tests++;
          current = json;
          final changed = _changedText(original, candidate);
          step.detail = '$changed，試抓中…';
          _notify();
          final probe = await _guard(() => _probe(candidate, _cancelToken));
          if (_stopped || probe == null) return null;
          _record('試抓：${probe.summary}\n${_probeText(job, probe)}');
          if (probe.succeeded) {
            _finish(step, '$changed，試抓：${probe.summary}，交出');
            await _validate(job, candidate, note, probeSucceeded: true);
            return null;
          }
          _finish(step, '$changed，試抓：${probe.summary}');
          tried.writeln(
            '- ${note.isEmpty ? changed : note}（$changed）→ 試抓：${probe.summary}',
          );
          if (tests >= aiRepairMaxTests) break;
          answer('${aiRepairProbeReply(probe)}\n\n${budget()}');
        case AiSubmit(:final change, :final note):
          final json = applyAiChange(current, change);
          final candidate = _candidateOrNull(original, json);
          if (candidate == null) {
            _finish(step, '讀不懂 AI 回的書源', failed: true);
            answer('${aiRepairBadReplyFor(text)}\n${budget()}');
            continue;
          }
          _finish(step, '${_changedText(original, candidate)}，交出');
          await _validate(job, candidate, note);
          return null;
      }
      if (tests >= aiRepairMaxTests) break;
    }
    if (earlier == null && tests > 0) return tried.toString().trimRight();
    _fail(job, earlier == null ? '試了 $tests 次還沒修好，書源沒有改。' : '試了兩回還沒修好，書源沒有改。');
    return null;
  }

  /// 前面幾輪 AI 回的書源與試抓的網頁換成一句話，只留最近一輪的全文。
  static void _shrinkEarlierRounds(List<AiMessage> messages, int opening) {
    for (var i = opening; i < messages.length; i++) {
      final message = messages[i];
      if (message.role == 'assistant') {
        final note = switch (AiRepairCommand.parse(message.content)) {
          AiTest(:final change, :final note) when change.source != null => note,
          _ => null,
        };
        if (note == null) continue;
        messages[i] = (
          role: 'assistant',
          content: '{"action":"test","note":${_quote(note)}}（書源省略）',
        );
      } else {
        final firstLine = message.content.split('\n').first;
        if (firstLine.startsWith('# 試抓結果') || firstLine.startsWith('# 網頁：')) {
          messages[i] = (role: 'user', content: '$firstLine（網頁內容省略）');
        }
      }
    }
  }

  static String _quote(String text) =>
      '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', ' ')}"';

  /// 校驗 AI 交出（或貼回）的書源，通過才存進去。
  ///
  /// 試抓一路抓到了正文、校驗卻沒過時（網站限流、偶爾回慢），隔
  /// [recheckDelay] 再校驗一次。
  Future<void> _validate(
    AiRepairJob job,
    BookSource candidate,
    String note, {
    bool probeSucceeded = false,
  }) async {
    final step = _addStep(job, '校驗修好的書源');
    var checked = await _guard(() => _check(candidate, _cancelToken));
    if (_stopped) return;
    bool usable(SourceCheckIsolateResult? result) =>
        _usableFix(result, job.original, candidate);
    if (probeSucceeded && !usable(checked)) {
      step.detail = '${_checkText(checked)}；稍後再校驗一次…';
      _record('校驗修好的書源：${_checkText(checked)}，稍後再校驗一次');
      _notify();
      await Future.any<Object?>([
        Future<void>.delayed(recheckDelay),
        _cancelToken.whenCancel,
      ]);
      if (_stopped) return;
      checked = await _guard<SourceCheckIsolateResult?>(
        () => _check(candidate, _cancelToken),
      );
      if (_stopped) return;
    }
    final checkText = _checkText(checked);
    _record('校驗修好的書源：$checkText');
    if (checked == null || !usable(checked)) {
      _finish(step, checkText, failed: true);
      _fail(job, ['校驗：$checkText', if (note.isNotEmpty) 'AI：$note'].join('\n'));
      return;
    }
    job._committing = true;
    try {
      await _apply(
        BookSource.fromJson(checked.updatedSourceJson),
        job.original,
      );
    } on AiRepairConflict catch (error) {
      _finish(step, error.message, failed: true);
      _fail(job, error.message);
      return;
    } catch (error, stack) {
      AppLog.e('存 AI 修好的書源失敗', error: error, stackTrace: stack);
      _finish(step, '存不進去', failed: true);
      _fail(job, '校驗通過了，但存不進去：$error');
      return;
    } finally {
      job._committing = false;
    }
    _finish(step, checkText);
    job
      ..outcome = AiRepairOutcome.repaired
      ..repairedUrl = candidate.bookSourceUrl
      ..explanation = note.isEmpty ? null : 'AI：$note';
    _notify();
  }

  /// 校驗的結果可以存：沒問題，或只剩發現頁失效、而 AI 沒動發現的規則——
  /// 發現頁原本就壞了，搜尋與閱讀修好了還是比原本好。
  static bool _usableFix(
    SourceCheckIsolateResult? result,
    BookSource original,
    BookSource candidate,
  ) {
    if (result == null) return false;
    if (result.isHealthy) return true;
    final category = BookSource.fromJson(result.updatedSourceJson)
        .runtimeHealth
        .category;
    return _discoveryOnly.contains(category) &&
        !changedParts(original, candidate).contains('發現');
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

  /// 「複製紀錄」裡的試抓全文：遮掉秘密，最長 [_transcriptProbeLength] 字。
  String _probeText(AiRepairJob job, SourceProbeReport probe) {
    final text = _redact(job, probe.fullText);
    return text.length <= _transcriptProbeLength
        ? text
        : '${text.substring(0, _transcriptProbeLength)}…（以下省略）';
  }

  static const int _transcriptProbeLength = 20000;

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
    _record('沒修好：$explanation');
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

  void _record(String text) => _transcript
    ..writeln(text)
    ..writeln();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }

  static const Set<SourceHealthCategory> _unfixable = {
    SourceHealthCategory.upstreamUnstable,
    SourceHealthCategory.loginRequired,
    SourceHealthCategory.verificationRequired,
    SourceHealthCategory.downloadOnly,
    SourceHealthCategory.nonNovel,
  };

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

  static Future<SourceCheckIsolateResult?> _defaultCheck(
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
    CancelToken cancelToken,
  ) async {
    final config = await _config();
    return probeSource(
      source,
      keyword: source.getCheckKeyword(config.keyword),
      timeout: config.sourceTimeoutDuration,
      cancelToken: cancelToken,
    );
  }

  static Future<String> _defaultFetchPage(
    BookSource source,
    String url,
    CancelToken cancelToken,
  ) async {
    final config = await _config();
    return fetchPageForAi(
      source,
      url,
      timeout: config.sourceTimeoutDuration,
      cancelToken: cancelToken,
    );
  }

  static AiRepairAsker _defaultAsk(AiService service) {
    final client = AiChatClient(service);
    return (messages, cancelToken) =>
        client.complete(messages, cancelToken: cancelToken);
  }

  static Future<void> _defaultCopy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  /// 存修好的書源。修的這段時間書源被刪掉或改過（例如同步）時不存：存了會
  /// 蓋掉別處的改動、或把刪掉的書源加回來。AI 換了網址開頭時照書源編輯
  /// 改網址的做法搬過去，書架上的書跟著搬；新網址已經有別的書源時不存。
  Future<void> _defaultApply(BookSource repaired, BookSource original) async {
    final dao = getIt<BookSourceDao>();
    final current = await dao.getByUrl(original.bookSourceUrl);
    if (current == null) {
      throw const AiRepairConflict('修的這段時間書源被刪掉了，沒有存。');
    }
    if (changedParts(original, current).isNotEmpty ||
        current.bookSourceName != original.bookSourceName) {
      throw const AiRepairConflict('修的這段時間書源被改過了（例如同步），沒有存。');
    }
    final moved = repaired.bookSourceUrl != original.bookSourceUrl;
    if (moved && await dao.getByUrl(repaired.bookSourceUrl) != null) {
      throw AiRepairConflict('新網址 ${repaired.bookSourceUrl} 已經有別的書源，沒有存。');
    }
    await _backups.put(repaired.bookSourceUrl, current.toJson());
    await BookSourceService().saveEditedSource(
      repaired,
      previousUrl: moved ? original.bookSourceUrl : null,
    );
  }
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
Future<void> restoreAiRepair(
  String sourceUrl, {
  AiRepairBackups? backups,
}) async {
  final store = backups ?? AiRepairBackups.instance;
  final json = await store.get(sourceUrl);
  if (json == null) return;
  // 書源已經刪掉了（例如另一台同步刪的）：不還原，免得把它加回來。
  if (await getIt<BookSourceDao>().getByUrl(sourceUrl) == null) {
    await store.remove(sourceUrl);
    return;
  }
  final previous = BookSource.fromJson(json);
  await BookSourceService().saveEditedSource(
    previous,
    previousUrl: previous.bookSourceUrl == sourceUrl ? null : sourceUrl,
  );
  await store.remove(sourceUrl);
}

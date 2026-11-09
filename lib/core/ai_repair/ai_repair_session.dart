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

  /// 給 AI 與剪貼簿用的現況：原本的校驗結果與試抓。
  String? _checkResult;
  SourceProbeReport? _probe;
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
    Future<void> Function(BookSource repaired)? apply,
    Future<void> Function(String text)? copy,
    AiRepairBackups? backups,
  }) : assert(service != null || sources.length == 1),
       jobs = [for (final source in sources) AiRepairJob(source)],
       _check = check ?? _defaultCheck,
       _probe = probe ?? _defaultProbe,
       _ask = ask ?? (service == null ? null : _defaultAsk(service)),
       _copy = copy ?? _defaultCopy,
       _backups = backups ?? AiRepairBackups.instance {
    _apply = apply ?? _defaultApply;
  }

  /// 使用者的 AI 服務；null 時用剪貼簿。
  final AiService? service;
  final List<AiRepairJob> jobs;
  final AiRepairChecker _check;
  final AiRepairProber _probe;
  final AiRepairAsker? _ask;
  final Future<void> Function(String text) _copy;
  final AiRepairBackups _backups;
  late final Future<void> Function(BookSource repaired) _apply;

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
    final json = pastedSourceJson(text);
    if (json == null) return '讀不出書源 JSON';
    job.awaitingPaste = false;
    _running = true;
    _notify();
    try {
      _record('## 貼回的書源\n$text');
      await _validate(job, candidateFrom(job.original, json), '');
    } finally {
      _running = false;
      _notify();
    }
    return null;
  }

  /// 修好之後還原成改前的版本。
  Future<void> restore(AiRepairJob job) async {
    if (job.outcome != AiRepairOutcome.repaired || job.restored) return;
    await restoreAiRepair(job.original.bookSourceUrl, backups: _backups);
    job.restored = true;
    _notify();
  }

  Future<void> _repair(AiRepairJob job) async {
    final original = job.original;
    _record('# ${original.bookSourceName}（${original.bookSourceUrl}）');

    final checkStep = _addStep(job, '校驗原本的書源');
    final checked = await _guard(() => _check(original, _cancelToken));
    if (_stopped) return;
    final health = checked == null
        ? null
        : BookSource.fromJson(checked.updatedSourceJson).runtimeHealth;
    final checkText = _checkText(checked);
    job._checkResult = [checkText, ...?checked?.diagnostics].join('\n\n');
    _finish(checkStep, checkText);
    _record('校驗原本的書源：$checkText');

    if (jobs.length > 1 && health != null) {
      final skip = health.category == SourceHealthCategory.healthy
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
    _record('抓網頁：${_fetchText(probe)}');

    if (usesClipboard) {
      await _copy(
        aiRepairClipboardPrompt(
          source: original,
          checkResult: job._checkResult!,
          probe: probe,
        ),
      );
      _finish(_addStep(job, '已複製給 AI'), null);
      job.awaitingPaste = true;
      _notify();
      return;
    }
    await _converse(job);
  }

  /// 和 AI 來回：每一輪 AI 回一個指令，試抓的結果回給它，直到交出、放棄或
  /// 輪數用完。只留最近一輪的書源與網頁全文，前面的換成一句摘要，送出的
  /// 內容不會一輪比一輪長。
  Future<void> _converse(AiRepairJob job) async {
    final original = job.original;
    final messages = aiRepairOpening(
      source: original,
      checkResult: job._checkResult!,
      probe: job._probe!,
    );
    final opening = messages.length;
    for (var round = 1; round <= aiRepairMaxRounds; round++) {
      final step = _addStep(job, '第 $round 輪', detail: 'AI 回覆中…');
      final String reply;
      try {
        reply = await _ask!(messages, _cancelToken);
      } on AiServiceException catch (error) {
        _finish(step, error.message, failed: true);
        _fail(job, error.message);
        return;
      } on DioException catch (error) {
        if (_stopped) return;
        _finish(step, '連不上 AI 服務', failed: true);
        _fail(job, '連不上 AI 服務：${error.message}');
        return;
      }
      if (_stopped) return;
      _record('## 第 $round 輪 AI 回覆\n$reply');
      _shrinkEarlierRounds(messages, opening);
      messages.add((role: 'assistant', content: reply));
      final roundsLeft = aiRepairMaxRounds - round;
      switch (AiRepairCommand.parse(reply)) {
        case null:
          _finish(step, '讀不懂 AI 回的內容', failed: true);
          messages.add((role: 'user', content: aiRepairBadReply));
        case AiGiveUp(:final reason):
          _finish(step, 'AI 說修不好');
          _fail(job, reason.isEmpty ? 'AI 說修不好。' : 'AI：$reason');
          return;
        case AiTest(:final source):
          final candidate = candidateFrom(original, source);
          final changed = _changedText(original, candidate);
          step.detail = '$changed，試抓中…';
          _notify();
          final probe = await _guard(() => _probe(candidate, _cancelToken));
          if (_stopped || probe == null) return;
          _finish(step, '$changed，試抓：${probe.summary}');
          _record('試抓：${probe.summary}');
          messages.add((
            role: 'user',
            content: aiRepairProbeReply(probe, roundsLeft: roundsLeft),
          ));
        case AiSubmit(:final source, :final note):
          final candidate = candidateFrom(original, source);
          _finish(step, '${_changedText(original, candidate)}，交出');
          await _validate(job, candidate, note);
          return;
      }
    }
    _fail(job, '試了 $aiRepairMaxRounds 輪還沒修好，書源沒有改。');
  }

  /// 前面幾輪 AI 回的書源與試抓的網頁換成一句話，只留最近一輪的全文。
  static void _shrinkEarlierRounds(List<AiMessage> messages, int opening) {
    for (var i = opening; i < messages.length; i++) {
      final message = messages[i];
      if (message.role == 'assistant') {
        final note = switch (AiRepairCommand.parse(message.content)) {
          AiTest(:final note) => note,
          _ => null,
        };
        if (note == null) continue;
        messages[i] = (
          role: 'assistant',
          content: '{"action":"test","note":${_quote(note)}}（書源省略）',
        );
      } else {
        final firstLine = message.content.split('\n').first;
        if (firstLine.startsWith('# 試抓結果')) {
          messages[i] = (role: 'user', content: '$firstLine（網頁內容省略）');
        }
      }
    }
  }

  static String _quote(String text) =>
      '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', ' ')}"';

  /// 校驗 AI 交出（或貼回）的書源，通過才存進去。
  Future<void> _validate(
    AiRepairJob job,
    BookSource candidate,
    String note,
  ) async {
    final step = _addStep(job, '校驗修好的書源');
    final checked = await _guard(() => _check(candidate, _cancelToken));
    if (_stopped) return;
    final checkText = _checkText(checked);
    _record('校驗修好的書源：$checkText');
    if (checked == null || !checked.isHealthy) {
      _finish(step, checkText, failed: true);
      _fail(job, ['校驗：$checkText', if (note.isNotEmpty) 'AI：$note'].join('\n'));
      return;
    }
    try {
      await _apply(BookSource.fromJson(checked.updatedSourceJson));
    } catch (error, stack) {
      AppLog.e('存 AI 修好的書源失敗', error: error, stackTrace: stack);
      _finish(step, '存不進去', failed: true);
      _fail(job, '校驗通過了，但存不進去：$error');
      return;
    }
    _finish(step, checkText);
    job
      ..outcome = AiRepairOutcome.repaired
      ..explanation = note.isEmpty ? null : 'AI：$note';
    _notify();
  }

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

  static AiRepairAsker _defaultAsk(AiService service) {
    final client = AiChatClient(service);
    return (messages, cancelToken) =>
        client.complete(messages, cancelToken: cancelToken);
  }

  static Future<void> _defaultCopy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  Future<void> _defaultApply(BookSource repaired) async {
    final current = await getIt<BookSourceDao>().getByUrl(
      repaired.bookSourceUrl,
    );
    if (current != null) {
      await _backups.put(current.bookSourceUrl, current.toJson());
    }
    await BookSourceService().saveEditedSource(repaired);
  }
}

/// 把書源還原成 AI 改之前的那份，並刪掉留著的改前版本。
Future<void> restoreAiRepair(
  String sourceUrl, {
  AiRepairBackups? backups,
}) async {
  final store = backups ?? AiRepairBackups.instance;
  final json = await store.get(sourceUrl);
  if (json == null) return;
  await BookSourceService().saveEditedSource(BookSource.fromJson(json));
  await store.remove(sourceUrl);
}

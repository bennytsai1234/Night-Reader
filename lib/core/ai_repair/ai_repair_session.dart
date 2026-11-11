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
import 'package:night_reader/core/services/crash_trail.dart';
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
enum AiRepairOutcome { repaired, failed }

/// 一個書源的修復：做過的步驟與結果。
class AiRepairJob {
  AiRepairJob(this.original);

  final BookSource original;
  final List<AiRepairStep> steps = [];
  AiRepairOutcome? outcome;

  /// 結果的說明：AI 最後說的話，或卡在哪。
  String? explanation;

  /// AI 明確放棄，或第二回的試抓次數用完（含最後一次交出沒過校驗）時才標
  /// 「AI 修不好」；網路、金鑰、系統錯誤、校驗超過時間，以及空白或讀不懂的
  /// 回覆把回覆次數用完的都不標。
  bool confirmedUnfixable = false;

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

/// 搜尋結果跟關鍵字有沒有關係（[searchFollowsKeyword]）。
typedef AiRepairKeywordCheck = Future<bool> Function(
  BookSource source,
  CancelToken cancelToken,
);

/// 問 AI 一次。
typedef AiRepairAsker = Future<String> Function(
  List<AiMessage> messages,
  CancelToken cancelToken,
);

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
    Future<void> Function(BookSource repaired, BookSource original)? apply,
    Future<void> Function(String text)? copy,
    AiRepairBackups? backups,
    Future<Set<String>> Function(BookSource source)? secrets,
    this.recheckDelay = const Duration(seconds: 30),
    bool Function()? hasBudget,
    void Function(AiUsage usage)? onUsage,
  }) : job = AiRepairJob(source),
       _check = check ?? defaultCheck,
       _probe = probe ?? _defaultProbe,
       _fetchPage = fetchPage ?? _defaultFetchPage,
       _keywordCheck = keywordCheck ?? _defaultKeywordCheck,
       _ask = ask ?? (service == null ? null : _defaultAsk(service, onUsage)),
       _hasBudget = hasBudget ?? _always,
       _copy = copy ?? _defaultCopy,
       _secretsOf = secrets ?? aiRepairSecretsOf,
       _backups = backups ?? AiRepairBackups.instance {
    _apply =
        apply ??
        (repaired, original) =>
            saveRepairedSource(repaired, original, backups: _backups);
  }

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
  final AiRepairAsker? _ask;
  final Future<void> Function(String text) _copy;
  final Future<Set<String>> Function(BookSource source) _secretsOf;
  final AiRepairBackups _backups;
  late final Future<void> Function(BookSource repaired, BookSource original)
  _apply;

  final CancelToken _cancelToken = CancelToken();
  final StringBuffer _transcript = StringBuffer();
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

  /// 「複製紀錄」：每一步、AI 每一輪說的話與試抓結果。
  String get transcript => _transcript.toString().trimRight();

  /// 有紀錄可以複製。
  bool get hasTranscript => _transcript.isNotEmpty;

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
      _record('## 貼回的書源\n$text');
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
    _record('# ${original.bookSourceName}（${original.bookSourceUrl}）');
    job._secrets = await _secretsOf(original);
    if (_stopped) return;

    final checkStep = _addStep(job, '校驗原本的書源');
    final checked = await _guard(() => _check(original, _cancelToken));
    if (_stopped) return;
    final checkText = _checkText(checked);
    job._before = checked == null
        ? null
        : BookSource.fromJson(checked.updatedSourceJson).runtimeHealth.category;
    job._checkResult = _redact(
      job,
      [checkText, ...?checked?.diagnostics].join('\n\n'),
    );
    _finish(checkStep, checkText);
    _record('校驗原本的書源：${job._checkResult}');

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
  /// 用掉試抓的機會。對話照原樣一路接下去，前面的內容不改寫：AI 要靠前面
  /// 看過的網頁推下一步，開頭不變也讓服務的快取打得中。
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
    var current = sourceForAi(original);
    var tests = 0;
    var fetches = 0;
    var pushedBack = false;
    String budget() => aiRepairBudget(
      testsLeft: aiRepairMaxTests - tests,
      fetchesLeft: aiRepairMaxFetches - fetches,
    );
    for (var reply = 1; reply <= aiRepairMaxReplies; reply++) {
      if (!_hasBudget()) {
        _fail(job, '花費到了上限，沒修完，書源沒有改。');
        return null;
      }
      final round = ++job._rounds;
      final step = _addStep(job, '第 $round 輪', detail: 'AI 回覆中…');
      final String text;
      try {
        text = await _ask!(messages, _cancelToken);
      } on AiEmptyReply catch (error) {
        // 空白回覆不放進對話，同樣的話再問一次。
        _finish(step, error.message, failed: true);
        continue;
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
          job.confirmedUnfixable = true;
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
          final what = '- ${note.isEmpty ? changed : note}（$changed）';
          if (probe.succeeded) {
            _finish(step, '$changed，試抓：${probe.summary}，交出');
            final failure = await _validate(
              job,
              candidate,
              note,
              probeSucceeded: true,
              last: tests >= aiRepairMaxTests,
              lastRound: earlier != null,
            );
            if (failure == null) return null;
            tried.writeln('$what → 試抓到正文，但校驗沒過：${_firstLine(failure)}');
            answer('$failure\n\n${budget()}');
            continue;
          }
          _finish(step, '$changed，試抓：${probe.summary}');
          tried.writeln('$what → 試抓：${probe.summary}');
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
          tests++;
          current = json;
          final changed = _changedText(original, candidate);
          _finish(step, '$changed，交出');
          final failure = await _validate(
            job,
            candidate,
            note,
            last: tests >= aiRepairMaxTests,
            lastRound: earlier != null,
          );
          if (failure == null) return null;
          tried.writeln(
            '- ${note.isEmpty ? changed : note}（$changed）→ 交出，校驗沒過：'
            '${_firstLine(failure)}',
          );
          answer('$failure\n\n${budget()}');
      }
      if (tests >= aiRepairMaxTests) break;
    }
    if (earlier == null && tests > 0) return tried.toString().trimRight();
    if (earlier != null && tests >= aiRepairMaxTests) {
      job.confirmedUnfixable = true;
    }
    _fail(job, earlier == null ? '試了 $tests 次還沒修好，書源沒有改。' : '試了兩回還沒修好，書源沒有改。');
    return null;
  }

  /// 校驗 AI 交出（或貼回）的書源，通過才存進去。
  ///
  /// 試抓一路抓到了正文、校驗卻沒過時（網站限流、偶爾回慢），隔
  /// [recheckDelay] 再校驗一次。
  ///
  /// 沒通過時：[last]（AI 沒機會再改了）就記成沒修好，傳回 null；不然傳回
  /// 要回給 AI 的校驗結果，讓它接著改。修好、存不進去或停下時是 null。
  /// [lastRound] 時最後一次沒過就是兩回都試完了，標「AI 修不好」（校驗超過
  /// 時間除外）。
  Future<String?> _validate(
    AiRepairJob job,
    BookSource candidate,
    String note, {
    bool probeSucceeded = false,
    bool last = true,
    bool lastRound = false,
  }) async {
    final step = _addStep(job, '校驗修好的書源');
    var checked = await _guard(() => _check(candidate, _cancelToken));
    if (_stopped) return null;
    bool usable(SourceCheckIsolateResult? result) =>
        usableFix(result, job.original, candidate, before: job._before);
    if (probeSucceeded && !usable(checked)) {
      step.detail = '${_checkText(checked)}；稍後再校驗一次…';
      _record('校驗修好的書源：${_checkText(checked)}，稍後再校驗一次');
      _notify();
      await Future.any<Object?>([
        Future<void>.delayed(recheckDelay),
        _cancelToken.whenCancel,
      ]);
      if (_stopped) return null;
      checked = await _guard<SourceCheckIsolateResult?>(
        () => _check(candidate, _cancelToken),
      );
      if (_stopped) return null;
    }
    final checkText = _checkText(checked);
    _record('校驗修好的書源：$checkText');
    if (checked == null || !usable(checked)) {
      _finish(step, checkText, failed: true);
      if (!last) {
        return _redact(
          job,
          aiRepairCheckReply(checkText, checked?.diagnostics ?? const []),
        );
      }
      // 校驗超過時間不算修不好：可能只是網站一時慢。
      job.confirmedUnfixable = lastRound && checked != null;
      _fail(job, ['校驗：$checkText', if (note.isNotEmpty) 'AI：$note'].join('\n'));
      return null;
    }
    // 校驗只看搜尋有沒有回書：規則抓的是頁面上固定的推薦書也會過。
    step.detail = '$checkText；確認搜尋結果跟關鍵字有關…';
    _notify();
    final follows = await _guard(() => _keywordCheck(candidate, _cancelToken));
    if (_stopped) return null;
    if (follows == false) {
      const unrelated = '搜尋結果跟關鍵字無關：搜一個不可能有的詞也回同樣的書，抓到的是頁面上固定的推薦書';
      _record('校驗修好的書源：$unrelated');
      _finish(step, unrelated, failed: true);
      if (!last) {
        return '# 書源校驗沒過：$unrelated（用「$nonsenseKeyword」搜尋也得到同樣的書）。'
            '要抓的是搜尋結果；網站真的搜不到書時就放棄。';
      }
      job.confirmedUnfixable = lastRound;
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
    _notify();
    return null;
  }

  static String _firstLine(String text) => text.split('\n').first;

  /// 校驗的結果可以存：沒問題；或原本搜尋、閱讀有壞（[before] 不是只壞
  /// 發現頁），現在只剩發現頁失效、而 AI 沒動發現的規則——發現頁原本就壞
  /// 了，搜尋與閱讀修好了還是比原本好。原本就只壞發現頁、或不知道原本壞在
  /// 哪（[before] 是 null）的，要整個沒問題才算。
  static bool usableFix(
    SourceCheckIsolateResult? result,
    BookSource original,
    BookSource candidate, {
    required SourceHealthCategory? before,
  }) {
    if (result == null) return false;
    if (result.isHealthy) return true;
    if (before == null || _discoveryOnly.contains(before)) return false;
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

  /// 記進「複製紀錄」：一律先遮掉登入資料、Cookie 與變數的值（ADR 0054）。
  void _record(String text) => _transcript
    ..writeln(redactAiRepairSecrets(text, job._secrets))
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

  static Future<String> _defaultFetchPage(
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

  static AiRepairAsker _defaultAsk(
    AiService service,
    void Function(AiUsage usage)? onUsage,
  ) {
    final client = AiChatClient(service);
    return (messages, cancelToken) =>
        client.complete(messages, cancelToken: cancelToken, onUsage: onUsage);
  }

  static Future<void> _defaultCopy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
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

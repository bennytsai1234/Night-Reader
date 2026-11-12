import 'dart:async';

import 'package:dio/dio.dart';

import 'ai_chat_client.dart';

/// 和任務無關的 AI 迴圈（`agent-harness` 技能「做迴圈」）：程式把一件事交給
/// AI，AI 每輪回一個指令，程式執行、把結果接在對話最後，直到交出的東西通過
/// 驗收。任務相關的部分（開場、怎麼讀指令、怎麼執行與驗收）由 [AgentTask]
/// 提供，AI 修書源是第一個任務。
///
/// 一律照做的機制：
/// - 執行中只回事實：結果後面附上跑的狀態（同樣的參數第幾次、剩幾輪），
///   不附指示。這輪沒有結果可接（沒有指令、讀不懂）時才另發一句。
/// - 卡住（[AiStalled]）：同一段對話原封不動重送；連續卡住
///   [AiAgentKnobs.stallLimit] 次就整件重跑。
/// - 失控（[AiRunaway]）、可重試的服務錯誤、未收斂：整件用全新的對話與工具
///   狀態重跑，含第一次最多 [AiAgentKnobs.attempts] 次，仍不行是
///   [AgentEndKind.unconfirmed]。
/// - 每件都有結果：完成、無法確認、取消，或服務出了重跑也不會好的錯
///   （金鑰、網址、額度）、整批的用量上限到了。
abstract class AgentTask<C> {
  /// 每次（含重跑）的開場：系統提示與這一件的第一則訊息。
  List<AiMessage> opening();

  /// 整件重跑前把工具的狀態清掉（抓過的頁、改到一半的書源）。[attempt] 是
  /// 接著要跑的第幾次，[why] 是上一次為什麼沒跑完。
  void restart(int attempt, String why);

  /// 讀出 AI 這輪回的指令。
  AgentParse<C> parse(String reply);

  /// 執行一個指令；傳回的文字是要接進對話的事實，秘密已經遮掉。
  Future<AgentResult> execute(C command);

  /// 一輪開始：第 [attempt] 次的第 [round] 輪（每次從 1 數起）；[messages]
  /// 是這輪要送出的全部對話。
  void roundStarted(int attempt, int round, List<AiMessage> messages) {}

  /// 一輪問完：成功時有 [reply]，沒有時 [error] 說出了什麼事。
  void roundEnded(AgentRoundRecord record) {}

  /// 接進對話、但不是工具結果的一句（沒有指令、讀不懂、這輪的狀態）。
  void factAdded(String fact) {}
}

/// 一輪問 AI 的紀錄（寫進修復紀錄）。[usage] 是這輪的用量：回完的照服務
/// 回報的；沒回完就斷了的是估的（[AiServiceException.usage]），[estimated]
/// 是 true。
typedef AgentRoundRecord = ({
  int attempt,
  int round,
  int sentMessages,
  int sentChars,
  AiReply? reply,
  AiUsage? usage,
  bool estimated,
  Duration elapsed,
  String? error,
});

/// AI 這輪回的話讀出來的樣子。
sealed class AgentParse<C> {
  const AgentParse();
}

/// 讀得懂的指令；[key] 是指令與參數（不含說明），一樣的參數一樣的 key。
final class AgentCommand<C> extends AgentParse<C> {
  const AgentCommand(this.command, this.key);
  final C command;
  final String key;
}

/// 回覆裡沒有指令（[fact] 說看到什麼）。
final class AgentNoCommand<C> extends AgentParse<C> {
  const AgentNoCommand(this.fact);
  final String fact;
}

/// 有指令但讀不懂：JSON 不合法、少了欄位（[fact] 說哪裡不對）。
final class AgentBadCommand<C> extends AgentParse<C> {
  const AgentBadCommand(this.fact);
  final String fact;
}

/// 執行一個指令的結果。
sealed class AgentResult {
  const AgentResult();
}

/// 工具的結果，接進對話。[same] 是拿來比「結果與前幾次相同」的那一份
/// （例如去掉每次都不同的頁碼）；沒給時比 [text]。
final class AgentToolResult extends AgentResult {
  const AgentToolResult(this.text, {this.same});
  final String text;
  final String? same;
}

/// 參數讀得懂 JSON、但內容用不了（例如改過的書源組不起來）：和讀不懂的指令
/// 一起數。
final class AgentInvalid extends AgentResult {
  const AgentInvalid(this.fact);
  final String fact;
}

/// 交出的東西沒過驗收：[reason] 是具體原因，接進對話。
final class AgentRejected extends AgentResult {
  const AgentRejected(this.reason);
  final String reason;
}

/// 交出的東西通過驗收（或確定的放棄被接受），這件做完。
final class AgentAccepted extends AgentResult {
  const AgentAccepted();
}

/// 做到一半停下了（使用者按停止），或任務自己結束了這件（例如存不進去）。
final class AgentStopped extends AgentResult {
  const AgentStopped(this.kind, this.reason);
  final AgentEndKind kind;
  final String reason;
}

enum AgentEndKind {
  /// 交出的通過驗收，或放棄被接受。
  completed,

  /// 重跑到上限還是沒收斂、卡住或失控。
  unconfirmed,

  /// 使用者停下。
  cancelled,

  /// 重跑也不會好的錯（金鑰、網址、額度），或整批的用量上限到了。
  failed,
}

/// 一件的結果與統計（修復紀錄的「統計」、評估表的一列）。
final class AgentEnd {
  AgentEnd(this.kind, this.reason, this.stats);

  final AgentEndKind kind;

  /// 怎麼結束的，一句話。
  final String reason;
  final AgentStats stats;
}

/// 一件跑下來的數字。
final class AgentStats {
  int attempts = 1;
  int rounds = 0;
  int toolCalls = 0;
  int rejections = 0;
  int badCommands = 0;
  int noCommands = 0;
  int stalls = 0;
  int prompt = 0;
  int cached = 0;
  int completion = 0;
  int reasoning = 0;
  Duration model = Duration.zero;
  Duration tools = Duration.zero;
  final Stopwatch _clock = Stopwatch()..start();

  /// 每次沒跑完的原因，照順序。
  final List<String> restarts = [];

  Duration get total => _clock.elapsed;
  Duration get other => total - model - tools;

  void add(AiUsage usage) {
    prompt += usage.prompt;
    cached += usage.cached;
    completion += usage.completion;
    reasoning += usage.reasoning;
  }

  Map<String, Object?> toMap() => {
    'attempts': attempts,
    'rounds': rounds,
    'toolCalls': toolCalls,
    'rejections': rejections,
    'badCommands': badCommands,
    'noCommands': noCommands,
    'stalls': stalls,
    'prompt': prompt,
    'cached': cached,
    'completion': completion,
    'reasoning': reasoning,
    'modelMs': model.inMilliseconds,
    'toolsMs': tools.inMilliseconds,
    'otherMs': other.inMilliseconds,
    'restarts': restarts,
  };
}

/// 問 AI 一次（[AiChatClient.complete]）。
typedef AgentAsk = Future<AiReply> Function(
  List<AiMessage> messages,
  CancelToken cancelToken,
);

/// 跑一件：照 [AgentTask] 開場，一輪一輪問 [ask]，直到有結果。
/// [cancelToken] 取消時是 [AgentEndKind.cancelled]；[hasBudget] 不再成立時
/// 不再問，是 [AgentEndKind.failed]。[attempts] 是含第一次最多跑幾次。
Future<AgentEnd> runAgent<C>(
  AgentTask<C> task, {
  required AgentAsk ask,
  required CancelToken cancelToken,
  bool Function()? hasBudget,
  int attempts = AiAgentKnobs.attempts,
}) async {
  final stats = AgentStats();
  AgentEnd end(AgentEndKind kind, String reason) =>
      AgentEnd(kind, reason, stats);

  for (var attempt = 1; ; attempt++) {
    stats.attempts = attempt;
    final why = await _attempt(
      task,
      attempt,
      stats,
      ask,
      cancelToken,
      hasBudget,
    );
    switch (why) {
      case _Finished(:final kind, :final reason):
        return end(kind, reason);
      case _Retry(:final reason):
        stats.restarts.add(reason);
        if (attempt >= attempts) {
          return end(
            AgentEndKind.unconfirmed,
            attempt == 1 ? '沒有結果：$reason' : '跑了 $attempt 次都沒有結果，最後一次：$reason',
          );
        }
        task.restart(attempt + 1, reason);
    }
  }
}

sealed class _AttemptEnd {
  const _AttemptEnd();
}

final class _Finished extends _AttemptEnd {
  const _Finished(this.kind, this.reason);
  final AgentEndKind kind;
  final String reason;
}

/// 這次沒跑完、整件重跑：卡住、失控、可重試的服務錯誤、未收斂。
final class _Retry extends _AttemptEnd {
  const _Retry(this.reason);
  final String reason;
}

Future<_AttemptEnd> _attempt<C>(
  AgentTask<C> task,
  int attempt,
  AgentStats stats,
  AgentAsk ask,
  CancelToken cancelToken,
  bool Function()? hasBudget,
) async {
  final messages = [...task.opening()];
  var round = 0;
  var noCommand = 0;
  var badCommand = 0;
  var rejections = 0;
  var stalls = 0;
  final calls = <String, int>{};
  final lastResult = <String, String>{};
  const cancelled = _Finished(AgentEndKind.cancelled, '已停止');

  /// 這輪的狀態，附在結果後面：快用完時剩幾輪。
  String status() {
    final left = AiAgentKnobs.maxRounds - round;
    return left <= AiAgentKnobs.warnRoundsLeft ? '\n\n（剩 $left 輪）' : '';
  }

  void fact(String text) {
    final line = '$text${status()}';
    messages.add((role: 'user', content: line));
    task.factAdded(line);
  }

  while (true) {
    if (cancelToken.isCancelled) return cancelled;
    if (!(hasBudget?.call() ?? true)) {
      return const _Finished(AgentEndKind.failed, '整批的 AI 用量到了上限');
    }
    if (round >= AiAgentKnobs.maxRounds) {
      return _Retry('用完 ${AiAgentKnobs.maxRounds} 輪還沒交出');
    }
    round++;
    stats.rounds++;
    task.roundStarted(attempt, round, messages);
    final sentChars = messages.fold(0, (sum, m) => sum + m.content.length);
    final watch = Stopwatch()..start();
    void record({AiReply? reply, AiServiceException? failure, String? error}) {
      stats.model += watch.elapsed;
      final usage = reply?.usage ?? failure?.usage;
      if (usage != null) stats.add(usage);
      task.roundEnded((
        attempt: attempt,
        round: stats.rounds,
        sentMessages: messages.length,
        sentChars: sentChars,
        reply: reply,
        usage: usage,
        estimated: reply == null && usage != null,
        elapsed: watch.elapsed,
        error: error ?? failure?.message,
      ));
    }

    final AiReply reply;
    try {
      reply = await ask(messages, cancelToken);
    } on AiStalled catch (error) {
      record(failure: error);
      if (cancelToken.isCancelled) return cancelled;
      stats.stalls++;
      if (++stalls >= AiAgentKnobs.stallLimit) {
        return _Retry('連續卡住 $stalls 次：${error.message}');
      }
      continue;
    } on AiRunaway catch (error) {
      record(failure: error, error: '${error.message}\n${error.tail}');
      return _Retry(error.message);
    } on AiEmptyReply catch (error) {
      // 空白的回覆不放進對話，同一段對話再問一次。
      record(failure: error);
      stats.noCommands++;
      if (++noCommand >= AiAgentKnobs.noCommandLimit) {
        return _Retry('連續 $noCommand 輪沒有收到指令');
      }
      continue;
    } on AiServiceException catch (error) {
      record(failure: error);
      if (cancelToken.isCancelled) return cancelled;
      if (error.retryable) return _Retry(error.message);
      return _Finished(AgentEndKind.failed, error.message);
    } on DioException catch (error) {
      record(error: '$error');
      if (cancelToken.isCancelled || CancelToken.isCancel(error)) {
        return cancelled;
      }
      return _Retry('連不上 AI 服務：${error.message}');
    }
    record(reply: reply);
    stalls = 0;
    if (cancelToken.isCancelled) return cancelled;
    messages.add((role: 'assistant', content: reply.content));

    switch (task.parse(reply.content)) {
      case AgentNoCommand(fact: final text):
        stats.noCommands++;
        if (++noCommand >= AiAgentKnobs.noCommandLimit) {
          return _Retry('連續 $noCommand 輪沒有收到指令');
        }
        fact(text);
      case AgentBadCommand(fact: final text):
        noCommand = 0;
        stats.badCommands++;
        if (++badCommand >= AiAgentKnobs.badCommandLimit) {
          return _Retry('連續 $badCommand 輪的指令讀不懂');
        }
        fact(text);
      case AgentCommand(:final command, :final key):
        noCommand = 0;
        final count = calls[key] = (calls[key] ?? 0) + 1;
        if (count >= AiAgentKnobs.sameCallLimit) {
          return _Retry('同樣的指令與參數第 $count 次');
        }
        stats.toolCalls++;
        final toolWatch = Stopwatch()..start();
        final result = await task.execute(command);
        stats.tools += toolWatch.elapsed;
        if (cancelToken.isCancelled) return cancelled;
        switch (result) {
          case AgentAccepted():
            return const _Finished(AgentEndKind.completed, '交出的通過了');
          case AgentStopped(:final kind, :final reason):
            return _Finished(kind, reason);
          case AgentInvalid(fact: final text):
            stats.badCommands++;
            if (++badCommand >= AiAgentKnobs.badCommandLimit) {
              return _Retry('連續 $badCommand 輪的指令讀不懂');
            }
            fact(text);
          case AgentRejected(:final reason):
            badCommand = 0;
            stats.rejections++;
            // 交出之間的查證不重算：數的是交出的那幾次連續被退。
            if (++rejections >= AiAgentKnobs.rejectionLimit) {
              return _Retry('交出連續被退 $rejections 次');
            }
            fact('$reason${_repeated(count, lastResult, key, reason)}');
          case AgentToolResult(:final text, :final same):
            badCommand = 0;
            fact('$text${_repeated(count, lastResult, key, same ?? text)}');
        }
    }
  }
}

/// 同樣的指令與參數又來一次時附上的狀態。
String _repeated(
  int count,
  Map<String, String> lastResult,
  String key,
  String result,
) {
  final previous = lastResult[key];
  lastResult[key] = result;
  if (count < 2) return '';
  return '\n\n（這是同樣參數的第 $count 次，'
      '${previous == result ? '結果與前幾次相同' : '結果和上一次不同'}）';
}

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import 'ai_chat_client.dart';

/// 和任務無關的 AI 迴圈（`agent-harness` 技能「做迴圈」）：程式把一件事交給
/// AI，AI 每輪呼叫工具（服務的 function calling），程式執行、把每個呼叫的
/// 結果接在對話最後，直到交出的東西通過驗收。任務相關的部分（開場、怎麼讀指令、怎麼執行與驗收）由 [AgentTask]
/// 提供，AI 修書源是第一個任務。
///
/// 一律照做的機制：
/// - 接進對話的每一句（開場、工具結果、狀態）先經過 [AgentTask.redact]。
/// - 執行中只回事實：結果後面附上跑的狀態（同樣的參數第幾次、剩幾輪），
///   不附指示。每個呼叫都有一句工具結果（參數讀不懂的也回哪裡不對）；這輪
///   沒有呼叫工具時才另發一句。
/// - 卡住（[AiStalled]）：同一段對話原封不動重送；連續卡住
///   [AiAgentKnobs.stallLimit] 次就整件重跑。
/// - 失控（[AiRunaway]）、可重試的服務錯誤、未收斂：整件用全新的對話與工具
///   狀態重跑，含第一次最多 [AiAgentKnobs.attempts] 次，仍不行是
///   [AgentEndKind.unconfirmed]。
/// - 每件都有結果：完成、無法確認、取消，或服務出了重跑也不會好的錯
///   （金鑰、網址、額度）。
abstract class AgentTask<C> {
  /// 每次（含重跑）的開場：系統提示與這一件的第一則訊息。
  List<AiMessage> opening();

  /// 接進對話前遮掉秘密（金鑰、Cookie、登入資料）：開場與每一句事實都經過
  /// 這裡，新加的工具不用自己遮（`agent-harness` 技能：遮蔽放在共用的出口）。
  String redact(String text) => text;

  /// 整件重跑前把工具的狀態清掉（抓過的頁、改到一半的書源）。[attempt] 是
  /// 接著要跑的第幾次，[why] 是上一次為什麼沒跑完。
  void restart(int attempt, String why);

  /// 讀出 AI 呼叫的一個工具。
  AgentParse<C> parse(AiToolCall call);

  /// AI 這輪沒有呼叫工具：傳回要接進對話的那句事實。
  String noToolCall(AiReply reply);

  /// 執行一個指令；傳回的文字是要接進對話的事實，秘密已經遮掉。
  Future<AgentResult> execute(C command);

  /// [command] 和同一則回覆裡的其他呼叫同時執行也不會改變結果（只讀的
  /// 查詢）：迴圈一收到回覆就一起開始，結果照呼叫的順序接回對話。交出這類
  /// 要看前面查過什麼的，照順序執行。預設都照順序。
  bool runsAlongside(C command) => false;

  /// 一輪開始：第 [attempt] 次的第 [round] 輪（每次從 1 數起）；[messages]
  /// 是這輪要送出的全部對話。
  void roundStarted(int attempt, int round, List<AiMessage> messages) {}

  /// 一輪問完：成功時有 [reply]，沒有時 [error] 說出了什麼事。
  void roundEnded(AgentRoundRecord record) {}

  /// 接進對話、但不是工具結果的一句（沒有指令、讀不懂、這輪的狀態）。
  void factAdded(String fact) {}

  /// 要問 AI 之前的完整狀態：上一輪的每個呼叫都有結果了，接著問的就是
  /// [state] 的對話。任務在這裡同步存下它與自己的狀態（看過哪些書、抓過的
  /// 頁），App 重開後用 [runAgent] 的 `resume` 從這裡接著問（ADR 0058）。
  /// 一定要在這裡同步存：之後的工具會改任務的狀態，晚一點存的話，任務記得
  /// 做過、對話裡卻還沒有那句結果。
  void checkpoint(AgentCheckpoint state) {}
}

/// 問 AI 之前的迴圈狀態（[AgentTask.checkpoint]）：對話與停下條件的計數，
/// 從這裡接著跑和沒中斷一樣。
final class AgentCheckpoint {
  AgentCheckpoint({
    required this.attempt,
    required this.round,
    required this.messages,
    required this.noCommand,
    required this.badCommand,
    required this.rejections,
    required this.stalls,
    required this.calls,
    required this.lastResult,
    required this.stats,
  });

  /// 第幾次（整件重跑算一次）。
  final int attempt;

  /// 這一次已經問了幾輪。
  final int round;
  final List<AiMessage> messages;
  final int noCommand;
  final int badCommand;
  final int rejections;
  final int stalls;

  /// 同樣的工具與參數各叫了幾次（[AiAgentKnobs.sameCallLimit]）。
  final Map<String, int> calls;

  /// 每個工具與參數上一次的結果（「結果與前幾次相同」）。
  final Map<String, String> lastResult;

  /// [AgentStats.toMap] 的樣子。
  final Map<String, Object?> stats;

  Map<String, Object?> toJson() => {
    'attempt': attempt,
    'round': round,
    'messages': [for (final message in messages) agentMessageToJson(message)],
    'noCommand': noCommand,
    'badCommand': badCommand,
    'rejections': rejections,
    'stalls': stalls,
    'calls': calls,
    'lastResult': lastResult,
    'stats': stats,
  };

  /// 讀回 [toJson] 存的；格式不對時丟 [FormatException]。
  factory AgentCheckpoint.fromJson(Map<String, Object?> json) {
    T read<T>(String key) => switch (json[key]) {
      final T value => value,
      _ => throw FormatException('迴圈狀態少了 $key'),
    };
    return AgentCheckpoint(
      attempt: read<int>('attempt'),
      round: read<int>('round'),
      messages: [
        for (final item in read<List<Object?>>('messages'))
          agentMessageFromJson(item),
      ],
      noCommand: read<int>('noCommand'),
      badCommand: read<int>('badCommand'),
      rejections: read<int>('rejections'),
      stalls: read<int>('stalls'),
      calls: read<Map<String, Object?>>('calls')
          .map((key, value) => MapEntry(key, value is int ? value : 0)),
      lastResult: read<Map<String, Object?>>('lastResult')
          .map((key, value) => MapEntry(key, '$value')),
      stats: read<Map<String, Object?>>('stats'),
    );
  }
}

/// 存檔用的一句對話：和送給服務的樣子（[AiMessage.toJson]）分開，原樣存
/// 每個欄位（送出時空白的內容會變成 null，讀回來就不一樣了）。
Map<String, Object?> agentMessageToJson(AiMessage message) => {
  'role': message.role,
  'content': message.content,
  if (message.reasoning.isNotEmpty) 'reasoning': message.reasoning,
  if (message.reasoningDetails.isNotEmpty)
    'reasoningDetails': message.reasoningDetails,
  if (message.responseItems.isNotEmpty) 'responseItems': message.responseItems,
  'toolCallId': ?message.toolCallId,
  if (message.toolCalls.isNotEmpty)
    'toolCalls': [
      for (final call in message.toolCalls)
        {
          'id': call.id,
          'name': call.name,
          'arguments': call.arguments,
          if (call.extra.isNotEmpty) 'extra': call.extra,
        },
    ],
};

AiMessage agentMessageFromJson(Object? json) {
  if (json case {'role': final String role, 'content': final String content}) {
    return AiMessage(
      role,
      content,
      reasoning: switch (json['reasoning']) {
        final String text => text,
        _ => '',
      },
      reasoningDetails: switch (json['reasoningDetails']) {
        final List<Object?> details => details,
        _ => const [],
      },
      responseItems: switch (json['responseItems']) {
        final List<Object?> items => items,
        _ => const [],
      },
      toolCallId: switch (json['toolCallId']) {
        final String id => id,
        _ => null,
      },
      toolCalls: [
        if (json['toolCalls'] case final List<Object?> calls)
          for (final call in calls)
            if (call case {
              'id': final String id,
              'name': final String name,
              'arguments': final String arguments,
            })
              AiToolCall(
                id: id,
                name: name,
                arguments: arguments,
                extra: switch (call['extra']) {
                  final Map<String, Object?> extra => extra,
                  _ => const {},
                },
              ),
      ],
    );
  }
  throw const FormatException('對話的一句格式不對');
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

/// 讀 AI 的一個工具呼叫的參數：讀得懂時 [args] 是參數物件；讀不懂時 [fact]
/// 說哪裡不對（沒有這個工具、參數不是 JSON 物件），開頭是 [badCall]。
/// [malformed] 是參數根本不是 JSON（[AgentBadCommand.malformed]）。
({Map<String, dynamic>? args, String fact, bool malformed}) decodeToolCall(
  AiToolCall call,
  List<AiTool> tools, {
  required String badCall,
}) {
  // 先看是不是 JSON：參數寫壞時工具名稱多半也是模型內建標記的一部分，
  // 照樣丟掉重送。
  final Object? args;
  try {
    args = call.arguments.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(call.arguments);
  } on FormatException catch (error) {
    return (
      args: null,
      fact:
          '$badCall（${call.name}）：參數不是合法的 JSON：'
          '${error.message}${_badJsonSpot(call.arguments, error.offset)}',
      malformed: true,
    );
  }
  if (!tools.any((tool) => tool.name == call.name)) {
    return (
      args: null,
      fact:
          '$badCall：沒有叫 ${call.name} 的工具，有的是 '
          '${tools.map((tool) => tool.name).join('、')}',
      malformed: false,
    );
  }
  if (args is! Map<String, dynamic>) {
    return (
      args: null,
      fact: '$badCall（${call.name}）：參數要是一個 JSON 物件',
      malformed: false,
    );
  }
  return (args: args, fact: '', malformed: false);
}

/// JSON 壞在哪：第幾個字與那一段原文。只寫「Unexpected character」時，AI
/// 看不出自己寫錯什麼，同樣的錯再送一次（2026-11-14 读客书库，模型把內建的
/// 工具標記寫進參數，連續三次讀不懂）。
String _badJsonSpot(String text, int? offset) {
  if (offset == null) return '';
  final at = offset.clamp(0, text.length);
  final from = (at - 20).clamp(0, text.length);
  final to = (at + 20).clamp(0, text.length);
  return '，第 ${at + 1} 個字附近：${text.substring(from, to)}';
}

/// 參數讀得懂、但少了必要的參數或值不對時的那句話。
String missingToolArguments(
  AiToolCall call,
  List<AiTool> tools,
  String badCall,
) {
  final tool = tools.firstWhere((tool) => tool.name == call.name);
  final required = (tool.parameters['required'] as List?)?.cast<String>() ?? [];
  return '$badCall（${call.name}）：少了必要的參數或值不對'
      '${required.isEmpty ? '' : '，要有 ${required.join('、')}'}';
}

/// 一個指令的 key：工具名稱與參數，鍵照名稱排；[ignore] 是不算進去的頂層
/// 參數（例如給人看的說明）。同樣的工具與參數 key 相同
/// （[AiAgentKnobs.sameCallLimit]）。
String agentCommandKey(
  String name,
  Map<String, dynamic> args, {
  Set<String> ignore = const {},
}) {
  Object? sorted(Object? value) => switch (value) {
    final Map<dynamic, dynamic> map => {
      for (final key in map.keys.map((k) => '$k').toList()..sort())
        key: sorted(map[key]),
    },
    final List<dynamic> list => [for (final item in list) sorted(item)],
    _ => value,
  };
  final command = sorted({...args}..removeWhere((k, _) => ignore.contains(k)));
  try {
    return '$name ${jsonEncode(command)}';
  } on JsonUnsupportedObjectError {
    // 數字超出範圍這類寫不回 JSON 的值。
    return '$name $command';
  }
}

/// 一輪寫進紀錄的那行：花的時間、送出多少、服務回報的用量。
String agentRoundText(AgentRoundRecord record) {
  String tokens(int count) => NumberFormat.decimalPattern().format(count);
  final reply = record.reply;
  final seconds =
      '${(record.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} 秒';
  final sent = '送出 ${record.sentMessages} 句 ${tokens(record.sentChars)} 字';
  final head = reply == null
      ? 'AI 回覆 $seconds（$sent）'
      : 'AI 回覆 $seconds（$sent，第一段資料 '
            '${(reply.firstData.inMilliseconds / 1000).toStringAsFixed(1)} 秒）';
  final usage = record.usage;
  if (usage == null) return head;
  return '$head；${record.estimated ? '沒回完，照字數估：' : ''}'
      '送出 ${tokens(usage.prompt)} token'
      '（打中快取 ${tokens(usage.cached)}）、回覆 ${tokens(usage.completion)}'
      '（思考 ${tokens(usage.reasoning)}）';
}

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

/// 呼叫讀不懂：沒有這個工具、參數不是合法的 JSON、少了欄位（[fact] 說
/// 哪裡不對）。[malformed] 是參數根本不是 JSON（模型把內建的工具標記寫進
/// 參數、服務轉不了原樣交回）：這則回覆不接進對話，同一段對話重送。
final class AgentBadCommand<C> extends AgentParse<C> {
  const AgentBadCommand(this.fact, {this.malformed = false});
  final String fact;
  final bool malformed;
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

/// 交出的東西通過驗收（或確定的放棄被接受），這件做完。[reason] 是寫進紀錄
/// 的結束原因：交件與放棄分開記，評估表上放棄的件才不會看起來像做好了。
final class AgentAccepted extends AgentResult {
  const AgentAccepted() : reason = '交件被收下';
  const AgentAccepted.gaveUp() : reason = '放棄被收下';
  final String reason;
}

/// 做到一半停下了（使用者按暫停或結束），或任務自己結束了這件（例如存不進去）。
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

  /// 重跑也不會好的錯（金鑰、網址、額度）。
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

  /// 暫停之前已經跑了多久（接著跑時從 [toMap] 讀回來）；暫停的時間不算。
  Duration _before = Duration.zero;

  /// 每次沒跑完的原因，照順序。
  final List<String> restarts = [];

  /// 接著跑：讀回暫停前 [toMap] 的數字。
  void restore(Map<String, Object?> map) {
    int read(String key) => switch (map[key]) {
      final int value => value,
      _ => 0,
    };
    attempts = read('attempts').clamp(1, 1 << 30);
    rounds = read('rounds');
    toolCalls = read('toolCalls');
    rejections = read('rejections');
    badCommands = read('badCommands');
    noCommands = read('noCommands');
    stalls = read('stalls');
    prompt = read('prompt');
    cached = read('cached');
    completion = read('completion');
    reasoning = read('reasoning');
    model = Duration(milliseconds: read('modelMs'));
    tools = Duration(milliseconds: read('toolsMs'));
    _before = Duration(
      milliseconds: read('modelMs') + read('toolsMs') + read('otherMs'),
    );
    restarts
      ..clear()
      ..addAll([
        if (map['restarts'] case final List<Object?> list)
          for (final item in list) '$item',
      ]);
    _clock
      ..reset()
      ..start();
  }

  Duration get total => _before + _clock.elapsed;
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
    'restarts': [...restarts],
  };
}

/// 問 AI 一次（[AiChatClient.complete]）。
typedef AgentAsk = Future<AiReply> Function(
  List<AiMessage> messages,
  CancelToken cancelToken,
);

/// 跑一件：照 [AgentTask] 開場，一輪一輪問 [ask]，直到有結果。
/// [cancelToken] 取消時是 [AgentEndKind.cancelled]。[attempts] 是含第一次
/// 最多跑幾次。給了 [resume] 是從暫停前存的那一刻接著跑（任務自己的狀態
/// 由任務先讀回來），不再開場。
Future<AgentEnd> runAgent<C>(
  AgentTask<C> task, {
  required AgentAsk ask,
  required CancelToken cancelToken,
  int attempts = AiAgentKnobs.attempts,
  AgentCheckpoint? resume,
}) async {
  final stats = AgentStats();
  if (resume != null) stats.restore(resume.stats);
  AgentEnd end(AgentEndKind kind, String reason) =>
      AgentEnd(kind, reason, stats);

  var from = resume;
  for (var attempt = from?.attempt ?? 1; ; attempt++) {
    stats.attempts = attempt;
    final why = await _attempt(task, attempt, stats, ask, cancelToken, from);
    from = null;
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
  AgentCheckpoint? resume,
) async {
  final messages = resume != null
      ? [...resume.messages]
      : [
          for (final message in task.opening())
            AiMessage(message.role, task.redact(message.content)),
        ];
  var round = resume?.round ?? 0;
  var noCommand = resume?.noCommand ?? 0;
  var badCommand = resume?.badCommand ?? 0;
  var rejections = resume?.rejections ?? 0;
  var stalls = resume?.stalls ?? 0;
  final calls = <String, int>{...?resume?.calls};
  final lastResult = <String, String>{...?resume?.lastResult};
  const cancelled = _Finished(AgentEndKind.cancelled, '已停止');

  /// 這輪的狀態，附在結果後面：快用完時剩幾輪。
  String status() {
    final left = AiAgentKnobs.maxRounds - round;
    return left <= AiAgentKnobs.warnRoundsLeft ? '\n\n（剩 $left 輪）' : '';
  }

  /// 接進對話的一句事實：工具的結果（[callId] 是它回應的那個呼叫），或這輪
  /// 沒有呼叫工具時的一句話。
  void fact(String text, {String? callId}) {
    final line = task.redact('$text${status()}');
    messages.add(
      callId == null ? AiMessage.user(line) : AiMessage.tool(callId, line),
    );
    task.factAdded(line);
  }

  while (true) {
    if (cancelToken.isCancelled) return cancelled;
    if (round >= AiAgentKnobs.maxRounds) {
      return _Retry('用完 ${AiAgentKnobs.maxRounds} 輪還沒交出');
    }
    task.checkpoint(
      AgentCheckpoint(
        attempt: attempt,
        round: round,
        messages: List.unmodifiable(messages),
        noCommand: noCommand,
        badCommand: badCommand,
        rejections: rejections,
        stalls: stalls,
        calls: Map.unmodifiable(calls),
        lastResult: Map.unmodifiable(lastResult),
        stats: stats.toMap(),
      ),
    );
    round++;
    stats.rounds++;
    task.roundStarted(attempt, round, messages);
    final sentChars = messages.fold(
      0,
      (sum, m) =>
          sum +
          m.content.length +
          m.reasoning.length +
          m.toolCalls.fold(0, (n, call) => n + call.arguments.length),
    );
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
        return _Retry('連續 $noCommand 輪沒有呼叫工具');
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
    final parsed = [for (final call in reply.toolCalls) task.parse(call)];
    // 參數寫壞的回覆不接進對話，同一段對話重送：留著的話模型下一輪照抄
    // 自己寫壞的開頭（2026-11-14 读客书库連續三次一字不差）。
    if (parsed.any((p) => p is AgentBadCommand<C> && p.malformed)) {
      stats.badCommands++;
      if (++badCommand >= AiAgentKnobs.badCommandLimit) {
        return _Retry('連續 $badCommand 次工具參數寫壞');
      }
      continue;
    }
    messages.add(AiMessage.reply(reply));

    if (reply.toolCalls.isEmpty) {
      stats.noCommands++;
      if (++noCommand >= AiAgentKnobs.noCommandLimit) {
        return _Retry('連續 $noCommand 輪沒有呼叫工具');
      }
      fact(task.noToolCall(reply));
      continue;
    }
    noCommand = 0;
    // 互不影響的查詢一起跑（AI 一則回覆常叫好幾個搜尋，一個接一個等的話
    // 一輪要好幾分鐘，2026-11-15 AI 找書實跑）：照呼叫的順序切段，相鄰、
    // 可以一起跑的那段輪到時一起開始；交出這類要照順序的是段的界線，前面那段
    // 都回來才做它，後面那段等它做完才開始（Codex 審查：排在交出後面的詳情先
    // 開始，交出就照「已經看過詳情」收了）。同樣的參數到上限的那個和它後面的
    // 不算進來，照順序那段會在那裡停下。
    final alongside = <int>{};
    final counted = Map.of(calls);
    for (final (i, parse) in parsed.indexed) {
      if (parse is! AgentCommand<C>) continue;
      final count = counted[parse.key] = (counted[parse.key] ?? 0) + 1;
      if (count >= AiAgentKnobs.sameCallLimit) break;
      if (task.runsAlongside(parse.command)) alongside.add(i);
    }
    final early = <int, Future<AgentResult>>{};
    void startSegment(int from) {
      for (var j = from; alongside.contains(j); j++) {
        early[j] ??= task.execute((parsed[j] as AgentCommand<C>).command)
          ..ignore();
      }
    }

    final toolWatch = Stopwatch()..start();
    try {
      // 每個呼叫都要有一句工具結果，服務才收下一輪的對話。
      for (final (i, call) in reply.toolCalls.indexed) {
        void answer(String text) => fact(text, callId: call.id);
        switch (parsed[i]) {
          case AgentBadCommand(fact: final text):
            stats.badCommands++;
            if (++badCommand >= AiAgentKnobs.badCommandLimit) {
              return _Retry('連續 $badCommand 次工具呼叫讀不懂');
            }
            answer(text);
          case AgentCommand(:final command, :final key):
            final count = calls[key] = (calls[key] ?? 0) + 1;
            if (count >= AiAgentKnobs.sameCallLimit) {
              return _Retry('同樣的工具與參數第 $count 次');
            }
            stats.toolCalls++;
            if (alongside.contains(i)) startSegment(i);
            final result = await (early[i] ?? task.execute(command));
            if (cancelToken.isCancelled) return cancelled;
            switch (result) {
              case AgentAccepted(:final reason):
                return _Finished(AgentEndKind.completed, reason);
              case AgentStopped(:final kind, :final reason):
                return _Finished(kind, reason);
              case AgentInvalid(fact: final text):
                stats.badCommands++;
                if (++badCommand >= AiAgentKnobs.badCommandLimit) {
                  return _Retry('連續 $badCommand 次工具呼叫讀不懂');
                }
                answer(text);
              case AgentRejected(:final reason):
                badCommand = 0;
                stats.rejections++;
                // 交出之間的查證不重算：數的是交出的那幾次連續被退。
                if (++rejections >= AiAgentKnobs.rejectionLimit) {
                  return _Retry('交出連續被退 $rejections 次');
                }
                answer('$reason${_repeated(count, lastResult, key, reason)}');
              case AgentToolResult(:final text, :final same):
                badCommand = 0;
                answer(
                  '$text${_repeated(count, lastResult, key, same ?? text)}',
                );
            }
        }
      }
    } finally {
      // 提前結束（交出被收下、讀不懂到上限、停止）時，已經開始的查詢也等
      // 它們回來再走：不然這件已經結束、重跑清了狀態，舊的查詢還在用書源、
      // 改狀態、寫紀錄。停止時它們收到同一個取消，很快就回來。
      await Future.wait([
        for (final pending in early.values)
          pending.then<void>((_) {}, onError: (Object _) {}),
      ]);
      // 一起跑的幾個重疊的時間只算一次：工具秒是這一輪等工具的時間。
      stats.tools += toolWatch.elapsed;
    }
  }
}

/// 同樣的工具與參數又來一次時附上的狀態。
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

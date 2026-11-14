import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/agent_loop.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';

/// 假任務：AI 呼叫 `tool:x` 是工具 x、`submit:ok` 交出通過、`submit:bad`
/// 交出被退、`bad` 讀不懂；回的話沒有呼叫工具是沒有指令（[_reply]）。
final class _Task extends AgentTask<String> {
  final List<String> restarts = [];
  final List<String> facts = [];
  var openings = 0;

  @override
  List<AiMessage> opening() {
    openings++;
    return [const AiMessage.system('規則'), const AiMessage.user('這一件')];
  }

  @override
  void restart(int attempt, String why) => restarts.add(why);

  @override
  AgentParse<String> parse(AiToolCall call) {
    if (call.name == 'bad') return const AgentBadCommand('讀不懂');
    return AgentCommand(call.name, call.name);
  }

  @override
  String noToolCall(AiReply reply) => '沒有指令';

  @override
  Future<AgentResult> execute(String command) async => switch (command) {
    'submit:ok' => const AgentAccepted(),
    _ when command.startsWith('submit:bad') => const AgentRejected('校驗沒過'),
    _ => AgentToolResult('$command 的結果'),
  };

  @override
  void factAdded(String fact) => facts.add(fact);
}

/// 開場與工具結果都帶著金鑰的假任務：遮蔽要在迴圈接進對話時做。
final class _Leaky extends _Task {
  @override
  List<AiMessage> opening() => [const AiMessage.user('金鑰 sk-secret')];

  @override
  Future<AgentResult> execute(String command) async => command == 'submit:ok'
      ? const AgentAccepted()
      : const AgentToolResult('回應裡有 sk-secret');

  @override
  String redact(String text) => text.replaceAll('sk-secret', '***');
}

/// 記下每一輪紀錄的假任務。
final class _Recording extends _Task {
  _Recording(this.rounds);
  final List<AgentRoundRecord> rounds;

  @override
  void roundEnded(AgentRoundRecord record) => rounds.add(record);
}

/// 假 AI 回的一次：`tool:`、`submit:` 開頭或 `bad` 是呼叫那個工具，用 `|`
/// 隔開是同一次呼叫好幾個；其他是沒有呼叫工具的話。
AiReply _reply(String content) {
  final calls = content.split('|');
  final isCall = calls.every(
    (name) =>
        name == 'bad' || name.startsWith('tool:') || name.startsWith('submit:'),
  );
  return (
    content: isCall ? '' : content,
    toolCalls: [
      if (isCall)
        for (final (i, name) in calls.indexed)
          (id: 'call_$i', name: name, arguments: '{}'),
    ],
    reasoning: '',
    usage: null,
    firstData: Duration.zero,
  );
}

/// 照順序回 [script] 的假 AI：字串是回的話，例外就丟出來；用完了一直回
/// [rest]。
AgentAsk _ai(List<Object> script, {Object rest = 'tool:more'}) {
  var next = 0;
  return (messages, _) async {
    final step = next < script.length ? script[next++] : rest;
    if (step is Exception) throw step;
    return _reply(step as String);
  };
}

void main() {
  late _Task task;
  setUp(() => task = _Task());

  // 重跑的機制照技能的預設 3 次測；目前設定是一次（AiAgentKnobs.attempts）。
  Future<AgentEnd> run(AgentAsk ask, {CancelToken? cancel}) => runAgent(
    task,
    ask: ask,
    cancelToken: cancel ?? CancelToken(),
    attempts: 3,
  );

  test('a submission that passes completes the case', () async {
    final end = await run(_ai(['tool:a', 'submit:ok']));
    expect(end.kind, AgentEndKind.completed);
    expect(end.stats.rounds, 2);
    expect(end.stats.toolCalls, 2);
  });

  test('a stall is sent again with the same conversation; two in a row '
      'restart the case', () async {
    final seen = <int>[];
    var calls = 0;
    final end = await runAgent(
      task,
      cancelToken: CancelToken(),
      ask: (messages, _) async {
        seen.add(messages.length);
        calls++;
        if (calls == 1) throw const AiStalled('卡住');
        if (calls == 2) return _reply('submit:ok');
        throw StateError('不該再問');
      },
    );
    expect(end.kind, AgentEndKind.completed);
    expect(seen, [2, 2], reason: '原封不動重送');

    final again = _Task();
    final stalls = await runAgent(
      again,
      cancelToken: CancelToken(),
      attempts: 3,
      ask: _ai([
        const AiStalled('卡住'),
        const AiStalled('卡住'),
      ], rest: 'submit:ok'),
    );
    expect(stalls.kind, AgentEndKind.completed);
    expect(again.restarts.single, startsWith('連續卡住 2 次'));
    expect(again.openings, 2);
  });

  test('a runaway restarts with a fresh conversation', () async {
    final end = await run(_ai([const AiRunaway('重複', tail: '…'), 'submit:ok']));
    expect(end.kind, AgentEndKind.completed);
    expect(task.restarts, ['重複']);
  });

  test('the estimated usage of a reply cut off midway still counts', () async {
    final rounds = <AgentRoundRecord>[];
    final recording = _Recording(rounds);
    final end = await runAgent(
      recording,
      ask: _ai([
        const AiRunaway(
          '重複',
          tail: '…',
          usage: (prompt: 100, cached: 0, completion: 40, reasoning: 30),
        ),
      ]),
      cancelToken: CancelToken(),
      attempts: 1,
    );
    expect(end.stats.prompt, 100);
    expect(end.stats.completion, 40);
    expect(rounds.single.usage?.prompt, 100);
    expect(rounds.single.estimated, isTrue);
  });

  test('everything put into the conversation passes through the task\'s '
      'redaction, the opening and every tool result', () async {
    final seen = <List<AiMessage>>[];
    final leaky = _Leaky();
    await runAgent(
      leaky,
      ask: (messages, _) async {
        seen.add(List.of(messages));
        return _reply(seen.length == 1 ? 'tool:a' : 'submit:ok');
      },
      cancelToken: CancelToken(),
      attempts: 1,
    );
    final sent = [for (final m in seen.last) m.content].join('\n');
    expect(sent, isNot(contains('sk-secret')));
    expect(sent, contains('***'));
    expect(seen.last.last.role, 'tool');
  });

  test('the thinking goes back in the conversation as it was', () async {
    final seen = <List<AiMessage>>[];
    await run((messages, _) async {
      seen.add(List.of(messages));
      final reply = _reply(seen.length == 1 ? 'tool:a' : 'submit:ok');
      return (
        content: reply.content,
        toolCalls: reply.toolCalls,
        reasoning: '第 ${seen.length} 輪的思考',
        usage: null,
        firstData: Duration.zero,
      );
    });
    final assistant = seen[1].firstWhere((m) => m.role == 'assistant');
    expect(assistant.reasoning, '第 1 輪的思考');
  });

  test('every call of a reply gets its own tool result, in order', () async {
    final seen = <List<AiMessage>>[];
    final end = await run((messages, _) async {
      seen.add(List.of(messages));
      return _reply(seen.length == 1 ? 'tool:a|bad|tool:b' : 'submit:ok');
    });
    expect(end.kind, AgentEndKind.completed);
    final second = seen[1];
    final asked = second[second.length - 4];
    expect(asked.role, 'assistant');
    expect(asked.toolCalls.map((call) => call.id), [
      'call_0',
      'call_1',
      'call_2',
    ]);
    expect(
      [
        for (final message in second.skip(second.length - 3))
          (message.role, message.toolCallId, message.content),
      ],
      [
        ('tool', 'call_0', 'tool:a 的結果'),
        ('tool', 'call_1', '讀不懂'),
        ('tool', 'call_2', 'tool:b 的結果'),
      ],
      reason: '讀不懂的呼叫也回哪裡不對，服務才收下一輪的對話',
    );
  });

  test('three rounds without a command restart the case', () async {
    final end = await run(_ai(['我想想', '我想想', '我想想'], rest: 'submit:ok'));
    expect(end.kind, AgentEndKind.completed);
    expect(task.restarts.single, '連續 3 輪沒有呼叫工具');
    expect(task.facts.first, '沒有指令', reason: '只回事實，不加指示');
  });

  test('three unreadable commands in a row restart the case', () async {
    final end = await run(_ai(['bad', 'bad', 'bad'], rest: 'submit:ok'));
    expect(end.kind, AgentEndKind.completed);
    expect(task.restarts.single, '連續 3 次工具呼叫讀不懂');
  });

  test('the same call again says so; the fourth time restarts', () async {
    final end = await run(
      _ai(['tool:x', 'tool:x', 'tool:x', 'tool:x'], rest: 'submit:ok'),
    );
    expect(end.kind, AgentEndKind.completed);
    expect(task.facts[1], contains('這是同樣參數的第 2 次，結果與前幾次相同'));
    expect(task.restarts.single, '同樣的工具與參數第 4 次');
  });

  test('five rejected submissions restart the case, even with checks in '
      'between', () async {
    final end = await run(
      _ai([
        for (var i = 0; i < 5; i++) ...['tool:look$i', 'submit:bad$i'],
      ], rest: 'submit:ok'),
    );
    expect(end.kind, AgentEndKind.completed);
    expect(task.restarts.single, '交出連續被退 5 次');
  });

  test('running out of rounds restarts; the last rounds say how many are '
      'left', () async {
    var n = 0;
    final end = await runAgent(
      task,
      cancelToken: CancelToken(),
      ask: (_, _) async => _reply('tool:${n++}'),
      attempts: 3,
    );
    expect(task.restarts.first, '用完 ${AiAgentKnobs.maxRounds} 輪還沒交出');
    expect(task.facts, contains(endsWith('（剩 1 輪）')));
    expect(end.kind, AgentEndKind.unconfirmed, reason: '每次都用完，跑滿 3 次');
    expect(end.stats.attempts, 3);
    expect(end.reason, startsWith('跑了 3 次都沒有結果'));

    // 目前的設定只跑一次：用完就結束，不重跑。
    var m = 0;
    final once = await runAgent(
      _Task(),
      cancelToken: CancelToken(),
      ask: (_, _) async => _reply('tool:${m++}'),
    );
    expect(once.stats.attempts, 1);
    expect(once.stats.rounds, AiAgentKnobs.maxRounds);
    expect(once.reason, '沒有結果：用完 ${AiAgentKnobs.maxRounds} 輪還沒交出');
  });

  test('a busy service is retried with a fresh conversation; a wrong key '
      'ends the case at once', () async {
    final busy = await run(
      _ai([const AiServiceException('忙', retryable: true)], rest: 'submit:ok'),
    );
    expect(busy.kind, AgentEndKind.completed);

    final key = await runAgent(
      _Task(),
      cancelToken: CancelToken(),
      ask: _ai([const AiServiceException('金鑰不對')]),
    );
    expect(key.kind, AgentEndKind.failed);
    expect(key.reason, '金鑰不對');
  });

  test('stopping ends as cancelled', () async {
    final cancel = CancelToken();
    final end = await runAgent(
      task,
      cancelToken: cancel,
      ask: (_, _) async {
        cancel.cancel();
        return _reply('tool:x');
      },
    );
    expect(end.kind, AgentEndKind.cancelled);
  });
}

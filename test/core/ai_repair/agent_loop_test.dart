import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/agent_loop.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';

/// 假任務：AI 回 `tool:x` 是呼叫工具 x、`submit:ok` 交出通過、`submit:bad`
/// 交出被退、`bad` 讀不懂、其他是沒有指令。
final class _Task extends AgentTask<String> {
  final List<String> restarts = [];
  final List<String> facts = [];
  var openings = 0;

  @override
  List<AiMessage> opening() {
    openings++;
    return [(role: 'system', content: '規則'), (role: 'user', content: '這一件')];
  }

  @override
  void restart(int attempt, String why) => restarts.add(why);

  @override
  AgentParse<String> parse(String reply) {
    if (reply == 'bad') return const AgentBadCommand('讀不懂');
    if (reply.startsWith('tool:') || reply.startsWith('submit:')) {
      return AgentCommand(reply, reply);
    }
    return const AgentNoCommand('沒有指令');
  }

  @override
  Future<AgentResult> execute(String command) async => switch (command) {
    'submit:ok' => const AgentAccepted(),
    _ when command.startsWith('submit:bad') => const AgentRejected('校驗沒過'),
    _ => AgentToolResult('$command 的結果'),
  };

  @override
  void factAdded(String fact) => facts.add(fact);
}

AiReply _reply(String content) =>
    (content: content, reasoning: '', usage: null, firstData: Duration.zero);

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

  Future<AgentEnd> run(AgentAsk ask, {CancelToken? cancel}) =>
      runAgent(task, ask: ask, cancelToken: cancel ?? CancelToken());

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

  test('three rounds without a command restart the case', () async {
    final end = await run(_ai(['我想想', '我想想', '我想想'], rest: 'submit:ok'));
    expect(end.kind, AgentEndKind.completed);
    expect(task.restarts.single, '連續 3 輪沒有收到指令');
    expect(task.facts.first, '沒有指令', reason: '只回事實，不加指示');
  });

  test('three unreadable commands in a row restart the case', () async {
    final end = await run(_ai(['bad', 'bad', 'bad'], rest: 'submit:ok'));
    expect(end.kind, AgentEndKind.completed);
    expect(task.restarts.single, '連續 3 輪的指令讀不懂');
  });

  test('the same call again says so; the fourth time restarts', () async {
    final end = await run(
      _ai(['tool:x', 'tool:x', 'tool:x', 'tool:x'], rest: 'submit:ok'),
    );
    expect(end.kind, AgentEndKind.completed);
    expect(task.facts[1], contains('這是同樣參數的第 2 次，結果與前幾次相同'));
    expect(task.restarts.single, '同樣的指令與參數第 4 次');
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
    );
    expect(task.restarts.first, '用完 ${AiAgentKnobs.maxRounds} 輪還沒交出');
    expect(task.facts, contains(endsWith('（剩 1 輪）')));
    expect(
      end.kind,
      AgentEndKind.unconfirmed,
      reason: '每次都用完，跑滿 ${AiAgentKnobs.attempts} 次',
    );
    expect(end.stats.attempts, AiAgentKnobs.attempts);
    expect(end.reason, startsWith('跑了 ${AiAgentKnobs.attempts} 次都沒有結果'));
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

  test('an exhausted batch budget stops before asking', () async {
    final end = await runAgent(
      task,
      cancelToken: CancelToken(),
      ask: _ai(['tool:x']),
      hasBudget: () => false,
    );
    expect(end.kind, AgentEndKind.failed);
    expect(end.stats.rounds, 0);
  });
}

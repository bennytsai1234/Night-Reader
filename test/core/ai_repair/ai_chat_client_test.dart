import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';

/// 照 `text/event-stream` 一段一段送 [chunks] 的服務；[hangAfter] 段之後就
/// 不再送（卡住）。
class _Stream implements HttpClientAdapter {
  _Stream(this.chunks, {this.hangAfter});

  final List<String> chunks;
  final int? hangAfter;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final controller = StreamController<Uint8List>();
    unawaited(() async {
      for (final (i, chunk) in chunks.indexed) {
        if (hangAfter != null && i >= hangAfter!) return;
        await Future<void>.delayed(Duration.zero);
        if (controller.isClosed) return;
        controller.add(Uint8List.fromList(utf8.encode(chunk)));
      }
      await controller.close();
    }());
    unawaited(cancelFuture?.then((_) => controller.close()));
    return ResponseBody(
      controller.stream,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _event(Map<String, Object?> data) => 'data: ${jsonEncode(data)}\n\n';

String _delta({String? content, String? reasoning, String? finish}) => _event({
  'choices': [
    {
      'delta': {'content': ?content, 'reasoning_content': ?reasoning},
      'finish_reason': finish,
    },
  ],
});

class _Service implements HttpClientAdapter {
  _Service(this.status, this.body);

  final int status;
  final Object body;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

AiChatClient _client(
  HttpClientAdapter adapter, {
  String apiKey = 'sk-1',
  String effort = '',
  String baseUrl = 'https://ai.example/v1/',
}) => AiChatClient((
  baseUrl: baseUrl,
  apiKey: apiKey,
  model: 'm',
  effort: effort,
), dio: Dio()..httpClientAdapter = adapter);

void main() {
  test('the endpoint is the base URL plus chat/completions, once', () {
    expect(
      AiChatClient.endpoint('https://ai.example/v1/'),
      'https://ai.example/v1/chat/completions',
    );
    expect(
      AiChatClient.endpoint('http://localhost:11434/v1/chat/completions'),
      'http://localhost:11434/v1/chat/completions',
    );
  });

  test('sends the model and conversation, reads the first choice', () async {
    final service = _Service(200, {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': '{"action":"give_up"}'},
        },
      ],
    });

    final reply = await _client(service)
        .complete([const AiMessage.system('說明'), const AiMessage.user('書源')]);

    expect(reply.content, '{"action":"give_up"}');
    expect(
      service.request!.uri.toString(),
      'https://ai.example/v1/chat/completions',
    );
    expect(service.request!.headers['Authorization'], 'Bearer sk-1');
    expect(service.request!.data, containsPair('model', 'm'));
    expect(service.request!.data, containsPair('stream', true));
    expect(service.request!.data, isNot(contains('temperature')));
  });

  test('tools are sent and must be called; earlier calls, their thinking '
      'and results go back in the conversation', () async {
    final service = _Service(200, {
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': 'call_2',
                'type': 'function',
                'function': {'name': 'read', 'arguments': '{"page":1}'},
              },
            ],
          },
        },
      ],
    });
    const fetch = (id: 'call_1', name: 'fetch', arguments: '{"url":"/"}');

    final reply = await _client(service).complete(
      [
        const AiMessage.user('書源'),
        const AiMessage.assistant('', toolCalls: [fetch], reasoning: '先看首頁'),
        const AiMessage.tool('call_1', '頁 1'),
      ],
      tools: [
        (
          name: 'read',
          description: '讀頁',
          parameters: {'type': 'object', 'properties': {}},
        ),
      ],
    );

    expect(reply.content, '');
    expect(reply.toolCalls, [
      (id: 'call_2', name: 'read', arguments: '{"page":1}'),
    ]);
    final data = service.request!.data as Map<String, dynamic>;
    expect(data['tool_choice'], 'required');
    expect((data['tools'] as List).single, {
      'type': 'function',
      'function': {
        'name': 'read',
        'description': '讀頁',
        'parameters': {'type': 'object', 'properties': {}},
      },
    });
    expect((data['messages'] as List).skip(1), [
      {
        'role': 'assistant',
        'content': null,
        'reasoning_content': '先看首頁',
        'tool_calls': [
          {
            'id': 'call_1',
            'type': 'function',
            'function': {'name': 'fetch', 'arguments': '{"url":"/"}'},
          },
        ],
      },
      {'role': 'tool', 'content': '頁 1', 'tool_call_id': 'call_1'},
    ]);
  });

  test('a streamed tool call is put together from its pieces', () async {
    Map<String, Object?> piece(Map<String, Object?> call) => {
      'choices': [
        {
          'delta': {
            'tool_calls': [call],
          },
        },
      ],
    };
    final service = _Stream([
      _event(
        piece({
          'index': 0,
          'id': 'call_9',
          'function': {'name': 'fetch', 'arguments': ''},
        }),
      ),
      _event(
        piece({
          'index': 0,
          'function': {'arguments': '{"url":'},
        }),
      ),
      _event(
        piece({
          'index': 0,
          'function': {'arguments': '"/s"}'},
        }),
      ),
      'data: [DONE]\n\n',
    ]);

    final reply = await _client(service).complete([const AiMessage.user('hi')]);

    expect(reply.toolCalls, [
      (id: 'call_9', name: 'fetch', arguments: '{"url":"/s"}'),
    ]);
  });

  test('the thinking effort is sent only when one is chosen, and the usage '
      'is reported', () async {
    Map<String, Object> reply() => {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': 'OK'},
        },
      ],
      'usage': {
        'prompt_tokens': 100,
        'completion_tokens': 20,
        'prompt_cache_hit_tokens': 60,
      },
    };
    final plain = _Service(200, reply());
    await _client(plain).complete([const AiMessage.user('hi')]);
    expect(plain.request!.data, isNot(contains('reasoning_effort')));

    final low = _Service(200, reply());
    final answer = await _client(
      low,
      effort: 'low',
    ).complete([const AiMessage.user('hi')]);
    expect(low.request!.data, containsPair('reasoning_effort', 'low'));
    expect(answer.usage, (
      prompt: 100,
      cached: 60,
      completion: 20,
      reasoning: 0,
    ));
  });

  test('a local service without a key sends no Authorization', () async {
    final service = _Service(200, {
      'choices': [
        {
          'message': {'content': 'ok'},
        },
      ],
    });

    await _client(service, apiKey: '').complete([const AiMessage.user('hi')]);

    expect(service.request!.headers.containsKey('Authorization'), isFalse);
  });

  test('OpenCode requests reuse a session within one conversation', () async {
    final service = _Service(200, {
      'choices': [
        {
          'message': {'content': 'OK'},
        },
      ],
    });
    const baseUrl = 'https://opencode.ai/inference/go/openai/v1';
    final client = _client(service, baseUrl: baseUrl);

    await client.complete([const AiMessage.user('first')]);
    final firstSession = service.request!.headers['x-opencode-session'];
    expect(firstSession, isA<String>());
    expect(firstSession, startsWith('ses_'));
    expect(service.request!.headers['User-Agent'], 'NightReader-AIRepair/1.0');
    expect(service.request!.uri.toString(), '$baseUrl/chat/completions');

    await client.complete([const AiMessage.user('second')]);
    expect(service.request!.headers['x-opencode-session'], firstSession);

    await _client(
      service,
      baseUrl: baseUrl,
    ).complete([const AiMessage.user('a different repair')]);
    expect(service.request!.headers['x-opencode-session'], isNot(firstSession));
  });

  test('the OpenCode header never leaks to other providers', () async {
    final response = {
      'choices': [
        {
          'message': {'content': 'OK'},
        },
      ],
    };
    final regular = _Service(200, response);
    await _client(regular).complete([const AiMessage.user('hi')]);
    expect(regular.request!.headers.containsKey('x-opencode-session'), isFalse);
    expect(regular.request!.headers.containsKey('User-Agent'), isFalse);

    final unrelatedPath = _Service(200, response);
    await _client(
      unrelatedPath,
      baseUrl: 'https://opencode.ai/another-api/v1',
    ).complete([const AiMessage.user('hi')]);
    expect(
      unrelatedPath.request!.headers.containsKey('x-opencode-session'),
      isFalse,
    );

    final payg = _Service(200, response);
    await _client(
      payg,
      baseUrl: 'https://opencode.ai/inference/openai/v1',
    ).complete([const AiMessage.user('hi')]);
    expect(payg.request!.headers['x-opencode-session'], startsWith('ses_'));
  });

  test('a service message that echoes the key does not carry it out', () async {
    // 審查：相容服務的 401 會把收到的金鑰原樣寫回錯誤訊息。
    const key = 'sk-secret-key-123456';
    final service = _Service(401, {
      'error': {'message': 'Incorrect API key provided: $key'},
    });

    await expectLater(
      () =>
          _client(service, apiKey: key).complete([const AiMessage.user('hi')]),
      throwsA(
        isA<AiServiceException>()
            .having((e) => e.message, 'message', isNot(contains(key)))
            .having((e) => e.message, 'message', contains('«已遮蔽»')),
      ),
    );
  });

  test('errors say what to fix, with the service message', () async {
    final service = _Service(401, {
      'error': {'message': 'Incorrect API key provided'},
    });

    expect(
      () => _client(service).complete([const AiMessage.user('hi')]),
      throwsA(
        isA<AiServiceException>().having(
          (e) => e.message,
          'message',
          '金鑰不對或沒有權限：Incorrect API key provided',
        ),
      ),
    );
  });

  group('streaming', () {
    const limits = (
      stall: Duration(milliseconds: 200),
      total: Duration(seconds: 5),
      maxOutputChars: 2000,
      repeatedSentences: 5,
    );

    test('the reply and the thinking are put together from the chunks, with '
        'the usage from the last one', () async {
      final service = _Stream([
        _delta(reasoning: '先看搜尋頁。'),
        _delta(reasoning: '規則選錯了。'),
        _delta(content: '{"action":'),
        // 一段資料切在一行的中間。
        _delta(content: '"read"}').substring(0, 10),
        _delta(content: '"read"}').substring(10),
        _event({
          'choices': <Object>[],
          'usage': {
            'prompt_tokens': 50,
            'completion_tokens': 30,
            'completion_tokens_details': {'reasoning_tokens': 12},
          },
        }),
        'data: [DONE]\n\n',
      ]);

      final reply = await _client(service)
          .complete([const AiMessage.user('hi')], limits: limits);

      expect(reply.content, '{"action":"read"}');
      expect(reply.reasoning, '先看搜尋頁。規則選錯了。');
      expect(reply.usage, (
        prompt: 50,
        cached: 0,
        completion: 30,
        reasoning: 12,
      ));
    });

    test('no data for the stall time is a stall, retried with the same '
        'conversation', () async {
      final service = _Stream([
        _delta(reasoning: '想一下。'),
        _delta(content: '{}'),
      ], hangAfter: 1);

      await expectLater(
        _client(service).complete([const AiMessage.user('hi')], limits: limits),
        throwsA(
          isA<AiStalled>().having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('the same sentences over and over is a runaway, with the tail '
        'kept', () async {
      final service = _Stream([
        _delta(reasoning: '我要先檢查搜尋規則。'),
        for (var i = 0; i < 8; i++) _delta(reasoning: '我要先檢查搜尋規則。'),
        _delta(content: '{}'),
      ]);

      await expectLater(
        _client(service).complete([const AiMessage.user('hi')], limits: limits),
        throwsA(
          isA<AiRunaway>()
              .having((e) => e.tail, 'tail', startsWith('思考的最後一段：\n'))
              .having((e) => e.tail, 'tail', contains('檢查搜尋規則'))
              // 服務來不及回報用量：照字數估，送出的 2 字、失控時思考的
              // 60 字（第 6 句是第 5 次重複），每 token 2.5 字。
              .having((e) => e.usage?.prompt, 'prompt', 1)
              .having((e) => e.usage?.reasoning, 'reasoning', 24),
        ),
      );
    });

    test('quoting the same line now and then is not a runaway', () async {
      final service = _Stream([
        for (var i = 0; i < 8; i++) ...[
          _delta(reasoning: '規則是 class.txt@text。'),
          _delta(reasoning: '第 $i 次試的是新的寫法。'),
        ],
        _delta(content: '{"action":"read"}'),
      ]);

      final reply = await _client(service)
          .complete([const AiMessage.user('hi')], limits: limits);
      expect(reply.content, '{"action":"read"}');
    });

    test(
      'hitting the output limit, ours or the service\'s, is a runaway',
      () async {
        await expectLater(
          _client(_Stream([_delta(content: 'x' * 2500)]))
              .complete([const AiMessage.user('hi')], limits: limits),
          throwsA(isA<AiRunaway>()),
        );
        await expectLater(
          _client(_Stream([_delta(content: '{"a":', finish: 'length')]))
              .complete([const AiMessage.user('hi')], limits: limits),
          throwsA(isA<AiRunaway>()),
        );
      },
    );

    test('busy and server errors can be retried; a wrong key cannot', () async {
      for (final (status, retryable) in [
        (429, true),
        (503, true),
        (401, false),
      ]) {
        await expectLater(
          _client(
            _Service(status, {
              'error': {'message': 'x'},
            }),
          ).complete([const AiMessage.user('hi')], limits: limits),
          throwsA(
            isA<AiServiceException>().having(
              (e) => e.retryable,
              'retryable',
              retryable,
            ),
          ),
          reason: '$status',
        );
      }
    });
  });
}

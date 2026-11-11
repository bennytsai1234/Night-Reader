import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';

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
  _Service adapter, {
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

    final reply = await _client(service).complete([
      (role: 'system', content: '說明'),
      (role: 'user', content: '書源'),
    ]);

    expect(reply, '{"action":"give_up"}');
    expect(
      service.request!.uri.toString(),
      'https://ai.example/v1/chat/completions',
    );
    expect(service.request!.headers['Authorization'], 'Bearer sk-1');
    expect(service.request!.data, containsPair('model', 'm'));
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
    await _client(plain).complete([(role: 'user', content: 'hi')]);
    expect(plain.request!.data, isNot(contains('reasoning_effort')));

    final low = _Service(200, reply());
    AiUsage? usage;
    await _client(low, effort: 'low').complete([
      (role: 'user', content: 'hi'),
    ], onUsage: (value) => usage = value);
    expect(low.request!.data, containsPair('reasoning_effort', 'low'));
    expect(usage, (prompt: 100, cached: 60, completion: 20));
  });

  test('a local service without a key sends no Authorization', () async {
    final service = _Service(200, {
      'choices': [
        {
          'message': {'content': 'ok'},
        },
      ],
    });

    await _client(
      service,
      apiKey: '',
    ).complete([(role: 'user', content: 'hi')]);

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

    await client.complete([(role: 'user', content: 'first')]);
    final firstSession = service.request!.headers['x-opencode-session'];
    expect(firstSession, isA<String>());
    expect(firstSession, startsWith('ses_'));
    expect(
      service.request!.headers['User-Agent'],
      'NightReader-AIRepair/1.0',
    );
    expect(
      service.request!.uri.toString(),
      '$baseUrl/chat/completions',
    );

    await client.complete([(role: 'user', content: 'second')]);
    expect(service.request!.headers['x-opencode-session'], firstSession);

    await _client(service, baseUrl: baseUrl).complete([
      (role: 'user', content: 'a different repair'),
    ]);
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
    await _client(regular).complete([(role: 'user', content: 'hi')]);
    expect(
      regular.request!.headers.containsKey('x-opencode-session'),
      isFalse,
    );
    expect(regular.request!.headers.containsKey('User-Agent'), isFalse);

    final unrelatedPath = _Service(200, response);
    await _client(
      unrelatedPath,
      baseUrl: 'https://opencode.ai/another-api/v1',
    ).complete([(role: 'user', content: 'hi')]);
    expect(
      unrelatedPath.request!.headers.containsKey('x-opencode-session'),
      isFalse,
    );

    final payg = _Service(200, response);
    await _client(
      payg,
      baseUrl: 'https://opencode.ai/inference/openai/v1',
    ).complete([(role: 'user', content: 'hi')]);
    expect(payg.request!.headers['x-opencode-session'], startsWith('ses_'));
  });

  test('errors say what to fix, with the service message', () async {
    final service = _Service(401, {
      'error': {'message': 'Incorrect API key provided'},
    });

    expect(
      () => _client(service).complete([(role: 'user', content: 'hi')]),
      throwsA(
        isA<AiServiceException>().having(
          (e) => e.message,
          'message',
          '金鑰不對或沒有權限：Incorrect API key provided',
        ),
      ),
    );
  });
}

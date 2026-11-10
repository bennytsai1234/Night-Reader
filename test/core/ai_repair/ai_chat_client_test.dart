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

AiChatClient _client(_Service adapter, {String apiKey = 'sk-1'}) =>
    AiChatClient((
      baseUrl: 'https://ai.example/v1/',
      apiKey: apiKey,
      model: 'm',
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

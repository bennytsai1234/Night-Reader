import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/ai_repair/ai_chat_client.dart';
import 'package:night_reader/core/ai_repair/ai_connection_check.dart';

typedef _Reply = Map<String, Object?> Function(RequestOptions request);

/// 依序回傳模型的兩輪結果，並保留實際送給服務的請求。
class _ProbeService implements HttpClientAdapter {
  _ProbeService(this.replies);

  final List<_Reply> replies;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = requests.length;
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'choices': [
          {'message': replies[index](options)},
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

AiChatClient _client(_ProbeService service) => AiChatClient((
  baseUrl: 'https://opencode.ai/inference/go/openai/v1',
  apiKey: 'key',
  model: 'deepseek-v4.1-flash',
  effort: '',
), dio: Dio()..httpClientAdapter = service);

Map<String, Object?> _toolCall({
  String id = 'call_1',
  String name = 'connection_ping',
  String arguments = '{"value":"ping"}',
}) => {
  'role': 'assistant',
  'content': null,
  'tool_calls': [
    {
      'id': id,
      'type': 'function',
      'function': {'name': name, 'arguments': arguments},
    },
  ],
};

Map<String, Object?> _echoToolNonce(RequestOptions request) {
  final data = request.data as Map<String, dynamic>;
  final messages = data['messages'] as List<dynamic>;
  final tool = messages[3] as Map<String, dynamic>;
  final body = jsonDecode(tool['content'] as String) as Map<String, dynamic>;
  return {'role': 'assistant', 'content': body['nonce']};
}

void main() {
  test('tests a complete tool call and result round trip', () async {
    final service = _ProbeService([(_) => _toolCall(), _echoToolNonce]);

    await verifyAiToolConnection(_client(service));

    expect(service.requests, hasLength(2));
    final first = service.requests.first.data as Map<String, dynamic>;
    expect(first['tool_choice'], 'required');
    final tools = first['tools'] as List<dynamic>;
    final function =
        (tools.single as Map<String, dynamic>)['function']
            as Map<String, dynamic>;
    expect(function['name'], 'connection_ping');
    expect(function['parameters'], containsPair('required', ['value']));

    final second = service.requests.last.data as Map<String, dynamic>;
    expect(second.containsKey('tools'), isFalse);
    final messages = second['messages'] as List<dynamic>;
    expect(messages, hasLength(5));
    final assistant = messages[2] as Map<String, dynamic>;
    expect(assistant['role'], 'assistant');
    expect((assistant['tool_calls'] as List<dynamic>), hasLength(1));
    final toolMessage = messages[3] as Map<String, dynamic>;
    expect(toolMessage['role'], 'tool');
    expect(toolMessage['tool_call_id'], 'call_1');
    final result =
        jsonDecode(toolMessage['content'] as String) as Map<String, dynamic>;
    final nonce = result['nonce'] as String;
    expect(nonce, isNotEmpty);
    final followup = messages[4] as Map<String, dynamic>;
    expect(followup['role'], 'user');
    expect(followup['content'], isNot(contains(nonce)));

    // OpenCode 同一次連線檢測的兩輪應該使用同一個 session。
    expect(
      service.requests.first.headers['x-opencode-session'],
      service.requests.last.headers['x-opencode-session'],
    );
  });

  test('every tool call in the first reply gets a matching result', () async {
    final multi = _toolCall();
    (multi['tool_calls'] as List<dynamic>).add({
      'id': 'call_2',
      'type': 'function',
      'function': {'name': 'connection_ping', 'arguments': '{"value":"ping"}'},
    });
    final service = _ProbeService([(_) => multi, _echoToolNonce]);

    await verifyAiToolConnection(_client(service));

    final second = service.requests.last.data as Map<String, dynamic>;
    final messages = second['messages'] as List<dynamic>;
    expect(messages, hasLength(6));
    expect((messages[3] as Map<String, dynamic>)['tool_call_id'], 'call_1');
    expect((messages[4] as Map<String, dynamic>)['tool_call_id'], 'call_2');
  });

  test('plain text without a tool call is not reported as connected', () async {
    final service = _ProbeService([
      (_) => {'role': 'assistant', 'content': 'OK'},
    ]);

    await expectLater(
      verifyAiToolConnection(_client(service)),
      throwsA(
        isA<AiServiceException>().having(
          (e) => e.message,
          'message',
          contains('工具呼叫'),
        ),
      ),
    );
    expect(service.requests, hasLength(1));
  });

  test('malformed arguments and unexpected tool names are rejected', () async {
    for (final reply in [
      _toolCall(arguments: '{"value":'),
      _toolCall(arguments: '{}'),
      _toolCall(name: 'different_tool'),
      _toolCall(id: ''),
    ]) {
      final service = _ProbeService([(_) => reply]);
      await expectLater(
        verifyAiToolConnection(_client(service)),
        throwsA(isA<AiServiceException>()),
      );
      expect(service.requests, hasLength(1));
    }
  });

  test('a second reply that ignores the tool result is rejected', () async {
    final service = _ProbeService([
      (_) => _toolCall(),
      (_) => {'role': 'assistant', 'content': 'OK'},
    ]);

    await expectLater(
      verifyAiToolConnection(_client(service)),
      throwsA(
        isA<AiServiceException>().having(
          (e) => e.message,
          'message',
          contains('工具結果'),
        ),
      ),
    );
    expect(service.requests, hasLength(2));
  });
}

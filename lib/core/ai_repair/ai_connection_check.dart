import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'ai_chat_client.dart';

/// 檢查 AI 服務能不能完成一次真正的工具呼叫往返。
/// 工具只回傳隨機驗證值，不會執行書源規則或修改手機上的資料。
Future<void> verifyAiToolConnection(AiChatClient client) async {
  const tool = (
    name: 'connection_ping',
    description: '測試工具呼叫，不讀取或修改任何資料。',
    parameters: <String, Object?>{
      'type': 'object',
      'properties': {
        'value': {
          'type': 'string',
          'enum': ['ping'],
        },
      },
      'required': ['value'],
    },
  );
  const opening = <AiMessage>[
    AiMessage.system('這是工具呼叫測試。請照使用者的要求呼叫提供的工具。'),
    AiMessage.user('請只呼叫一次 connection_ping，參數 value 必須是 ping。'),
  ];

  final first = await client.complete(opening, tools: const [tool]);
  if (first.toolCalls.isEmpty) {
    throw const AiServiceException('模型沒有回傳工具呼叫，無法確認工具功能正常');
  }

  // 模型可能在同一輪呼叫多次；每個呼叫都要驗證並回覆，才能繼續對話。
  for (final call in first.toolCalls) {
    if (call.id.isEmpty || call.name != tool.name) {
      throw const AiServiceException('模型回傳的工具名稱或呼叫 ID 不正確');
    }
    try {
      final args = jsonDecode(call.arguments);
      if (args is! Map<String, dynamic> || args['value'] != 'ping') {
        throw const FormatException('參數不正確');
      }
    } on FormatException {
      throw const AiServiceException('模型回傳的工具參數不是正確的 JSON 或缺少 value');
    }
  }

  // 驗證值只出現在工具結果，不能讓模型只憑前面的提示詞回答成功。
  final nonce = const Uuid().v4();
  final second = await client.complete([
    ...opening,
    AiMessage.assistant(
      first.content,
      toolCalls: first.toolCalls,
      reasoning: first.reasoning,
    ),
    for (final call in first.toolCalls)
      AiMessage.tool(call.id, jsonEncode({'nonce': nonce})),
    const AiMessage.user('請只回覆剛才工具結果中的 nonce 原值，不加引號或說明。'),
  ]);
  if (second.toolCalls.isNotEmpty || second.content.trim() != nonce) {
    throw const AiServiceException('模型沒有正確讀取工具結果，工具呼叫往返未通過');
  }
}

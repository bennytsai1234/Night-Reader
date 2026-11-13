import 'dart:convert';

import 'package:night_reader/core/ai_repair/ai_chat_client.dart';

/// 假 AI 的一次回覆。[text] 是 `{"action":"test", …}` 這種 JSON 物件時，當成
/// 呼叫工具 `action`、其他欄位是參數；其他文字是沒有呼叫工具的一句話。
AiReply fakeAiReply(String text) {
  Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    json = null;
  }
  if (json is Map<String, dynamic> && json['action'] is String) {
    // 參數照原文給（多一個 action 欄位不影響）：1e400 這種寫不回 JSON 的數字
    // 也照樣送到。
    return (
      content: '',
      toolCalls: [
        (
          id: 'call_${_calls++}',
          name: json['action'] as String,
          arguments: text,
        ),
      ],
      reasoning: '',
      usage: null,
      firstData: Duration.zero,
    );
  }
  return (
    content: text,
    toolCalls: const [],
    reasoning: '',
    usage: null,
    firstData: Duration.zero,
  );
}

var _calls = 0;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'ai_repair_secrets.dart';
import 'ai_repair_settings.dart';

/// 對話裡的一句：`system`、`user`、`assistant` 說的話，或 `tool`（工具的
/// 結果，[toolCallId] 是它回應的那個呼叫）。AI 呼叫工具的那一句帶著
/// [toolCalls]，話可以是空的；AI 說的話帶著它的思考 [reasoning]，原樣放回
/// 對話（`agent-harness` 技能）：模型下一輪接著自己的推理，不用重想。
///
/// 服務另外附、規定要原樣送回的思考資料也帶著：[reasoningDetails] 是
/// OpenRouter 的 `reasoning_details`，[responseItems] 是 OpenAI `responses`
/// 那次回覆的全部輸出項目（含加密的思考）。
final class AiMessage {
  const AiMessage(
    this.role,
    this.content, {
    this.toolCalls = const [],
    this.toolCallId,
    this.reasoning = '',
    this.reasoningDetails = const [],
    this.responseItems = const [],
  });

  const AiMessage.system(String content) : this('system', content);
  const AiMessage.user(String content) : this('user', content);
  const AiMessage.assistant(
    String content, {
    List<AiToolCall> toolCalls = const [],
    String reasoning = '',
  }) : this('assistant', content, toolCalls: toolCalls, reasoning: reasoning);
  const AiMessage.tool(String toolCallId, String content)
    : this('tool', content, toolCallId: toolCallId);

  /// AI 的一次回覆，連同服務要原樣送回的資料。
  AiMessage.reply(AiReply reply)
    : this(
        'assistant',
        reply.content,
        toolCalls: reply.toolCalls,
        reasoning: reply.reasoning,
        reasoningDetails: reply.reasoningDetails,
        responseItems: reply.responseItems,
      );

  final String role;
  final String content;
  final List<AiToolCall> toolCalls;
  final String? toolCallId;
  final String reasoning;
  final List<Object?> reasoningDetails;
  final List<Object?> responseItems;

  /// 送給服務的樣子（OpenAI 的 `chat/completions`）。思考放在
  /// `reasoning_content`（DeepSeek 的欄位，OpenRouter 也認；2026-11-12
  /// OpenCode Go 的 deepseek-v4.1-flash 實測收）。[withReasoning] 是對話裡有
  /// 一則帶過思考：AI 的每則回覆都帶這個欄位，空的送空字串（DeepSeek 的思考
  /// 模式每則都要，少了回 400）。
  Map<String, Object?> toJson({bool withReasoning = false}) => {
    'role': role,
    'content': toolCalls.isNotEmpty && content.isEmpty ? null : content,
    if (role == 'assistant' && (withReasoning || reasoning.isNotEmpty))
      'reasoning_content': reasoning,
    if (_detailsToSend case final details when details.isNotEmpty)
      'reasoning_details': details,
    if (toolCalls.isNotEmpty)
      'tool_calls': [
        for (final call in toolCalls)
          {
            ...call.extra,
            'id': call.id,
            'type': 'function',
            'function': {'name': call.name, 'arguments': call.arguments},
          },
      ],
    'tool_call_id': ?toolCallId,
  };

  /// 送回的 `reasoning_details`：Anthropic 與 Gemini 的思考文字沒有簽章的
  /// 不送（照 OpenRouter 官方的 AI SDK 套件：沒簽章的那家不收）。
  List<Object?> get _detailsToSend => [
    for (final detail in reasoningDetails)
      if (!(detail is Map &&
          detail['type'] == 'reasoning.text' &&
          detail['signature'] == null &&
          const {
            'anthropic-claude-v1',
            'google-gemini-v1',
          }.contains(detail['format'])))
        detail,
  ];
}

/// AI 呼叫的一個工具：[arguments] 是服務原樣給的參數 JSON 字串，[extra] 是
/// 服務在這個呼叫上多附的欄位（Gemini 的 `extra_content` 帶著思考簽章），
/// 送回時原樣附上：Gemini 3 以上少了簽章回 400。
final class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.extra = const {},
  });

  final String id;
  final String name;
  final String arguments;
  final Map<String, Object?> extra;

  @override
  bool operator ==(Object other) =>
      other is AiToolCall &&
      other.id == id &&
      other.name == name &&
      other.arguments == arguments &&
      jsonEncode(other.extra) == jsonEncode(extra);

  @override
  int get hashCode => Object.hash(id, name, arguments, jsonEncode(extra));

  @override
  String toString() => 'AiToolCall($id, $name, $arguments, $extra)';
}

/// 給 AI 用的工具：名稱、做什麼與參數（JSON Schema；沒有參數是空的）。
typedef AiTool = ({
  String name,
  String description,
  Map<String, Object?> parameters,
});

/// 送給服務的工具清單（OpenAI `chat/completions` 的 `tools`）。沒有參數的
/// 不送參數格式：OpenAI 的規格允許，沒列欄位的物件 Gemini 不收。
List<Map<String, Object?>> aiToolsJson(List<AiTool> tools) => [
  for (final tool in tools)
    {
      'type': 'function',
      'function': {
        'name': tool.name,
        'description': tool.description,
        if (tool.parameters.isNotEmpty) 'parameters': tool.parameters,
      },
    },
];

/// 一次回覆用了多少 token：送出的（其中 [cached] 打中服務的快取）、回覆的
/// （其中 [reasoning] 是思考）。服務沒回報的是 0。
typedef AiUsage = ({int prompt, int cached, int completion, int reasoning});

/// 一次回覆：[content] 是回的話，[toolCalls] 是呼叫的工具，[reasoning] 是
/// 服務送出的思考（沒有是空字串），[reasoningDetails] 與 [responseItems] 是
/// 服務要原樣送回的資料（[AiMessage]），[firstData] 是送出後多久收到第一段
/// 資料。
final class AiReply {
  const AiReply({
    required this.content,
    this.toolCalls = const [],
    this.reasoning = '',
    this.reasoningDetails = const [],
    this.responseItems = const [],
    this.usage,
    this.firstData = Duration.zero,
  });

  final String content;
  final List<AiToolCall> toolCalls;
  final String reasoning;
  final List<Object?> reasoningDetails;
  final List<Object?> responseItems;
  final AiUsage? usage;
  final Duration firstData;
}

/// AI 服務回了錯，或回的東西讀不懂；[message] 給使用者看。[retryable] 是
/// 一時的狀況（連線中斷、HTTP 408／429／5xx），整件重跑可能就好。[usage]
/// 是已經有輸出、還沒回完就斷了時估的用量（[_StreamReader.estimate]）：
/// 服務照樣計費，卻來不及回報。
class AiServiceException implements Exception {
  const AiServiceException(this.message, {this.retryable = false, this.usage});

  final String message;
  final bool retryable;
  final AiUsage? usage;

  @override
  String toString() => message;
}

/// AI 服務好好回了，但內容是空的：模型偶爾會這樣，再問一次通常就好。
class AiEmptyReply extends AiServiceException {
  const AiEmptyReply() : super('AI 服務回了空的內容');
}

/// 卡住：[AiCallLimits.stall] 沒有任何資料，或到了總時限還沒有任何輸出。
/// 多半是服務端的事，同一段對話原封不動重送。
class AiStalled extends AiServiceException {
  const AiStalled(super.message, {super.usage}) : super(retryable: true);
}

/// 失控：碰到單次輸出上限、超過總時限還在輸出，或連續好幾句都是前面出現
/// 過的句子。出在對話本身，整件換新對話重跑。[tail] 是思考與回覆各自的最後
/// 一段（[_StreamReader.tail]）。
class AiRunaway extends AiServiceException {
  const AiRunaway(super.message, {required this.tail, super.usage})
    : super(retryable: true);

  final String tail;
}

/// 一次呼叫的界線（`agent-harness` 技能的迴圈旋鈕），預設值的依據寫在
/// [AiAgentKnobs]。
typedef AiCallLimits = ({
  Duration stall,
  Duration total,
  int maxOutputChars,
  int repeatedSentences,
});

/// 呼叫使用者自己的 OpenAI 相容服務（ADR 0054），串流接收：不串流時分不出
/// 是斷線還是還在生成。服務不理 `stream`、回整份 JSON 的也照收。不經過書源
/// 的網路設定（Cookie、書源的標頭、限流），送的只有對話。
///
/// 一般走 `chat/completions`；服務網址是 OpenAI 官方時走 `responses`
/// （[usesResponses]）。
class AiChatClient {
  AiChatClient(this.service, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 60),
            ),
          );

  final AiService service;
  final Dio _dio;

  // 同一次 AI 修復共用，讓 OpenCode 將多輪對話路由到同一個 session。
  final String _opencodeSession = 'ses_${const Uuid().v4()}';

  /// 走 OpenAI 的 `responses`：GPT-6 Astra、GPT-6.1 Sol 在 `chat/completions`
  /// 不能用工具（OpenAI 官方文件），`responses` 也把加密的思考交回來、下一輪
  /// 原樣送回。只有 OpenAI 官方：其他相容服務多半只有 `chat/completions`。
  static bool usesResponses(String baseUrl) =>
      Uri.tryParse(_base(baseUrl))?.host == 'api.openai.com';

  /// 服務網址去掉結尾的 `/` 與使用者多填的 `/chat/completions`、`/responses`。
  static String _base(String baseUrl) {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    for (final tail in const ['/chat/completions', '/responses']) {
      if (url.endsWith(tail)) return url.substring(0, url.length - tail.length);
    }
    return url;
  }

  /// 送出的網址：服務網址後面接 `/chat/completions`（OpenAI 官方接
  /// `/responses`）；使用者已經填到這一段的不重複接。
  static String endpoint(String baseUrl) =>
      '${_base(baseUrl)}/${usesResponses(baseUrl) ? 'responses' : 'chat/completions'}';

  /// 服務列出的模型（OpenAI 相容的 `GET 服務網址/models`），照服務給的順序；
  /// AI 服務頁的模型選單用。不用金鑰也列得出的服務（OpenCode Go）照樣送
  /// 金鑰，各家都認。
  Future<List<String>> listModels() async {
    final uri = Uri.tryParse('${_base(service.baseUrl)}/models');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const AiServiceException('服務網址不對');
    }
    final Response<dynamic> response;
    try {
      response = await _dio.getUri<dynamic>(
        uri,
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            if (service.apiKey.isNotEmpty)
              'Authorization': 'Bearer ${service.apiKey}',
            'User-Agent': 'NightReader-AIRepair/1.0',
          },
        ),
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw AiServiceException(
        status == null ? '連不上服務：${error.type.name}' : '服務回了 $status',
      );
    }
    var data = response.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } on FormatException {
        throw const AiServiceException('服務回的模型清單讀不懂');
      }
    }
    final list = data is Map ? data['data'] : null;
    if (list is! List) throw const AiServiceException('服務回的模型清單讀不懂');
    return [
      for (final item in list)
        if (item is Map && item['id'] is String) item['id'] as String,
    ];
  }

  /// 不串流的回應最多收多少位元組：書源 JSON 加說明遠小於這個；再多就是
  /// 服務出了狀況，收下來只會佔滿記憶體。
  static const int maxResponseBytes = 2 * 1024 * 1024;

  /// 送出 [messages]，傳回 AI 回的話、呼叫的工具與思考。給了 [tools] 時帶上
  /// 工具清單，要不要呼叫由模型決定（不送 `tool_choice`，ADR 0054）：模型照
  /// 它訓練時的方式呼叫工具，服務解析好再交給我們。[limits] 沒給時用
  /// [AiAgentKnobs.call]。
  ///
  /// 不送 `temperature`（用模型預設）與 `max_tokens`（OpenAI 的新模型只認
  /// `max_completion_tokens`，送錯會被拒）：輸出上限在這裡數收到的字。
  Future<AiReply> complete(
    List<AiMessage> messages, {
    List<AiTool> tools = const [],
    CancelToken? cancelToken,
    AiCallLimits? limits,
  }) async {
    final bounds = limits ?? AiAgentKnobs.call;
    final guard = CancelToken();
    unawaited(
      cancelToken?.whenCancel.then((_) {
        if (!guard.isCancelled) guard.cancel('已停止');
      }),
    );
    final uri = Uri.tryParse(endpoint(service.baseUrl));
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const AiServiceException('服務網址不對，要以 https:// 開頭');
    }
    final responses = usesResponses(service.baseUrl);
    final watch = Stopwatch()..start();
    final reader = _StreamReader(
      bounds,
      responses: responses,
      promptChars: messages.fold(
        0,
        (sum, m) =>
            sum +
            m.content.length +
            m.reasoning.length +
            m.toolCalls.fold(0, (n, call) => n + call.arguments.length),
      ),
    );
    Timer? stall;
    Timer? total;
    AiServiceException? stopped;
    void stop(AiServiceException reason) {
      stopped ??= reason;
      if (!guard.isCancelled) guard.cancel(reason.message);
    }

    void armStall() {
      stall?.cancel();
      stall = Timer(bounds.stall, () {
        stop(
          AiStalled(
            'AI 服務 ${bounds.stall.inSeconds} 秒沒有送任何資料',
            usage: reader.estimate,
          ),
        );
      });
    }

    total = Timer(bounds.total, () {
      stop(
        reader.hasOutput
            ? AiRunaway(
                'AI 回覆超過 ${bounds.total.inSeconds} 秒還在輸出',
                tail: reader.tail,
                usage: reader.estimate,
              )
            : AiStalled('AI 服務 ${bounds.total.inSeconds} 秒都沒有回覆'),
      );
    });
    armStall();
    try {
      final Response<ResponseBody> response;
      try {
        response = await _dio.postUri<ResponseBody>(
          uri,
          data: responses
              ? _responsesBody(messages, tools)
              : _chatBody(messages, tools),
          options: Options(
            headers: {
              if (service.apiKey.isNotEmpty)
                'Authorization': 'Bearer ${service.apiKey}',
              // OpenCode Go 必須帶 session；一般額度也能用來維持路由與快取。
              // 僅對 OpenCode 官方推理端點送出，不影響其他相容服務。
              if (uri.host == 'opencode.ai' &&
                  uri.path.startsWith('/inference/')) ...{
                'x-opencode-session': _opencodeSession,
                'User-Agent': 'NightReader-AIRepair/1.0',
              },
            },
            contentType: Headers.jsonContentType,
            responseType: ResponseType.stream,
            validateStatus: (_) => true,
          ),
          cancelToken: guard,
        );
      } on DioException catch (error) {
        if (stopped case final reason?) throw reason;
        if (CancelToken.isCancel(error)) rethrow;
        throw AiServiceException(switch (error.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout => 'AI 服務太久沒回應',
          _ => '連不上 AI 服務（${uri.host}）',
        }, retryable: true);
      }
      final status = response.statusCode ?? 0;
      final body = response.data!;
      final type = response.headers.value(Headers.contentTypeHeader) ?? '';
      Duration? firstData;
      final bytes = <int>[];
      final decoder = const Utf8Decoder(allowMalformed: true)
          .startChunkedConversion(reader);
      try {
        await for (final chunk in body.stream) {
          firstData ??= watch.elapsed;
          armStall();
          if (status < 200 || status >= 300 || !type.contains('event-stream')) {
            bytes.addAll(chunk);
            if (bytes.length > maxResponseBytes) {
              throw const AiServiceException('AI 回的內容太長');
            }
          } else {
            decoder.add(chunk);
            if (reader.runaway case final reason?) throw reason;
          }
        }
        decoder.close();
      } on DioException catch (error) {
        if (stopped case final reason?) throw reason;
        if (CancelToken.isCancel(error)) rethrow;
        throw AiServiceException(
          'AI 服務的連線中斷了',
          retryable: true,
          usage: reader.estimate,
        );
      }
      if (stopped case final reason?) throw reason;
      if (status < 200 || status >= 300) {
        throw AiServiceException(
          _failure(status, _json(bytes), service.apiKey),
          retryable: status == 408 || status == 429 || status >= 500,
        );
      }
      if (!type.contains('event-stream')) reader.whole(_json(bytes));
      if (reader.error case final message?) {
        throw AiServiceException(
          'AI 服務出錯：${_withoutKey(message, service.apiKey)}',
          retryable: true,
        );
      }
      if (reader.runaway case final reason?) throw reason;
      final content = reader.content.toString();
      final toolCalls = reader.toolCalls;
      if (content.trim().isEmpty && toolCalls.isEmpty) {
        throw const AiEmptyReply();
      }
      return AiReply(
        content: content,
        toolCalls: toolCalls,
        reasoning: reader.reasoning.toString(),
        reasoningDetails: reader.reasoningDetails,
        responseItems: reader.responseItems,
        usage: reader.usage,
        firstData: firstData ?? watch.elapsed,
      );
    } on DioException catch (error) {
      if (stopped case final reason?) throw reason;
      if (CancelToken.isCancel(error)) rethrow;
      throw AiServiceException('連不上 AI 服務（${uri.host}）', retryable: true);
    } finally {
      stall?.cancel();
      total.cancel();
    }
  }

  /// `chat/completions` 的請求。
  Map<String, Object?> _chatBody(List<AiMessage> messages, List<AiTool> tools) {
    final withReasoning = messages.any(
      (m) => m.role == 'assistant' && m.reasoning.isNotEmpty,
    );
    return {
      'model': service.model,
      'messages': [
        for (final message in messages)
          message.toJson(withReasoning: withReasoning),
      ],
      if (tools.isNotEmpty) 'tools': aiToolsJson(tools),
      'stream': true,
      // 串流時用量只在要了才給（OpenAI、DeepSeek）；修復頁的 AI 用量靠它。
      'stream_options': {'include_usage': true},
      if (service.effort.isNotEmpty) 'reasoning_effort': service.effort,
    };
  }

  /// OpenAI `responses` 的請求：不存在 OpenAI 那邊（`store: false`），每輪送
  /// 整段對話；思考加密交回、原樣送回。工具不用嚴格模式：嚴格模式要每個
  /// 物件都列出全部欄位、全部必填，夜讀的參數多半可以不給。
  Map<String, Object?> _responsesBody(
    List<AiMessage> messages,
    List<AiTool> tools,
  ) => {
    'model': service.model,
    'input': responsesInput(messages),
    if (tools.isNotEmpty)
      'tools': [
        for (final tool in tools)
          {
            'type': 'function',
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.parameters.isEmpty
                ? const {'type': 'object', 'properties': <String, Object?>{}}
                : tool.parameters,
            'strict': false,
          },
      ],
    'stream': true,
    'store': false,
    'include': ['reasoning.encrypted_content'],
    if (service.effort.isNotEmpty) 'reasoning': {'effort': service.effort},
  };

  /// 對話換成 `responses` 的輸入項目：AI 的回覆有原本的輸出項目就照樣送回
  /// （順序不動，加密的思考也在裡面），沒有的照話與工具呼叫組出來。
  static List<Map<String, Object?>> responsesInput(List<AiMessage> messages) =>
      [
        for (final message in messages)
          ...switch (message.role) {
            'assistant' when message.responseItems.isNotEmpty => [
              for (final item in message.responseItems)
                if (item is Map<String, Object?>) item,
            ],
            'assistant' => [
              if (message.content.isNotEmpty)
                {'role': 'assistant', 'content': message.content},
              for (final call in message.toolCalls)
                {
                  'type': 'function_call',
                  'call_id': call.id,
                  'name': call.name,
                  'arguments': call.arguments,
                },
            ],
            'tool' => [
              {
                'type': 'function_call_output',
                'call_id': message.toolCallId,
                'output': message.content,
              },
            ],
            final role => [
              {'role': role, 'content': message.content},
            ],
          },
      ];

  static Object? _json(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException {
      return null;
    }
  }

  /// 回應裡的用量；沒有的欄位當 0。`chat/completions` 與 `responses` 的
  /// 欄位名不同，兩種都認。
  static AiUsage usageOf(Object? data) {
    int read(Object? value) => value is num ? value.toInt() : 0;
    Object? inner(Object? map, String key) => map is Map ? map[key] : null;
    final usage = switch (data) {
      {'usage': final Map<String, dynamic> usage} => usage,
      _ => const <String, dynamic>{},
    };
    return (
      prompt: read(usage['prompt_tokens'] ?? usage['input_tokens']),
      cached: read(
        usage['prompt_cache_hit_tokens'] ??
            inner(usage['prompt_tokens_details'], 'cached_tokens') ??
            inner(usage['input_tokens_details'], 'cached_tokens'),
      ),
      completion: read(usage['completion_tokens'] ?? usage['output_tokens']),
      reasoning: read(
        inner(usage['completion_tokens_details'], 'reasoning_tokens') ??
            inner(usage['output_tokens_details'], 'reasoning_tokens'),
      ),
    );
  }

  /// 服務的錯誤訊息有時把收到的金鑰原樣回顯（「Incorrect API key provided:
  /// sk-…」）：錯誤離開這裡之前換掉，畫面、紀錄與結果都看不到。
  static String _withoutKey(String text, String key) =>
      key.isEmpty ? text : text.replaceAll(key, aiRepairRedacted);

  static String _failure(int status, Object? data, String key) {
    final detail = switch (data) {
      {'error': {'message': final String message}} => message,
      {'error': final String message} => message,
      {'message': final String message} => message,
      _ => null,
    };
    final reason = switch (status) {
      401 || 403 => '金鑰不對或沒有權限',
      404 => '服務網址或模型名稱不對',
      402 => '額度用完',
      429 => '請求太頻繁或額度用完',
      _ => 'AI 服務出錯（$status）',
    };
    if (detail == null || detail.trim().isEmpty) return reason;
    // 先換掉金鑰再截短：截掉一半的金鑰認不出來。
    final short = _withoutKey(
      detail,
      key,
    ).trim().replaceAll(RegExp(r'\s+'), ' ');
    return '$reason：${short.length > 120 ? '${short.substring(0, 120)}…' : short}';
  }
}

/// 一律照做的迴圈機制用的數值（`agent-harness` 技能的旋鈕）。修復紀錄的開頭
/// 寫下實際生效的值。
abstract final class AiAgentKnobs {
  /// 一次呼叫：
  /// - 60 秒沒有任何資料（思考片段也算）就是卡住：技能的預設。
  /// - 總時限 300 秒：技能的預設；2026-11-10 對 12 個網站實跑 DeepSeek 時
  ///   最長的一輪不到 2 分鐘（當時的接收逾時是 4 分鐘，沒有碰到過）。
  /// - 輸出上限 10 萬字：技能的預設是 24,576 token，這裡數收到的字（不送
  ///   `max_tokens`）。中文約一字一 token、英文約四字母一 token，取英文那
  ///   一頭，寧可寬：正常輸出撞到上限會被當成失控重跑到失敗。一個書源的
  ///   改動加說明不到 1 萬字。
  /// - 連續 30 句都是前面出現過的句子是失控：技能的預設。
  ///
  /// 2026-11-12 量過（10 份完整紀錄、218 個正常回合，deepseek-v4.1-flash）：
  /// 正常回合最長輸出 15,595 字、最久 52 秒、第一段資料最慢 7.9 秒、最長連續
  /// 重複 10 句；兩次失控都是一直重複同一串標記，撞到 30 句。四個值都比正常
  /// 的最大值寬，不調。
  static const AiCallLimits call = (
    stall: Duration(seconds: 60),
    total: Duration(seconds: 300),
    maxOutputChars: 100000,
    repeatedSentences: 30,
  );

  /// 一件最多幾輪（技能的預設；之後照紀錄裡實際用到的輪數調）。
  static const int maxRounds = 36;

  /// 剩這麼多輪時，結果後面附上「剩 N 輪」。
  static const int warnRoundsLeft = 5;

  /// 一件含第一次最多跑幾次。技能的預設是 3；使用者 2026-11-12 看了實跑
  /// （蜘蛛小說網第 1 次 36 輪沒結果，再跑兩次多半一樣白燒）要先只跑一次，
  /// 等一次跑得通再談。
  static const int attempts = 1;

  /// 判未收斂的門檻（技能的預設）：連續幾輪沒有呼叫工具、連續幾次工具呼叫讀不懂、
  /// 同樣的指令與參數第幾次、交出連續被退幾次、連續卡住幾次就整件重跑。
  static const int noCommandLimit = 3;
  static const int badCommandLimit = 3;
  static const int sameCallLimit = 4;
  static const int rejectionLimit = 5;
  static const int stallLimit = 2;

  /// 寫進紀錄開頭的一行。
  static String get summary =>
      '卡住 ${call.stall.inSeconds} 秒、單次總時限 ${call.total.inSeconds} 秒、'
      '輸出上限 ${call.maxOutputChars} 字、重複 ${call.repeatedSentences} 句算失控、'
      '每件最多 $maxRounds 輪、剩 $warnRoundsLeft 輪起提醒、含第一次跑 $attempts 次、'
      '未收斂：沒有呼叫工具連續 $noCommandLimit 輪、呼叫讀不懂連續 $badCommandLimit 次、'
      '同樣參數第 $sameCallLimit 次、交出連續被退 $rejectionLimit 次、'
      '卡住連續 $stallLimit 次重跑、思考原樣放回對話';
}

/// 接收中的一個工具呼叫：編號與名稱用換的（服務每段都重送時不會接成
/// `fetchfetch`），參數用接的，同 OpenAI 官方套件。
final class _Call {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
  final Map<String, Object?> extra = {};
}

/// 讀 `text/event-stream`：每行 `data: {...}`，`[DONE]` 結束。邊讀邊數輸出
/// 的字與重複的句子，失控時記下原因（[runaway]），呼叫的地方停掉連線。
/// [responses] 是 OpenAI `responses` 的事件（每筆資料帶 `type`），否則是
/// `chat/completions` 的片段。
final class _StreamReader implements Sink<String> {
  _StreamReader(
    this.limits, {
    required this.responses,
    required this.promptChars,
  });

  final AiCallLimits limits;
  final bool responses;

  /// 送出的對話共幾字，估用量用（[estimate]）。
  final int promptChars;
  final StringBuffer content = StringBuffer();
  final StringBuffer reasoning = StringBuffer();

  /// 工具呼叫照收到的順序；[_byIndex] 是服務標的第幾個（`chat/completions`
  /// 的 `index`、`responses` 的 `output_index`）。
  final List<_Call> _calls = [];
  final Map<int, _Call> _byIndex = {};

  /// OpenRouter 的 `reasoning_details`，照它的官方套件接起來。
  final List<Map<String, Object?>> reasoningDetails = [];

  /// `responses` 的輸出項目，照 `output_index`。
  final Map<int, Map<String, Object?>> _items = {};
  AiUsage? usage;
  String? error;
  AiRunaway? runaway;
  String _pending = '';
  String _sentence = '';
  final Set<String> _seen = {};
  int _repeats = 0;

  bool get hasOutput =>
      content.isNotEmpty || reasoning.isNotEmpty || _calls.isNotEmpty;

  /// 呼叫的工具，照收到的順序。服務沒給編號的（Gemini 曾經給空的）補一個：
  /// 工具結果要照編號接回去。
  List<AiToolCall> get toolCalls => [
    for (final call in _calls)
      AiToolCall(
        id: call.id.isNotEmpty
            ? call.id
            : (call.id = 'call_${const Uuid().v4()}'),
        name: call.name,
        arguments: call.arguments.toString(),
        extra: Map.unmodifiable(call.extra),
      ),
  ];

  List<Object?> get responseItems => [
    for (final index in _items.keys.toList()..sort()) _items[index],
  ];

  int get _argumentChars =>
      _calls.fold(0, (sum, call) => sum + call.arguments.length);

  /// 思考、回覆與工具呼叫各自的最後 1,000 字，分開標出來：看得出失控出在
  /// 哪一段。
  String get tail {
    String last(String text) =>
        text.length <= 1000 ? text : text.substring(text.length - 1000);
    final calls = [for (final call in _calls) '${call.name} ${call.arguments}']
        .join('\n');
    return [
      if (reasoning.isNotEmpty) '思考的最後一段：\n${last('$reasoning')}',
      if (content.isNotEmpty) '回覆的最後一段：\n${last('$content')}',
      if (calls.isNotEmpty) '工具呼叫的最後一段：\n${last(calls)}',
    ].join('\n\n');
  }

  /// 還沒回完就斷了時的用量：服務回報過的照用；沒有輸出時是 null（多半還沒
  /// 開始計費）；其他照字數估，打中快取算 0。
  ///
  /// 每 token 算 2.5 字，寧可估多：2026-11-12 實跑
  /// 涨姿势（deepseek-v4.1-flash）第 1 輪送出 23,786 字是 9,180 token（2.6
  /// 字），思考加回覆 2,776 字是 738 token（3.8 字）。
  AiUsage? get estimate {
    if (usage case final reported?) return reported;
    if (!hasOutput) return null;
    int tokens(int chars) => (chars / _charsPerToken).ceil();
    return (
      prompt: tokens(promptChars),
      cached: 0,
      completion: tokens(content.length + reasoning.length + _argumentChars),
      reasoning: tokens(reasoning.length),
    );
  }

  static const double _charsPerToken = 2.5;

  @override
  void add(String data) {
    final text = _pending + data;
    final lines = text.split('\n');
    _pending = lines.removeLast();
    for (final line in lines) {
      _line(line.trimRight());
    }
  }

  @override
  void close() {
    if (_pending.isNotEmpty) _line(_pending.trimRight());
    _pending = '';
  }

  void _line(String line) {
    if (!line.startsWith('data:')) return;
    final payload = line.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return;
    final Object? json;
    try {
      json = jsonDecode(payload);
    } on FormatException {
      return;
    }
    if (json is! Map) return;
    if (responses) {
      _event(json);
    } else {
      _chunk(json);
    }
  }

  /// 整份 JSON 的回應（服務不理 `stream`）。
  void whole(Object? json) {
    if (json is! Map) return;
    if (responses) {
      _completed(json, whole: true);
      return;
    }
    if (json['usage'] is Map) usage = AiChatClient.usageOf(json);
    _chunk({...json, 'usage': null});
  }

  // ---- chat/completions ----

  void _chunk(Map<dynamic, dynamic> json) {
    if (json['error'] case final Object failure) {
      error = switch (failure) {
        {'message': final String message} => message,
        _ => '$failure',
      };
      return;
    }
    if (json['usage'] is Map) usage = AiChatClient.usageOf(json);
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) return;
    final choice = choices.first as Map;
    final delta = choice['delta'] ?? choice['message'];
    if (delta is Map) {
      // DeepSeek 的 reasoning_content、OpenRouter 的 reasoning。
      final thought = delta['reasoning_content'] ?? delta['reasoning'];
      if (thought is String && thought.isNotEmpty) _out(reasoning, thought);
      if (delta['reasoning_details'] case final List<Object?> details) {
        for (final detail in details) {
          if (detail is Map) _detail(detail);
        }
      }
      final said = delta['content'];
      if (said is String && said.isNotEmpty) _out(content, said);
      final calls = delta['tool_calls'];
      if (calls is List) {
        for (final call in calls) {
          if (call is Map) _callPiece(call);
        }
      }
    }
    if (choice['finish_reason'] == 'length') {
      runaway ??= AiRunaway('AI 回覆碰到服務的單次輸出上限', tail: tail, usage: estimate);
    }
  }

  /// 一段工具呼叫。有 `index` 的照它（同一個位置來了另一個編號就是新的
  /// 呼叫）；沒有的（Gemini 曾經不給）看編號，新
  /// 編號是新的呼叫；編號也沒有時，帶名稱的是新的呼叫（後續的片段只帶參數），
  /// 其他接在最後一個後面。參數只數字數（輸出上限），不數重複的句子。
  void _callPiece(Map<dynamic, dynamic> call) {
    final index = call['index'];
    final id = call['id'] is String ? call['id'] as String : '';
    final function = call['function'] is Map ? call['function'] as Map : null;
    final name = function?['name'] is String ? function!['name'] as String : '';
    final into = switch (index) {
      // 同一個位置換了編號是新的呼叫：有的服務每個呼叫都標 0。
      final int index
          when id.isEmpty ||
              _byIndex[index] == null ||
              _byIndex[index]!.id.isEmpty ||
              _byIndex[index]!.id == id =>
        _byIndex.putIfAbsent(index, _newCall),
      final int index => _byIndex[index] = _newCall(),
      _ when id.isNotEmpty =>
        _calls.where((c) => c.id == id).firstOrNull ?? _newCall(),
      _
          when name.isNotEmpty &&
              (_calls.isEmpty || _calls.last.name.isNotEmpty) =>
        _newCall(),
      _ => _calls.lastOrNull ?? _newCall(),
    };
    if (id.isNotEmpty) into.id = id;
    if (name.isNotEmpty) into.name = name;
    if (function?['arguments'] case final String arguments) {
      into.arguments.write(arguments);
    }
    for (final MapEntry(:key, :value) in call.entries) {
      if (key is String &&
          !const {'index', 'id', 'type', 'function'}.contains(key)) {
        into.extra[key] = value;
      }
    }
    _checkLength();
  }

  _Call _newCall() {
    final call = _Call();
    _calls.add(call);
    return call;
  }

  /// OpenRouter 的一段 `reasoning_details`：照它官方 AI SDK 套件的接法，不看
  /// `index`，看種類：思考文字接在最後一個還沒簽章的思考文字後面，簽章與格式
  /// 補上；摘要接在最後一個摘要後面；加密的各自一筆。
  void _detail(Map<dynamic, dynamic> piece) {
    final detail = {
      for (final MapEntry(:key, :value) in piece.entries)
        if (key is String) key: value,
    };
    final last = reasoningDetails.lastOrNull;
    switch (detail['type']) {
      case 'reasoning.text'
          when last != null &&
              last['type'] == 'reasoning.text' &&
              last['signature'] == null:
        last['text'] = '${last['text'] ?? ''}${detail['text'] ?? ''}';
        for (final key in const ['signature', 'format', 'id']) {
          if (detail[key] != null) last[key] ??= detail[key];
        }
      case 'reasoning.summary'
          when last != null && last['type'] == 'reasoning.summary':
        last['summary'] = '${last['summary'] ?? ''}${detail['summary'] ?? ''}';
      default:
        reasoningDetails.add(detail);
    }
  }

  // ---- responses ----

  /// `responses` 的一個串流事件。
  void _event(Map<dynamic, dynamic> json) {
    final position = json['output_index'] is int
        ? json['output_index'] as int
        : 0;
    switch (json['type']) {
      case 'response.output_text.delta':
        if (json['delta'] case final String delta) _out(content, delta);
      case 'response.reasoning_summary_text.delta' ||
          'response.reasoning_text.delta':
        if (json['delta'] case final String delta) _out(reasoning, delta);
      case 'response.output_item.added':
        if (json['item'] case final Map<dynamic, dynamic> item
            when item['type'] == 'function_call') {
          _responseCall(position, item);
        }
      case 'response.function_call_arguments.delta':
        if (json['delta'] case final String delta) {
          _byIndex.putIfAbsent(position, _newCall).arguments.write(delta);
          _checkLength();
        }
      case 'response.output_item.done':
        if (json['item'] case final Map<dynamic, dynamic> item) {
          _item(position, item);
        }
      case 'response.completed' || 'response.incomplete' || 'response.failed':
        if (json['response'] case final Map<dynamic, dynamic> response) {
          _completed(response, whole: false);
        }
      case 'error':
        error = switch (json) {
          {'message': final String message} => message,
          {'error': {'message': final String message}} => message,
          _ => '$json',
        };
    }
  }

  /// 一個工具呼叫開始了（或整份回應裡的一個）：`call_id` 是工具結果要接回
  /// 的編號。
  _Call _responseCall(int position, Map<dynamic, dynamic> item) {
    final call = _byIndex.putIfAbsent(position, _newCall);
    if (item['call_id'] case final String id when id.isNotEmpty) call.id = id;
    if (item['name'] case final String name when name.isNotEmpty) {
      call.name = name;
    }
    return call;
  }

  /// 一個完整的輸出項目：原樣留著送回（加密的思考以這裡的為準，開始時的
  /// 可能不完整）；工具呼叫的參數以這裡的為準。[whole] 是整份回應：話與
  /// 思考沒有串流片段，從項目裡讀。
  void _item(int position, Map<dynamic, dynamic> item, {bool whole = false}) {
    _items[position] = {
      for (final MapEntry(:key, :value) in item.entries)
        if (key is String) key: value,
    };
    switch (item['type']) {
      case 'function_call':
        final call = _responseCall(position, item);
        if (item['arguments'] case final String arguments) {
          call.arguments
            ..clear()
            ..write(arguments);
          _checkLength();
        }
      case 'message' when whole:
        for (final part
            in item['content'] is List ? item['content'] as List : const []) {
          if (part case {'type': 'output_text', 'text': final String text}) {
            _out(content, text);
          }
        }
      case 'reasoning' when whole:
        for (final part
            in item['summary'] is List ? item['summary'] as List : const []) {
          if (part case {'text': final String text}) _out(reasoning, text);
        }
    }
  }

  /// 回應結束（或整份回應）：用量、沒完成的原因、錯誤；整份回應的輸出項目
  /// 在這裡讀。
  void _completed(Map<dynamic, dynamic> response, {required bool whole}) {
    if (response['usage'] is Map) usage = AiChatClient.usageOf(response);
    if (whole && response['output'] is List) {
      for (final (position, item) in (response['output'] as List).indexed) {
        if (item is Map) _item(position, item, whole: true);
      }
    }
    if (response['error'] case {'message': final String message}) {
      error = message;
    }
    if (response['incomplete_details'] case {'reason': final reason}) {
      if (reason == 'max_output_tokens') {
        runaway ??= AiRunaway('AI 回覆碰到服務的單次輸出上限', tail: tail, usage: estimate);
      } else {
        error ??= 'AI 回覆沒有完成（$reason）';
      }
    }
  }

  // ---- 兩種共用 ----

  void _checkLength() {
    if (content.length + reasoning.length + _argumentChars >
        limits.maxOutputChars) {
      runaway ??= AiRunaway(
        'AI 回覆超過 ${limits.maxOutputChars} 字',
        tail: tail,
        usage: estimate,
      );
    }
  }

  void _out(StringBuffer into, String text) {
    into.write(text);
    _checkLength();
    if (runaway != null) return;
    for (final char in text.split('')) {
      if (_ends.contains(char)) {
        _endSentence();
      } else {
        _sentence += char;
      }
    }
  }

  void _endSentence() {
    final sentence = _sentence.trim();
    _sentence = '';
    // 太短的（「好。」「}」）正常也一直出現，不算。
    if (sentence.length < 8) return;
    if (_seen.add(sentence)) {
      _repeats = 0;
      return;
    }
    if (++_repeats >= limits.repeatedSentences) {
      runaway ??= AiRunaway(
        'AI 連續 ${limits.repeatedSentences} 句都是前面說過的',
        tail: tail,
        usage: estimate,
      );
    }
  }

  static const Set<String> _ends = {'。', '！', '？', '\n', '.', '!', '?'};
}

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
final class AiMessage {
  const AiMessage(
    this.role,
    this.content, {
    this.toolCalls = const [],
    this.toolCallId,
    this.reasoning = '',
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

  final String role;
  final String content;
  final List<AiToolCall> toolCalls;
  final String? toolCallId;
  final String reasoning;

  /// 送給服務的樣子（OpenAI 的 `chat/completions`）。思考放在
  /// `reasoning_content`（DeepSeek 的欄位；2026-11-12 OpenCode Go 的
  /// deepseek-v4.1-flash 實測收）。
  Map<String, Object?> toJson() => {
    'role': role,
    'content': toolCalls.isNotEmpty && content.isEmpty ? null : content,
    if (reasoning.isNotEmpty) 'reasoning_content': reasoning,
    if (toolCalls.isNotEmpty)
      'tool_calls': [
        for (final call in toolCalls)
          {
            'id': call.id,
            'type': 'function',
            'function': {'name': call.name, 'arguments': call.arguments},
          },
      ],
    'tool_call_id': ?toolCallId,
  };
}

/// AI 呼叫的一個工具：[arguments] 是服務原樣給的參數 JSON 字串。
typedef AiToolCall = ({String id, String name, String arguments});

/// 給 AI 用的工具：名稱、做什麼與參數（JSON Schema）。
typedef AiTool = ({
  String name,
  String description,
  Map<String, Object?> parameters,
});

/// 送給服務的工具清單（OpenAI 的 `tools`）。
List<Map<String, Object?>> aiToolsJson(List<AiTool> tools) => [
  for (final tool in tools)
    {
      'type': 'function',
      'function': {
        'name': tool.name,
        'description': tool.description,
        'parameters': tool.parameters,
      },
    },
];

/// 一次回覆用了多少 token：送出的（其中 [cached] 打中服務的快取）、回覆的
/// （其中 [reasoning] 是思考）。服務沒回報的是 0。
typedef AiUsage = ({int prompt, int cached, int completion, int reasoning});

/// 一次回覆：[content] 是回的話，[toolCalls] 是呼叫的工具，[reasoning] 是
/// 服務送出的思考（沒有是空字串），[firstData] 是送出後多久收到第一段資料。
typedef AiReply = ({
  String content,
  List<AiToolCall> toolCalls,
  String reasoning,
  AiUsage? usage,
  Duration firstData,
});

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

/// 呼叫使用者自己的 OpenAI 相容服務（`chat/completions`，ADR 0054），串流
/// 接收：不串流時分不出是斷線還是還在生成。服務不理 `stream`、回整份 JSON
/// 的也照收。不經過書源的網路設定（Cookie、書源的標頭、限流），送的只有
/// 對話。
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

  /// 送出的網址：服務網址後面接 `/chat/completions`；使用者已經填到這一段
  /// 的照用。
  static String endpoint(String baseUrl) {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url.endsWith('/chat/completions') ? url : '$url/chat/completions';
  }

  /// 服務列出的模型（OpenAI 相容的 `GET 服務網址/models`），照服務給的順序；
  /// AI 服務頁的模型選單用。不用金鑰也列得出的服務（OpenCode Go）照樣送
  /// 金鑰，各家都認。
  Future<List<String>> listModels() async {
    var base = service.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/chat/completions')) {
      base = base.substring(0, base.length - '/chat/completions'.length);
    }
    final uri = Uri.tryParse('$base/models');
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

  /// 送出 [messages]，傳回 AI 回的話、呼叫的工具與思考。給了 [tools] 時
  /// 每次回覆都要呼叫工具（`tool_choice: required`）：模型照它訓練時的方式
  /// 呼叫工具，服務解析好再交給我們（ADR 0054）。[limits] 沒給時用
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
    final watch = Stopwatch()..start();
    final reader = _StreamReader(
      bounds,
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
          data: {
            'model': service.model,
            'messages': [for (final message in messages) message.toJson()],
            if (tools.isNotEmpty) ...{
              'tools': aiToolsJson(tools),
              'tool_choice': 'required',
            },
            'stream': true,
            // 串流時用量只在要了才給（OpenAI、DeepSeek）；修復頁的 AI 用量靠它。
            'stream_options': {'include_usage': true},
            if (service.effort.isNotEmpty) 'reasoning_effort': service.effort,
          },
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
      return (
        content: content,
        toolCalls: toolCalls,
        reasoning: reader.reasoning.toString(),
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

  static Object? _json(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException {
      return null;
    }
  }

  /// 回應裡的用量；沒有的欄位當 0。
  static AiUsage usageOf(Object? data) {
    int read(Object? value) => value is num ? value.toInt() : 0;
    final usage = switch (data) {
      {'usage': final Map<String, dynamic> usage} => usage,
      _ => const <String, dynamic>{},
    };
    final prompt = usage['prompt_tokens_details'];
    final completion = usage['completion_tokens_details'];
    return (
      prompt: read(usage['prompt_tokens']),
      cached: read(
        usage['prompt_cache_hit_tokens'] ??
            (prompt is Map ? prompt['cached_tokens'] : null),
      ),
      completion: read(usage['completion_tokens']),
      reasoning: read(
        completion is Map ? completion['reasoning_tokens'] : null,
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

/// 讀 `text/event-stream`：每行 `data: {...}`，`[DONE]` 結束。邊讀邊數輸出
/// 的字與重複的句子，失控時記下原因（[runaway]），呼叫的地方停掉連線。
final class _StreamReader implements Sink<String> {
  _StreamReader(this.limits, {required this.promptChars});

  final AiCallLimits limits;

  /// 送出的對話共幾字，估用量用（[estimate]）。
  final int promptChars;
  final StringBuffer content = StringBuffer();
  final StringBuffer reasoning = StringBuffer();

  /// 工具呼叫照 `index` 一段一段接起來：id、名稱與參數。
  final Map<int, ({StringBuffer id, StringBuffer name, StringBuffer arguments})>
  _calls = {};
  AiUsage? usage;
  String? error;
  AiRunaway? runaway;
  String _pending = '';
  String _sentence = '';
  final Set<String> _seen = {};
  int _repeats = 0;

  bool get hasOutput =>
      content.isNotEmpty || reasoning.isNotEmpty || _calls.isNotEmpty;

  /// 呼叫的工具，照服務給的順序。
  List<AiToolCall> get toolCalls => [
    for (final index in _calls.keys.toList()..sort())
      (
        id: _calls[index]!.id.toString(),
        name: _calls[index]!.name.toString(),
        arguments: _calls[index]!.arguments.toString(),
      ),
  ];

  int get _argumentChars =>
      _calls.values.fold(0, (sum, call) => sum + call.arguments.length);

  /// 思考、回覆與工具呼叫各自的最後 1,000 字，分開標出來：看得出失控出在
  /// 哪一段。
  String get tail {
    String last(String text) =>
        text.length <= 1000 ? text : text.substring(text.length - 1000);
    final calls = [
      for (final call in toolCalls) '${call.name} ${call.arguments}',
    ].join('\n');
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
    _chunk(json);
  }

  void _chunk(Object? json) {
    if (json is! Map) return;
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
      final said = delta['content'];
      if (said is String && said.isNotEmpty) _out(content, said);
      final calls = delta['tool_calls'];
      if (calls is List) {
        for (final (position, call) in calls.indexed) {
          if (call is Map) _callPiece(call, position);
        }
      }
    }
    if (choice['finish_reason'] == 'length') {
      runaway ??= AiRunaway('AI 回覆碰到服務的單次輸出上限', tail: tail, usage: estimate);
    }
  }

  /// 整份 JSON 的回應（服務不理 `stream`）。
  void whole(Object? json) {
    if (json is Map && json['usage'] is Map) usage = AiChatClient.usageOf(json);
    _chunk(json is Map ? {...json, 'usage': null} : json);
  }

  /// 一段工具呼叫：串流時每段帶 `index`；整份回應的沒有，照位置。參數只數
  /// 字數（輸出上限），不數重複的句子。
  void _callPiece(Map<dynamic, dynamic> call, int position) {
    final index = call['index'] is int ? call['index'] as int : position;
    final into = _calls.putIfAbsent(
      index,
      () =>
          (id: StringBuffer(), name: StringBuffer(), arguments: StringBuffer()),
    );
    if (call['id'] case final String id) into.id.write(id);
    final function = call['function'];
    if (function is Map) {
      if (function['name'] case final String name) into.name.write(name);
      if (function['arguments'] case final String arguments) {
        into.arguments.write(arguments);
      }
    }
    _checkLength();
  }

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

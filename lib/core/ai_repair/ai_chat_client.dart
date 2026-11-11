import 'dart:async';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import 'ai_repair_prompt.dart';
import 'ai_repair_settings.dart';

/// 對話裡的一句：`system`、`user` 或 `assistant` 說的話。
typedef AiMessage = ({String role, String content});

/// 一次回覆用了多少 token：送出的（其中 [cached] 打中服務的快取）與回覆的。
/// 服務沒回報的是 0。
typedef AiUsage = ({int prompt, int cached, int completion});

/// AI 服務回了錯，或回的東西讀不懂；[message] 給使用者看。
class AiServiceException implements Exception {
  const AiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// AI 服務好好回了，但內容是空的：模型偶爾會這樣，再問一次通常就好。
class AiEmptyReply extends AiServiceException {
  const AiEmptyReply() : super('AI 服務回了空的內容');
}

/// 呼叫使用者自己的 OpenAI 相容服務（`chat/completions`，ADR 0054）。不經過
/// 書源的網路設定（Cookie、書源的標頭、限流），送的只有對話。
class AiChatClient {
  AiChatClient(this.service, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 60),
              // 大模型讀幾萬字的網頁再回一整份書源，要等一陣子。
              receiveTimeout: const Duration(minutes: 4),
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

  /// 一次回應最多收多少位元組：書源 JSON 加說明遠小於這個；再多就是服務
  /// 出了狀況，收下來只會佔滿記憶體。
  static const int maxResponseBytes = 2 * 1024 * 1024;

  /// 送出 [messages]，傳回 AI 回的那段話。
  /// [onUsage] 收到服務回報的用量（OpenAI 的 `usage`；快取打中的照
  /// DeepSeek 的 `prompt_cache_hit_tokens` 或 OpenAI 的
  /// `prompt_tokens_details.cached_tokens`）。
  Future<String> complete(
    List<AiMessage> messages, {
    CancelToken? cancelToken,
    void Function(AiUsage usage)? onUsage,
  }) async {
    // 收太多就停：自己的取消記號，外面停下時跟著取消。
    final guard = CancelToken();
    var tooLarge = false;
    unawaited(
      cancelToken?.whenCancel.then((_) {
        if (!guard.isCancelled) guard.cancel('已停止');
      }),
    );
    final uri = Uri.tryParse(endpoint(service.baseUrl));
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const AiServiceException('服務網址不對，要以 https:// 開頭');
    }
    final Response<dynamic> response;
    try {
      response = await _dio.postUri<dynamic>(
        uri,
        data: {
          'model': service.model,
          'messages': [
            for (final message in messages)
              {'role': message.role, 'content': message.content},
          ],
          'temperature': 0.2,
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
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
        cancelToken: guard,
        onReceiveProgress: (received, _) {
          if (received > maxResponseBytes && !guard.isCancelled) {
            tooLarge = true;
            guard.cancel('回應太大');
          }
        },
      );
    } on DioException catch (error) {
      if (tooLarge) throw const AiServiceException('AI 回的內容太長');
      if (CancelToken.isCancel(error)) rethrow;
      throw AiServiceException(switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => 'AI 服務太久沒回應',
        _ => '連不上 AI 服務（${uri.host}）',
      });
    }
    final status = response.statusCode ?? 0;
    final data = response.data;
    if (status < 200 || status >= 300) {
      throw AiServiceException(_failure(status, data));
    }
    if (onUsage != null) onUsage(usageOf(data));
    final content = switch (data) {
      {'choices': [{'message': {'content': final String content}}, ...]} =>
        content,
      _ => null,
    };
    if (content == null || content.trim().isEmpty) throw const AiEmptyReply();
    if (content.length > aiRepairMaxReplyLength) {
      throw const AiServiceException('AI 回的內容太長');
    }
    return content;
  }

  /// 回應裡的用量；沒有的欄位當 0。
  static AiUsage usageOf(Object? data) {
    int read(Object? value) => value is num ? value.toInt() : 0;
    final usage = switch (data) {
      {'usage': final Map<String, dynamic> usage} => usage,
      _ => const <String, dynamic>{},
    };
    final details = usage['prompt_tokens_details'];
    return (
      prompt: read(usage['prompt_tokens']),
      cached: read(
        usage['prompt_cache_hit_tokens'] ??
            (details is Map ? details['cached_tokens'] : null),
      ),
      completion: read(usage['completion_tokens']),
    );
  }

  static String _failure(int status, Object? data) {
    final detail = switch (data) {
      {'error': {'message': final String message}} => message,
      {'error': final String message} => message,
      {'message': final String message} => message,
      _ => null,
    };
    final reason = switch (status) {
      401 || 403 => '金鑰不對或沒有權限',
      404 => '服務網址或模型名稱不對',
      402 || 429 => '額度用完或請求太頻繁',
      _ => 'AI 服務出錯（$status）',
    };
    if (detail == null || detail.trim().isEmpty) return reason;
    final short = detail.trim().replaceAll(RegExp(r'\s+'), ' ');
    return '$reason：${short.length > 120 ? '${short.substring(0, 120)}…' : short}';
  }
}

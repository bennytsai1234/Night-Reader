import 'dart:async';

import 'package:dio/dio.dart';

import 'ai_repair_prompt.dart';
import 'ai_repair_settings.dart';

/// 對話裡的一句：`system`、`user` 或 `assistant` 說的話。
typedef AiMessage = ({String role, String content});

/// AI 服務回了錯，或回的東西讀不懂；[message] 給使用者看。
class AiServiceException implements Exception {
  const AiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
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
  Future<String> complete(
    List<AiMessage> messages, {
    CancelToken? cancelToken,
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
        },
        options: Options(
          headers: {
            if (service.apiKey.isNotEmpty)
              'Authorization': 'Bearer ${service.apiKey}',
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
    final content = switch (data) {
      {'choices': [{'message': {'content': final String content}}, ...]} =>
        content,
      _ => null,
    };
    if (content == null || content.trim().isEmpty) {
      throw const AiServiceException('AI 服務回了空的內容');
    }
    if (content.length > aiRepairMaxReplyLength) {
      throw const AiServiceException('AI 回的內容太長');
    }
    return content;
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

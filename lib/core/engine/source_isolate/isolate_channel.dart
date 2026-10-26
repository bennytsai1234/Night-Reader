import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';

/// 兩個 isolate 之間的請求（等回覆）與通知（不等回覆）。
///
/// 兩端各建一個，指向對方的 [SendPort]，再把自己 [ReceivePort] 收到的
/// 訊息交給 [receive]。同一個 isolate group 裡的物件可以直接傳；送不出去的
/// 結果或錯誤（帶著原生資源的物件）改送能傳的替代品，見 [_answer]。
final class IsolateChannel {
  IsolateChannel(
    this._remote, {
    required this._onRequest,
    required this._onNotice,
  });

  final SendPort _remote;
  final Future<Object?> Function(Object request) _onRequest;
  final void Function(Object notice) _onNotice;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;

  /// 送出 [request]，等對方的 `onRequest` 回覆。對方丟出的錯誤在這裡照原樣
  /// 丟出（送不過來時見 [IsolateTaskError]）。
  Future<Object?> request(Object request) {
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    try {
      _remote.send(_Request(id, request));
    } catch (_) {
      _pending.remove(id);
      rethrow;
    }
    return completer.future;
  }

  void notify(Object notice) => _remote.send(_Notice(notice));

  /// 對方不會再回覆了（isolate 結束）：還在等的請求都以 [error] 結束。
  void close(Object error) {
    final pending = [..._pending.values];
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(error);
    }
  }

  void receive(Object? message) {
    switch (message) {
      case _Request(:final id, :final body):
        unawaited(_answer(id, body));
      case _Reply(:final id, :final value, :final error, :final stackTrace):
        final completer = _pending.remove(id);
        if (completer == null) return;
        if (error == null) {
          completer.complete(value);
        } else {
          completer.completeError(
            error,
            stackTrace == null ? null : StackTrace.fromString(stackTrace),
          );
        }
      case _Notice(:final body):
        _onNotice(body);
    }
  }

  Future<void> _answer(int id, Object body) async {
    try {
      final value = await _onRequest(body);
      try {
        _remote.send(_Reply(id, value: value));
      } on ArgumentError catch (e) {
        _remote.send(
          _Reply(
            id,
            error: IsolateTaskError('結果無法傳回：$e'),
            stackTrace: StackTrace.current.toString(),
          ),
        );
      }
    } catch (error, stackTrace) {
      _sendError(id, error, stackTrace.toString());
    }
  }

  /// 錯誤原樣送回，呼叫端才能照錯誤種類處理（例如取消、網路錯誤）。送不
  /// 出去時先送只留種類與狀態碼的 [DioException]，再不行就只送文字。
  void _sendError(int id, Object error, String stackTrace) {
    for (final candidate in [error, ?_sendableDioException(error)]) {
      try {
        _remote.send(_Reply(id, error: candidate, stackTrace: stackTrace));
        return;
      } on ArgumentError {
        // 試下一個。
      }
    }
    _remote.send(
      _Reply(id, error: IsolateTaskError('$error'), stackTrace: stackTrace),
    );
  }
}

/// 另一個 isolate 的錯誤無法原樣傳回時，帶回它的文字。
final class IsolateTaskError implements Exception {
  const IsolateTaskError(this.message);

  final String message;

  @override
  String toString() => message;
}

DioException? _sendableDioException(Object error) {
  if (error is! DioException) return null;
  final options = RequestOptions(
    path: error.requestOptions.uri.toString(),
    method: error.requestOptions.method,
  );
  final response = error.response;
  final inner = error.error;
  return DioException(
    requestOptions: options,
    response: response == null
        ? null
        : Response<void>(
            requestOptions: options,
            statusCode: response.statusCode,
            statusMessage: response.statusMessage,
            // 留著轉址紀錄，才換算得出最後抓的網址（`finalUri`）。
            redirects: response.redirects,
          ),
    type: error.type,
    error: switch (inner) {
      null => null,
      SocketException(:final message) => SocketException(message),
      HttpException(:final message) => HttpException(message),
      HandshakeException(:final message) => HandshakeException(message),
      TimeoutException(:final message) => TimeoutException(message),
      _ => IsolateTaskError('$inner'),
    },
    message: error.message,
  );
}

final class _Request {
  const _Request(this.id, this.body);

  final int id;
  final Object body;
}

final class _Reply {
  const _Reply(this.id, {this.value, this.error, this.stackTrace});

  final int id;
  final Object? value;
  final Object? error;
  final String? stackTrace;
}

final class _Notice {
  const _Notice(this.body);

  final Object body;
}

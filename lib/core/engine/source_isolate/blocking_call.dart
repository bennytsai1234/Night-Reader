part of 'source_isolate.dart';

/// 規則 JS 裡要等的呼叫（`java.ajax`、`cache.get` 這類）：書源 isolate 整條
/// 停住，等網路 isolate（[SourceIo]）做完再繼續，規則 JS 拿到的就是結果
/// 本身，和 Legado 一樣（ADR 0034）。
///
/// 只有書源 isolate 能停住。主 isolate 停住畫面就卡死，網路 isolate 停住
/// 就沒有人替它做事；在這些地方呼叫 [run] 丟出 [BlockingCallUnavailable]。
abstract final class BlockingCall {
  static IsolateChannel? _channel;
  static Mailbox? _replies;

  static void _install(IsolateChannel channel, Mailbox replies) {
    _channel = channel;
    _replies = replies;
  }

  /// 這個 isolate 能不能停住等。
  static bool get available => _channel != null;

  /// 停住這個 isolate，交給網路 isolate 做 [task]，傳回它的結果：字串、
  /// 數字、布林、null，或由它們組成的 List 與 Map（照 JSON 的樣子），以及
  /// [Uint8List]。[task] 丟出的錯誤在這裡以 [BlockingCallError] 丟出。
  ///
  /// [task] 連同捕捉的變數會送到網路 isolate，要在只捕捉資料的頂層函式裡
  /// 建立（`CODING_STANDARDS.md` 背景執行）。它在網路 isolate 裡不能再
  /// 呼叫 [run]，也不能跑規則 JS。
  static Object? run(Future<Object?> Function() task) {
    final channel = _channel;
    final replies = _replies;
    if (channel == null || replies == null) {
      throw const BlockingCallUnavailable();
    }
    channel.notify(_Block(Zone.current[_taskIdZoneKey] as int?, task));
    return _Outcome.decode(replies.take());
  }
}

/// 不能停住的 isolate（主 isolate、網路 isolate）呼叫了 [BlockingCall.run]。
final class BlockingCallUnavailable implements Exception {
  const BlockingCallUnavailable();

  @override
  String toString() => '規則 JS 要等的呼叫只能在書源 isolate 裡執行';
}

/// [BlockingCall.run] 交出去的工作失敗了。
final class BlockingCallError implements Exception {
  const BlockingCallError(this.message, {required this.cancelled});

  final String message;

  /// 失敗是因為所在的書源工作被取消。
  final bool cancelled;

  @override
  String toString() => message;
}

/// 停住的 worker 從信箱拿到的結果：第一個位元組是種類，後面是內容。信箱
/// 只能放位元組，結果在網路 isolate 編好，在 worker 解開。
abstract final class _Outcome {
  static const int _json = 0;
  static const int _bytes = 1;
  static const int _error = 2;

  static Uint8List success(Object? value) => value is Uint8List
      ? _tagged(_bytes, value)
      : _tagged(_json, utf8.encode(jsonEncode(value)));

  static Uint8List failure(Object error) => _tagged(
    _error,
    utf8.encode(
      jsonEncode({
        'message': '$error',
        'cancelled':
            error is DioException && error.type == DioExceptionType.cancel,
      }),
    ),
  );

  static Object? decode(Uint8List outcome) {
    final content = Uint8List.sublistView(outcome, 1);
    switch (outcome[0]) {
      case _json:
        return jsonDecode(utf8.decode(content));
      case _bytes:
        return content;
      default:
        final error = jsonDecode(utf8.decode(content)) as Map;
        throw BlockingCallError(
          '${error['message']}',
          cancelled: error['cancelled'] == true,
        );
    }
  }

  static Uint8List _tagged(int tag, List<int> content) =>
      Uint8List(content.length + 1)
        ..[0] = tag
        ..setRange(1, content.length + 1, content);
}

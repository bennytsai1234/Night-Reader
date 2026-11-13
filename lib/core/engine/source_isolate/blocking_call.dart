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
    channel.notify(
      _Block(
        Zone.current[_taskIdZoneKey] as int?,
        task,
        requestLog: currentRequestLog?.settings,
      ),
    );
    final outcome = _Outcome.decode(replies.take());
    // 書源除錯與校驗要列出規則 JS 自己送的請求；它們在網路 isolate 送出，
    // 記下的網址（與回應）跟著結果回來，照順序接進這裡的紀錄。
    currentRequestLog?.merge(
      outcome.requestLines,
      outcome.transientResponses,
      otherPages: outcome.requestPages,
    );
    if (outcome.error case final error?) throw error;
    return outcome.value;
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

/// 停住的 worker 從信箱拿到的結果。信箱只能放位元組，結果在網路 isolate
/// 編好，在 worker 解開：第一個位元組是種類，接著四個位元組是請求紀錄
/// （[RequestLog] 的內容，JSON）的長度、紀錄，最後是內容。
final class _Outcome {
  const _Outcome(
    this.value,
    this.error,
    this.requestLines,
    this.transientResponses,
    this.requestPages,
  );

  final Object? value;
  final BlockingCallError? error;
  final List<String> requestLines;
  final int transientResponses;

  /// 完整的請求紀錄（`RequestLog.pages`）。
  final List<LoggedPage> requestPages;

  static const int _json = 0;
  static const int _bytes = 1;
  static const int _error = 2;

  static Uint8List success(Object? value, RequestLog? log) => value is Uint8List
      ? _encode(_bytes, log, value)
      : _encode(_json, log, utf8.encode(jsonEncode(value)));

  static Uint8List failure(Object error, RequestLog? log) => _encode(
    _error,
    log,
    utf8.encode(
      jsonEncode({
        'message': '$error',
        'cancelled':
            error is DioException && error.type == DioExceptionType.cancel,
      }),
    ),
  );

  static _Outcome decode(Uint8List outcome) {
    final logLength = ByteData.sublistView(
      outcome,
      1,
      5,
    ).getUint32(0, Endian.little);
    final log = jsonDecode(
      utf8.decode(Uint8List.sublistView(outcome, 5, 5 + logLength)),
    ) as Map;
    final lines = (log['lines'] as List).cast<String>();
    final transient = log['transient'] as int;
    final pages = [
      for (final page in log['pages'] as List) loggedPageFromJson(page),
    ];
    final content = Uint8List.sublistView(outcome, 5 + logLength);
    switch (outcome[0]) {
      case _json:
        return _Outcome(
          jsonDecode(utf8.decode(content)),
          null,
          lines,
          transient,
          pages,
        );
      case _bytes:
        return _Outcome(content, null, lines, transient, pages);
      default:
        final error = jsonDecode(utf8.decode(content)) as Map;
        return _Outcome(
          null,
          BlockingCallError(
            '${error['message']}',
            cancelled: error['cancelled'] == true,
          ),
          lines,
          transient,
          pages,
        );
    }
  }

  static Uint8List _encode(int tag, RequestLog? log, List<int> content) {
    final header = utf8.encode(
      jsonEncode({
        'lines': log?.lines ?? const <String>[],
        'transient': log?.transientResponses ?? 0,
        'pages': [...?log?.pages.map(loggedPageToJson)],
      }),
    );
    final out = Uint8List(5 + header.length + content.length);
    out[0] = tag;
    ByteData.sublistView(out, 1, 5).setUint32(0, header.length, Endian.little);
    out.setRange(5, 5 + header.length, header);
    out.setRange(5 + header.length, out.length, content);
    return out;
  }
}

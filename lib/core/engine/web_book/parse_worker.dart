import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:night_reader/core/services/app_log_service.dart';

/// 把書源頁面的解析交給一個常駐的背景 isolate，主 isolate 只收結果。
///
/// 只收規則裡沒有 JS、`@put`、`@get` 的解析（[isPureRule]）：這類規則只讀
/// 傳進去的 HTML 與書源，不碰網路、資料庫、Cookie，也不改書源或書籍的變數，
/// 在哪個 isolate 跑結果都一樣。帶 JS 的規則會經由 `java.*` 用到主 isolate 的
/// 網路與資料庫，維持原地解析（docs/research/source-engine-off-main-isolate.md）。
///
/// 只在 App 的主 isolate 開啟（`main.dart`）；測試、書源校驗這類已經在背景
/// 的 isolate 維持原地解析，不再多開一層。
abstract final class ParseWorker {
  static bool enabled = false;

  /// 在背景 isolate 完成的解析次數，給測試確認真的離開了主 isolate。
  @visibleForTesting
  static int completed = 0;

  static Future<SendPort>? _port;

  static final RegExp _impure = RegExp(
    r'@js:|<js>|\{\{|@put|@get|java\.',
    caseSensitive: false,
  );

  /// [rules] 全部可以離開主 isolate 解析時為 true。
  static bool isPureRule(Iterable<String?> rules) =>
      rules.every((rule) => rule == null || !_impure.hasMatch(rule));

  /// 在背景 isolate 執行 [task] 並回傳結果；沒開啟、送不出去或執行失敗時
  /// 回傳 null，由呼叫端改在原地解析（失敗時原地再跑一次，例外照原樣丟出）。
  ///
  /// [task] 連同它捕捉的變數會複製到背景 isolate，所以要在只捕捉書源、書籍與
  /// 字串的地方建立，不能捕捉回呼或資料庫連線。
  static Future<R?> run<R extends Object>(Future<R> Function() task) async {
    if (!enabled) return null;
    final reply = ReceivePort();
    try {
      final port = await (_port ??= _spawn());
      port.send((task, reply.sendPort));
      final (ok, value) = await reply.first as (bool, Object?);
      if (ok) {
        completed++;
        return value as R;
      }
      AppLog.w('ParseWorker task failed, parsing in place: $value');
    } catch (e) {
      AppLog.w('ParseWorker unavailable, parsing in place: $e');
    } finally {
      reply.close();
    }
    return null;
  }

  static Future<SendPort> _spawn() async {
    final ready = ReceivePort();
    try {
      await Isolate.spawn(_main, ready.sendPort, debugName: 'ParseWorker');
      return await ready.first as SendPort;
    } catch (_) {
      // 開不起來就整段改回原地解析，不在每次解析時重試。
      enabled = false;
      _port = null;
      rethrow;
    } finally {
      ready.close();
    }
  }

  static void _main(SendPort ready) {
    final requests = ReceivePort();
    ready.send(requests.sendPort);
    requests.listen((message) async {
      final (task, reply) = message as (Future<Object> Function(), SendPort);
      try {
        reply.send((true, await task()));
      } catch (e, stack) {
        reply.send((false, '$e\n$stack'));
      }
    });
  }
}

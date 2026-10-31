import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:night_reader/core/engine/analyze_rule.dart';
import 'package:night_reader/core/engine/js/js_extensions.dart';
import 'package:night_reader/core/engine/source_isolate/source_isolate.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/source/lenient_json.dart';
import 'package:night_reader/core/models/source/source_login_ui.dart';
import 'package:night_reader/core/services/source_interaction.dart';

/// 登入頁開著的這段時間：書源的登入程式（表單按鈕、右上角的登入、用程式
/// 產生的表單）在這段工作階段自己的書源 isolate 裡執行，關頁就結束它。
///
/// 不借用平常那四條書源 isolate：登入程式可能停在網頁上等使用者操作好幾
/// 分鐘，借用的那一條上其他書源的閱讀與下載會整條卡住（ADR 0034、0038）。
/// 這裡寫入的登入資料經由記憶體同步，其他書源 isolate 當下就看得到。
///
/// 這裡執行的書源程式可以要使用者操作（[SourceInteraction.runInteractive]）。
final class SourceLoginSession {
  SourceLoginSession._(this.source, this._worker);

  final BookSource source;

  /// 沒開書源 isolate 時（測試）是 null，原地執行。
  final SourceWorker? _worker;

  /// 開一段工作階段；開不起來時丟出錯誤。
  static Future<SourceLoginSession> open(BookSource source) async {
    if (!SourceIsolate.enabled) return SourceLoginSession._(source, null);
    final worker = await SourceWorker.spawn(
      debugName: 'SourceLogin',
      withDictionaries: false,
    );
    return SourceLoginSession._(source, worker);
  }

  /// 執行用程式產生的表單（`loginUi` 寫成 `@js:`），傳回表單的每一列。
  Future<List<SourceLoginRow>> loadScriptForm(String script) async =>
      SourceLoginUi.rowsFromJson(await _run(_scriptFormTask(source, script)));

  /// 按下表單的按鈕：執行書源的登入程式加上按鈕的 [action]，`result` 是
  /// 表單目前填的內容 [form]，同 Legado。
  Future<void> pressButton(
    String action,
    Map<String, String> form, {
    CancelToken? cancelToken,
  }) => _run(_buttonTask(source, action, form), cancelToken: cancelToken);

  /// 右上角的登入：存好表單內容（[form] 蓋過已存的同名欄位，按鈕存的其他
  /// 欄位留著），書源有 `login` 函式就執行它。傳回有沒有執行登入程式。
  Future<bool> submit(Map<String, String> form, {CancelToken? cancelToken}) =>
      _run(_submitTask(source, form), cancelToken: cancelToken);

  /// 結束工作階段；正在等使用者或網路的程式跟著停。
  void close() => _worker?.kill(StateError('登入頁已關閉'));

  Future<R> _run<R>(
    Future<R> Function(CancelToken cancelToken) task, {
    CancelToken? cancelToken,
  }) {
    final worker = _worker;
    if (worker == null) return task(cancelToken ?? CancelToken());
    return worker.run(task, cancelToken: cancelToken);
  }
}

/// 存表單內容：[form] 蓋過已存的同名欄位，其他欄位（書源按鈕自己存的，
/// 例如 token）留著。
Future<void> saveLoginForm(BookSource source, Map<String, String> form) async {
  final saved = await source.getLoginInfoMap() ?? const <String, String>{};
  await source.putLoginInfo(jsonEncode({...saved, ...form}));
}

// ── 在書源 isolate 執行的工作：只捕捉書源與字串（CODING_STANDARDS.md） ──

Future<Object?> Function(CancelToken) _scriptFormTask(
  BookSource source,
  String script,
) =>
    (_) => _interactive(source, (rule) {
      final value = rule.evalJS(script, null);
      return value is String ? decodeLenientJson(value) : value;
    });

Future<void> Function(CancelToken) _buttonTask(
  BookSource source,
  String action,
  Map<String, String> form,
) =>
    (_) => _interactive(source, (rule) {
      final loginJs = source.getLoginJs();
      rule.evalJS(loginJs == null ? action : '$loginJs\n$action', form);
    });

Future<bool> Function(CancelToken) _submitTask(
  BookSource source,
  Map<String, String> form,
) => (_) async {
  if (form.isNotEmpty) await saveLoginForm(source, form);
  final loginJs = source.getLoginJs();
  if (loginJs == null) return false;
  return _interactive(
    source,
    (rule) =>
        rule.evalJS(
          '$loginJs\n'
          "if (typeof login === 'function') { login.apply(this); true; } "
          'else { false; }',
          null,
        ) ==
        true,
  );
};

/// 在可以要使用者操作的情況下執行 [body]，等它觸發的寫入都寫完才結束：
/// 關頁就結束這條 isolate，沒寫完的會丟掉。
Future<R> _interactive<R>(BookSource source, R Function(AnalyzeRule) body) =>
    SourceInteraction.runInteractive(() async {
      final rule = AnalyzeRule(source: source);
      try {
        return body(rule);
      } finally {
        rule.dispose();
        await JsExtensions.settleWrites();
      }
    });

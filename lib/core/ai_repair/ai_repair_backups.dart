import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:night_reader/core/services/app_log_service.dart';

/// AI 改書源之前的那份（ADR 0054）：每個書源留最近一次，可以還原。存在這台
/// 手機 App 資料夾的一個檔裡，不進備份、不同步：是上一次操作的復原，不是
/// 書源的資料。寫入照呼叫的順序排隊。
class AiRepairBackups {
  AiRepairBackups({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static final AiRepairBackups instance = AiRepairBackups();

  static const String fileName = 'ai_repair_previous.json';

  final Future<Directory> Function() _directory;
  Future<void> _queue = Future<void>.value();
  Map<String, Map<String, dynamic>>? _cache;

  /// 這個書源 AI 改之前的那份；沒有時是 null。
  Future<Map<String, dynamic>?> get(String sourceUrl) async =>
      (await _load())[sourceUrl];

  /// 留著改前版本的書源網址。
  Future<Set<String>> urls() async => (await _load()).keys.toSet();

  /// 記下 AI 改之前的 [sourceJson]，取代這個書源之前留的。
  Future<void> put(String sourceUrl, Map<String, dynamic> sourceJson) =>
      _update((all) => all[sourceUrl] = sourceJson);

  Future<void> remove(String sourceUrl) =>
      _update((all) => all.remove(sourceUrl));

  /// 只留 [existing] 裡還在的書源；刪掉的書源它的改前版本也刪。
  Future<void> keepOnly(Set<String> existing) =>
      _update((all) => all.removeWhere((url, _) => !existing.contains(url)));

  Future<Map<String, Map<String, dynamic>>> _load() async {
    await _queue;
    return _cache ??= await _read();
  }

  Future<void> _update(void Function(Map<String, Map<String, dynamic>>) edit) {
    final next = _queue.then((_) async {
      final all = _cache ?? await _read();
      final snapshot = jsonEncode(all);
      edit(all);
      _cache = all;
      if (jsonEncode(all) == snapshot) return;
      final file = await _file();
      if (all.isEmpty) {
        if (await file.exists()) await file.delete();
        return;
      }
      await file.writeAsString(jsonEncode(all), flush: true);
    });
    _queue = next.catchError((Object error, StackTrace stack) {
      AppLog.e('寫 AI 修書源的改前版本失敗', error: error, stackTrace: stack);
    });
    return next;
  }

  Future<Map<String, Map<String, dynamic>>> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return {};
      return {
        for (final MapEntry(:key, :value) in decoded.entries)
          if (value is Map<String, dynamic>) key: value,
      };
    } catch (error, stack) {
      AppLog.e('讀 AI 修書源的改前版本失敗', error: error, stackTrace: stack);
      return {};
    }
  }

  Future<File> _file() async =>
      File('${(await _directory()).path}${Platform.pathSeparator}$fileName');
}

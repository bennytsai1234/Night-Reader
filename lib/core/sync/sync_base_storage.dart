import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'sync_records.dart';

/// 每種資料上次同步時的樣子（[SyncBaseEntry]），存在這台手機的 App 資料夾，
/// 一種資料一個檔。換同步空間或帳號時清掉，下次照「從沒同步過」合併。
class SyncBaseStorage {
  SyncBaseStorage({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _directory;

  static Future<Directory> _defaultDirectory() async =>
      Directory(p.join((await getApplicationSupportDirectory()).path, 'sync'));

  Future<File> _file(String name) async =>
      File(p.join((await _directory()).path, '$name.json'));

  Future<Map<String, SyncBaseEntry>> read(String kind) async => {
    for (final entry in (await readJson('base_$kind')).entries)
      entry.key: ?SyncBaseEntry.fromJson(entry.value),
  };

  Future<void> write(String kind, Map<String, SyncBaseEntry> base) => writeJson(
    'base_$kind',
    {for (final entry in base.entries) entry.key: entry.value.toJson()},
  );

  /// 同一個資料夾裡其他跟著同步空間的檔（例如別台的閱讀統計）；換同步空間
  /// 時一起清掉（[clear]）。
  Future<Map<String, Object?>> readJson(String name) async {
    final file = await _file(name);
    if (!await file.exists()) return {};
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map
          ? {for (final e in json.entries) '${e.key}': e.value}
          : {};
    } on FormatException {
      // 寫到一半被關掉的檔：當成從沒同步過，下次照最後修改時間合併。
      return {};
    }
  }

  Future<void> writeJson(String name, Map<String, Object?> json) async {
    final file = await _file(name);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    await temp.rename(file.path);
  }

  Future<void> clear() async {
    final directory = await _directory();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

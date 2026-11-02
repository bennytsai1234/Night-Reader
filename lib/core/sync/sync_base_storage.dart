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

  Future<File> _file(String kind) async =>
      File(p.join((await _directory()).path, 'base_$kind.json'));

  Future<Map<String, SyncBaseEntry>> read(String kind) async {
    final file = await _file(kind);
    if (!await file.exists()) return {};
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return {};
      return {
        for (final entry in json.entries)
          '${entry.key}': ?SyncBaseEntry.fromJson(entry.value),
      };
    } on FormatException {
      // 寫到一半被關掉的檔：當成從沒同步過，下次照最後修改時間合併。
      return {};
    }
  }

  Future<void> write(String kind, Map<String, SyncBaseEntry> base) async {
    final file = await _file(kind);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        for (final entry in base.entries) entry.key: entry.value.toJson(),
      }),
      flush: true,
    );
    await temp.rename(file.path);
  }

  Future<void> clear() async {
    final directory = await _directory();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

import 'dart:convert';

import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/storage/app_storage_paths.dart';
import 'package:share_plus/share_plus.dart';

/// 把書源存成 JSON 檔、用系統分享傳出去（同 Legado 的分享）：書源管理的
/// 「分享選中」與 AI 建立書源的「分享這個書源」。
Future<void> shareBookSources(
  List<BookSource> sources, {
  String fileName = 'sources',
}) async {
  final jsonStr = jsonEncode(sources.map((s) => s.toJson()).toList());
  final baseName = _exportBaseName(fileName);
  final file = await AppStoragePaths.shareExportFile('$baseName.json');
  await file.writeAsString(jsonStr);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: '分享夜讀書源 ($baseName.json)'),
  );
}

String _exportBaseName(String fileName) {
  var baseName = fileName
      .replaceAll(RegExp(r'\.(legado|json)$', caseSensitive: false), '')
      .trim()
      .replaceAll(RegExp(r'[\x00-\x1F\x7F\\/:*?"<>|]'), '_')
      .trim();
  if (baseName.isEmpty || baseName == '.' || baseName == '..') {
    baseName = 'source';
  }
  return baseName;
}

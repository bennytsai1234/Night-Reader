import 'dart:convert';

import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/shared/share_json_file.dart';

/// 匯出、分享書源的 JSON：Legado 讀得懂的樣子，開關寫 `true`／`false`
/// （[BookSource.toLegadoJson]）。
String encodeBookSources(Iterable<BookSource> sources) =>
    jsonEncode([for (final source in sources) source.toLegadoJson()]);

/// 把書源存成 JSON 檔、用系統分享傳出去（同 Legado 的分享）：書源管理的
/// 「分享選中」與 AI 建立書源的「分享這個書源」。
Future<void> shareBookSources(
  List<BookSource> sources, {
  String fileName = 'sources',
}) => shareJsonFile(
  encodeBookSources(sources),
  fileName: fileName,
  fallbackName: 'source',
  what: '書源',
);

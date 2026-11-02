import 'package:night_reader/core/database/dao/highlight_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/highlight.dart';

import 'sync_kind.dart';
import 'sync_records.dart';

/// 標註的同步：一個標註一筆，用編號對上，刪除也同步（同書籤，ADR 0044）。
class HighlightSync extends SyncKind {
  HighlightSync({HighlightDao? dao}) : _dao = dao ?? getIt<HighlightDao>();

  final HighlightDao _dao;

  static const String kind = 'highlights';

  @override
  String get name => kind;

  static SyncRecord recordOf(Highlight highlight) =>
      SyncRecord(time: 0, data: highlight.toJson()..remove('id'));

  /// 標註的內容是「哪本書、哪一章（章名）的第幾個字起、畫了哪段字、什麼
  /// 顏色與樣子」。章節序號與錨點同書籤，只是這台目錄裡的座標，不算改過。
  @override
  String fingerprint(SyncRecord record) {
    if (record.deleted) return record.fingerprint;
    final data = record.data;
    final title = data['chapterTitle'];
    final hasTitle = title is String && title.trim().isNotEmpty;
    return SyncRecord.fingerprintOf({
      'bookName': data['bookName'],
      'bookAuthor': data['bookAuthor'],
      if (hasTitle) 'chapterTitle': title.trim(),
      if (!hasTitle) 'chapterIndex': data['chapterIndex'],
      'charOffset': data['charOffset'],
      'quote': data['quote'],
      'color': data['color'],
      'style': data['style'],
    });
  }

  @override
  Future<Map<String, SyncRecord>> local() async => {
    for (final highlight in await _dao.getAll())
      '${highlight.id}': recordOf(highlight),
  };

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final upserts = <Highlight>[];
    final deleted = <int>[];
    final applied = <String, SyncRecord>{};
    for (final MapEntry(:key, value: record) in remote.entries) {
      final id = int.tryParse(key);
      if (id == null || id <= 0) continue;
      if (record.deleted) {
        deleted.add(id);
        applied[key] = record;
      } else {
        final highlight = Highlight.fromJson({...record.data, 'id': id});
        upserts.add(highlight);
        applied[key] = recordOf(highlight);
      }
    }
    if (upserts.isNotEmpty) await _dao.upsertAll(upserts);
    if (deleted.isNotEmpty) await _dao.deleteByIds(deleted);
    return applied;
  }
}

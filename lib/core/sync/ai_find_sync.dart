import 'package:night_reader/core/database/dao/ai_find_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/ai_find_record.dart';

import 'sync_kind.dart';
import 'sync_records.dart';

/// 過去的找書的同步（ADR 0060）：一次找書一筆，用開始時配的編號對上；
/// 新的贏、刪除也同步（同標註，ADR 0039、0046）。
class AiFindSync extends SyncKind {
  AiFindSync({AiFindDao? dao}) : _dao = dao ?? getIt<AiFindDao>();

  final AiFindDao _dao;

  static const String kind = 'aiFinds';

  @override
  String get name => kind;

  static SyncRecord recordOf(AiFindRecord record) =>
      SyncRecord(time: 0, data: record.toJson()..remove('id'));

  @override
  Future<Map<String, SyncRecord>> local() async => {
    for (final record in await _dao.getAll()) record.id: recordOf(record),
  };

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final upserts = <AiFindRecord>[];
    final deleted = <String>[];
    final applied = <String, SyncRecord>{};
    for (final MapEntry(:key, value: record) in remote.entries) {
      if (key.isEmpty) continue;
      if (record.deleted) {
        deleted.add(key);
        applied[key] = record;
      } else {
        final find = AiFindRecord.fromJson({...record.data, 'id': key});
        upserts.add(find);
        applied[key] = recordOf(find);
      }
    }
    if (upserts.isNotEmpty) await _dao.upsertAll(upserts);
    if (deleted.isNotEmpty) await _dao.deleteByIds(deleted);
    return applied;
  }
}

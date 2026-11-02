import 'package:night_reader/core/database/dao/replace_rule_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/replace_rule.dart';

import 'sync_kind.dart';
import 'sync_records.dart';

/// 替換規則的同步：一條規則一筆，用編號對上（ADR 0039）。新規則的編號是
/// 建立的時間（`ReplaceRuleDao`），兩台各自新增的不會撞號；更早以前新增
/// 的規則編號是 1、2、3……，兩台都有同一號時，第一次同步才分辨是不是同一條。
class ReplaceRuleSync extends SyncKind {
  ReplaceRuleSync({ReplaceRuleDao? dao})
    : _dao = dao ?? getIt<ReplaceRuleDao>();

  final ReplaceRuleDao _dao;

  /// 比這個小的編號是照順序配的舊編號，不是建立時間（2001 年以後的毫秒數
  /// 都比它大）。
  static const int _firstTimeId = 1000000000000;

  static const String kind = 'replace_rules';

  @override
  String get name => kind;

  static SyncRecord recordOf(ReplaceRule rule) =>
      SyncRecord(time: 0, data: rule.toJson()..remove('id'));

  /// 規則本身（找什麼、換成什麼、套用在哪）；排序和開關不算，兩台排在不同
  /// 位置、一台關掉的還是同一條。
  static String identityOf(SyncRecord record) {
    final data = Map.of(record.data)
      ..remove('order')
      ..remove('isEnabled');
    return SyncRecord.fingerprintOf(data);
  }

  @override
  Future<Map<String, SyncRecord>> local() async => {
    for (final rule in await _dao.getAll()) '${rule.id}': recordOf(rule),
  };

  /// 這台還沒和雲端同步過的規則（[base] 沒有它），和雲端整批一對一對齊
  /// 編號：
  ///
  /// - 同號就是同一條：不動。
  /// - 雲端有另一個編號的同一條規則（還沒被別條配走）：改用雲端的編號，
  ///   不重複；兩台互換編號的也對得上。
  /// - 雲端的同一號是另一條規則，或這個編號要讓給別條：這台的換一個新編號，
  ///   兩條都留。舊編號的規則在雲端被刪掉時也一樣，因為分不出被刪的是不是
  ///   同一條。
  @override
  Future<Map<String, SyncRecord>> reconcile(
    Map<String, SyncRecord> local,
    Map<String, SyncRecord> remote,
    Map<String, SyncBaseEntry> base,
  ) async {
    final pending = {
      for (final MapEntry(:key, :value) in local.entries)
        if (!base.containsKey(key) && int.tryParse(key) != null) key: value,
    };
    if (pending.isEmpty) return local;

    bool sameRule(String key) {
      final theirs = remote[key];
      return theirs != null &&
          !theirs.deleted &&
          identityOf(theirs) == identityOf(pending[key]!);
    }

    final unsettled = [
      for (final key in pending.keys)
        if (!sameRule(key)) key,
    ];
    // 可以讓這台的規則改用的雲端編號：這台沒有這個編號，或佔著它的也還沒
    // 對齊、會被換走。
    final free = <String, List<String>>{};
    for (final MapEntry(:key, value: record) in remote.entries) {
      if (record.deleted) continue;
      if (local.containsKey(key) && !unsettled.contains(key)) continue;
      (free[identityOf(record)] ??= []).add(key);
    }

    final mapping = <int, int?>{};
    for (final key in unsettled) {
      final candidates = free[identityOf(pending[key]!)];
      if (candidates == null || candidates.isEmpty) continue;
      mapping[int.parse(key)] = int.parse(candidates.removeAt(0));
    }
    final claimed = mapping.values.toSet();
    for (final key in unsettled) {
      final id = int.parse(key);
      if (mapping.containsKey(id)) continue;
      final theirs = remote[key];
      final collides =
          claimed.contains(id) ||
          (theirs != null && (!theirs.deleted || id < _firstTimeId));
      if (collides) mapping[id] = null;
    }
    if (mapping.isEmpty) return local;

    final targets = await _dao.changeIds(
      mapping,
      avoid: {
        for (final key in {...local.keys, ...remote.keys}) ?int.tryParse(key),
      },
    );
    final aligned = Map.of(local)
      ..removeWhere((key, _) => targets.containsKey(int.tryParse(key)));
    for (final MapEntry(key: from, value: to) in targets.entries) {
      aligned['$to'] = local['$from']!;
    }
    return aligned;
  }

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final upserts = <ReplaceRule>[];
    final deleted = <int>[];
    final applied = <String, SyncRecord>{};
    for (final MapEntry(:key, value: record) in remote.entries) {
      final id = int.tryParse(key);
      if (id == null || id <= 0) continue;
      if (record.deleted) {
        deleted.add(id);
        applied[key] = record;
      } else {
        final rule = ReplaceRule.fromJson({...record.data, 'id': id});
        upserts.add(rule);
        // 這次寫進去的樣子；寫完才又被編輯的，下次同步比得出來。
        applied[key] = recordOf(rule);
      }
    }
    if (upserts.isNotEmpty) await _dao.upsertAll(upserts);
    if (deleted.isNotEmpty) await _dao.deleteByIds(deleted);
    return applied;
  }
}

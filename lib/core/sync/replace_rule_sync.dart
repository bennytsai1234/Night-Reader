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

  /// 這台還沒和雲端同步過的規則（[base] 沒有它），和雲端對齊編號：
  ///
  /// - 雲端有另一個編號的同一條規則：改用雲端的編號，不重複。
  /// - 雲端的同一號是另一條規則：這台的換一個新編號，兩條都留。舊編號的
  ///   規則在雲端被刪掉時也一樣，因為分不出被刪的是不是同一條。
  @override
  Future<Map<String, SyncRecord>> reconcile(
    Map<String, SyncRecord> local,
    Map<String, SyncRecord> remote,
    Map<String, SyncBaseEntry> base,
  ) async {
    final unmatched = <String, String>{};
    for (final MapEntry(:key, value: record) in remote.entries) {
      if (record.deleted || local.containsKey(key)) continue;
      unmatched.putIfAbsent(identityOf(record), () => key);
    }
    final aligned = Map.of(local);
    for (final MapEntry(:key, value: record) in local.entries) {
      if (base.containsKey(key)) continue;
      final id = int.tryParse(key);
      if (id == null) continue;
      final theirs = remote[key];
      final sameRule =
          theirs != null &&
          !theirs.deleted &&
          identityOf(theirs) == identityOf(record);
      if (sameRule) continue;
      final collides = theirs != null && (!theirs.deleted || id < _firstTimeId);
      final target = switch (unmatched.remove(identityOf(record))) {
        final match? => int.parse(match),
        null when collides => await _unusedId({
          ...aligned.keys,
          ...remote.keys,
        }),
        null => null,
      };
      if (target == null) continue;
      await _dao.changeId(id, target);
      aligned
        ..remove(key)
        ..['$target'] = record;
    }
    return aligned;
  }

  Future<int> _unusedId(Set<String> taken) async {
    var id = await _dao.newId();
    while (taken.contains('$id')) {
      id++;
    }
    return id;
  }

  @override
  Future<Map<String, SyncRecord>> apply(Map<String, SyncRecord> remote) async {
    final upserts = <ReplaceRule>[];
    for (final MapEntry(:key, value: record) in remote.entries) {
      final id = int.tryParse(key);
      if (id == null || id <= 0) continue;
      if (record.deleted) {
        await _dao.deleteById(id);
      } else {
        upserts.add(ReplaceRule.fromJson({...record.data, 'id': id}));
      }
    }
    if (upserts.isNotEmpty) await _dao.upsertAll(upserts);
    final after = {for (final rule in await _dao.getAll()) '${rule.id}': rule};
    return {
      for (final key in remote.keys)
        if (int.tryParse(key) case final id? when id > 0)
          key: switch (after[key]) {
            final stored? => recordOf(stored),
            null => const SyncRecord(time: 0, data: {}, deleted: true),
          },
    };
  }
}

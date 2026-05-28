// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dict_rule_dao.dart';

// ignore_for_file: type=lint
mixin _$DictRuleDaoMixin on DatabaseAccessor<AppDatabase> {
  $DictRulesTable get dictRules => attachedDatabase.dictRules;
  DictRuleDaoManager get managers => DictRuleDaoManager(this);
}

class DictRuleDaoManager {
  final _$DictRuleDaoMixin _db;
  DictRuleDaoManager(this._db);
  $$DictRulesTableTableManager get dictRules =>
      $$DictRulesTableTableManager(_db.attachedDatabase, _db.dictRules);
}

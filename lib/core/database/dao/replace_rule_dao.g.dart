// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'replace_rule_dao.dart';

// ignore_for_file: type=lint
mixin _$ReplaceRuleDaoMixin on DatabaseAccessor<AppDatabase> {
  $ReplaceRulesTable get replaceRules => attachedDatabase.replaceRules;
  ReplaceRuleDaoManager get managers => ReplaceRuleDaoManager(this);
}

class ReplaceRuleDaoManager {
  final _$ReplaceRuleDaoMixin _db;
  ReplaceRuleDaoManager(this._db);
  $$ReplaceRulesTableTableManager get replaceRules =>
      $$ReplaceRulesTableTableManager(_db.attachedDatabase, _db.replaceRules);
}

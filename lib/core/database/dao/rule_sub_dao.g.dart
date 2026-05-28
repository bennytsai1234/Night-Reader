// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rule_sub_dao.dart';

// ignore_for_file: type=lint
mixin _$RuleSubDaoMixin on DatabaseAccessor<AppDatabase> {
  $RuleSubsTable get ruleSubs => attachedDatabase.ruleSubs;
  RuleSubDaoManager get managers => RuleSubDaoManager(this);
}

class RuleSubDaoManager {
  final _$RuleSubDaoMixin _db;
  RuleSubDaoManager(this._db);
  $$RuleSubsTableTableManager get ruleSubs =>
      $$RuleSubsTableTableManager(_db.attachedDatabase, _db.ruleSubs);
}

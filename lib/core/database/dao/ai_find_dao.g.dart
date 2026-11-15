// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_find_dao.dart';

// ignore_for_file: type=lint
mixin _$AiFindDaoMixin on DatabaseAccessor<AppDatabase> {
  $AiFindRecordsTable get aiFindRecords => attachedDatabase.aiFindRecords;
  AiFindDaoManager get managers => AiFindDaoManager(this);
}

class AiFindDaoManager {
  final _$AiFindDaoMixin _db;
  AiFindDaoManager(this._db);
  $$AiFindRecordsTableTableManager get aiFindRecords =>
      $$AiFindRecordsTableTableManager(_db.attachedDatabase, _db.aiFindRecords);
}

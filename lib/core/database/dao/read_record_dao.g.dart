// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'read_record_dao.dart';

// ignore_for_file: type=lint
mixin _$ReadRecordDaoMixin on DatabaseAccessor<AppDatabase> {
  $ReadRecordsTable get readRecords => attachedDatabase.readRecords;
  ReadRecordDaoManager get managers => ReadRecordDaoManager(this);
}

class ReadRecordDaoManager {
  final _$ReadRecordDaoMixin _db;
  ReadRecordDaoManager(this._db);
  $$ReadRecordsTableTableManager get readRecords =>
      $$ReadRecordsTableTableManager(_db.attachedDatabase, _db.readRecords);
}

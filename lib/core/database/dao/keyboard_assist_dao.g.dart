// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'keyboard_assist_dao.dart';

// ignore_for_file: type=lint
mixin _$KeyboardAssistDaoMixin on DatabaseAccessor<AppDatabase> {
  $KeyboardAssistsTable get keyboardAssists => attachedDatabase.keyboardAssists;
  KeyboardAssistDaoManager get managers => KeyboardAssistDaoManager(this);
}

class KeyboardAssistDaoManager {
  final _$KeyboardAssistDaoMixin _db;
  KeyboardAssistDaoManager(this._db);
  $$KeyboardAssistsTableTableManager get keyboardAssists =>
      $$KeyboardAssistsTableTableManager(
        _db.attachedDatabase,
        _db.keyboardAssists,
      );
}

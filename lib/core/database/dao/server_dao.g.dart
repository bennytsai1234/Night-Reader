// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_dao.dart';

// ignore_for_file: type=lint
mixin _$ServerDaoMixin on DatabaseAccessor<AppDatabase> {
  $ServersTable get servers => attachedDatabase.servers;
  ServerDaoManager get managers => ServerDaoManager(this);
}

class ServerDaoManager {
  final _$ServerDaoMixin _db;
  ServerDaoManager(this._db);
  $$ServersTableTableManager get servers =>
      $$ServersTableTableManager(_db.attachedDatabase, _db.servers);
}
